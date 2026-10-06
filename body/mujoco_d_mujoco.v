module body

import math
import strings
import lcl
import mujoco

// step_ms is MuJoCo's timestep in milliseconds, which mjcf writes into the model.
const step_ms = 2

// catch_up is the most steps one sense takes, 50 ms of the model's clock: a field loop that
// stalled longer finds the model paused rather than run fast (ADR-0008, Stepping and timing).
const catch_up = 25

// settle is how fast the base's hinge closes on the commanded heading, in seconds: within
// turn_rate * settle of it the turn slows in proportion. It is four times the hinge actuator's
// time constant, so the turn lands on the heading without overshoot.
const settle = 0.04

// base_mass is the base's mass in kg, which mjcf writes and stopping brakes.
const base_mass = 20.0

// slide_gain is each slide's velocity gain in N s/m, which mjcf writes: the slide follows its
// command with the time constant base_mass / slide_gain, 0.05 s.
const slide_gain = 400.0

// slide_force is each slide's force limit in N, which mjcf writes: it brakes the base at
// slide_force / base_mass, 10 m/s², at most.
const slide_force = 200.0

// Mujoco is a differential base on MuJoCo in a World, the Body main.v builds with new_mujoco
// when BODY is mujoco (ADR-0008). Planar joints, a slide along x, a slide along y and a hinge
// about z, carry a cylinder of body_radius, each with a velocity actuator and a force limit, so
// the slides move it along the world's axes whatever its heading. The armor steers it as it
// steers a differential Sim: actuate sets the slides to the Course's speed along the heading of
// the percept the armor checked, held until the next actuate, and the hinge toward the Course's
// heading at turn_rate. The world's humans are mocap bodies that walk as Sim moves them, on the
// model's clock, and touch the base by Sim's rule, which holds the base while one touches it.
pub struct Mujoco {
	world World
mut:
	model   &mujoco.Model
	base    int      // the base's geom
	walkers []Walker // one per human of world, in its order
	heading f64      // rad, of the last percept, which armor.Armor.drive checked
	aim     f64      // rad, the heading the hinge turns toward
	motion  []f64 = [0.0, 0.0] // m/s, the slides' command until the next actuate
	held    bool // a human touched the base at the last step
	payload bool = true
	contact bool
	t0_ms   i64
	cmd_ms  i64
	steps   i64 // taken since new_mujoco
	dropped i64 // steps sense let pass without taking them
}

// new_mujoco builds the base at the start of world w, facing +x with its payload aboard, writes
// the model from w and starts the world's clock. main.v hands it the world Sim would play. A
// model MuJoCo cannot compile returns its message.
pub fn new_mujoco(w World) !&Mujoco {
	model := mujoco.load(mjcf(w))!
	return &Mujoco{
		world:   w
		model:   model
		base:    model.geom('base')
		walkers: w.humans.map(Walker{ at: it.path(0) })
		t0_ms:   lcl.now_ms()
	}
}

// dof is the number of velocity channels the base takes, a Course's speed and heading.
pub fn (b &Mujoco) dof() int {
	return 2
}

// drive is how the base moves, always differential.
pub fn (b &Mujoco) drive() Drive {
	return .differential
}

// stopping is how far the base may move along a motion at speed m/s that a command sets, in
// meters, before it stands once a later command takes the motion out: catch_up steps at that
// speed, the most one sense runs the command before the next command can replace it, whatever
// the field loop's tick, 5 cm from 1 m/s, and then its braking. A slide brakes at its force limit
// down to slide_force / slide_gain, 0.5 m/s, below which it closes in on its command with the time
// constant base_mass / slide_gain, so it brakes 6.25 cm from 1 m/s and 2.5 cm from 0.5 m/s. Each
// slide brakes its own axis, so a motion between the axes stops sooner. A NaN speed gives NaN, on
// which the armor halts the base.
pub fn (b &Mujoco) stopping(speed f64) f64 {
	tau := base_mass / slide_gain
	knee := slide_force / slide_gain
	hold := speed * f64(catch_up * step_ms) / 1000.0
	if speed <= knee {
		return hold + speed * tau
	}
	return hold + (speed * speed - knee * knee) * base_mass / (2.0 * slide_force) + knee * tau
}

// sense steps the model up to the wall clock's time since new_mujoco, less what it dropped, at
// most catch_up steps, drops the rest, and reports where it left the base. It zeroes the controls
// first once the last actuate is 200 ms old, as a motor controller does, and walks the humans
// before every step. The percept's t_ms is the field unit's clock.
pub fn (mut b Mujoco) sense() lcl.Percept {
	now := lcl.now_ms()
	if now - b.cmd_ms > 200 {
		b.halt()
	}
	mut due := (now - b.t0_ms) / step_ms - b.dropped
	if due > b.steps + catch_up {
		b.dropped += due - b.steps - catch_up
		due = b.steps + catch_up
	}

	// lcl.now_ms reads the wall clock, which can step back; the model then waits for it.
	stepped := due > b.steps
	for b.steps < due {
		b.walk()
		b.model.step()
		b.steps++
	}
	if stepped {
		b.contact = b.held || b.model.touching(b.base)
	}
	q := b.model.qpos()
	v := b.model.qvel()
	b.heading = wrap(q[2])
	return lcl.Percept{
		t_ms:    now
		pose:    b.pose()
		vel:     [v[0], v[1]]
		scene:   b.world.scene(b.walkers)
		payload: b.payload
		contact: b.contact
		heading: b.heading
	}
}

// actuate takes a Course as [speed, heading] and lapses after 200 ms unless refreshed.
pub fn (mut b Mujoco) actuate(u []f64) ! {
	if u.len != 2 {
		return error('mujoco body: expected 2 dof, got ${u.len}')
	}
	b.motion = Course{u[0], u[1]}.motion(b.heading)
	b.aim = u[1]
	b.cmd_ms = lcl.now_ms()
}

// effect runs the effector behind a verb.
pub fn (mut b Mujoco) effect(verb string) ! {
	b.payload = effector('mujoco body', verb, b.payload)!
}

// halt zeroes the slides' command and stops the turn where the base heads now; the actuators
// brake it within their force limits.
pub fn (mut b Mujoco) halt() {
	b.motion = [0.0, 0.0]
	b.aim = b.model.qpos()[2]
}

// pose is the base's x and y in meters.
fn (b &Mujoco) pose() []f64 {
	q := b.model.qpos()
	return [b.world.start[0] + q[0], b.world.start[1] + q[1]]
}

// walk moves every human one step on, to the model's clock after the next step, and sets the
// controls for it: the slides' to motion, or to zero while a human touches the base by Sim's rule,
// as Sim holds its body, and the hinge's toward aim.
fn (mut b Mujoco) walk() {
	pose := b.pose()
	b.held = false
	for i, h in b.world.humans {
		b.walkers[i].step(h, (b.steps + 1) * step_ms, step_ms, pose)
		b.model.set_mocap(i, b.walkers[i].at[0], b.walkers[i].at[1])
		b.held = b.held || touches(pose, b.walkers[i].at, h.r)
	}
	m := if b.held { [0.0, 0.0] } else { b.motion }
	b.model.set_ctrl(0, m[0])
	b.model.set_ctrl(1, m[1])
	off := wrap(b.aim - b.model.qpos()[2])
	b.model.set_ctrl(2, math.max(-turn_rate, math.min(turn_rate, off / settle)))
}

// mjcf is the model of world w: the base at its start, every obstacle a static cylinder of its
// radius and every human a mocap capsule of its radius where its walk starts, all at one height,
// with no thread, plugin or floor, and autoreset off. A beacon is no geom, since nothing touches
// it, and a human's capsule takes part in no contact: a mocap body pushes with no limit on its
// force, so a human walking through a base beside a pillar would squeeze the base into the pillar
// and fling it out at about 8 m/s. The base weighs base_mass, so slide_gain gives the slides a
// time constant of 0.05 s, and the hinge's gain of 62.5 one of 0.01 s on the cylinder's
// 0.625 kg m²; force limits of slide_force and 100 N m cap the push as a motor's saturation does.
// ponytail: planar joints, not wheels, as ADR-0008 decides; wheels on a floor, with slip and a
// caster, once Open question 1 names the first real base.
fn mjcf(w World) string {
	z := 0.2
	mut x := strings.new_builder(1024)
	x.write_string('<mujoco model="gehirn"><compiler usethread="false"/>')
	x.write_string('<option timestep="${f64(step_ms) / 1000.0}"><flag autoreset="disable"/></option><worldbody>')
	x.write_string('<body name="base" pos="${w.start[0]} ${w.start[1]} ${z}">')
	x.write_string('<joint name="x" type="slide" axis="1 0 0"/><joint name="y" type="slide" axis="0 1 0"/><joint name="yaw" type="hinge" axis="0 0 1"/>')
	x.write_string('<geom name="base" type="cylinder" size="${body_radius} ${z}" mass="${base_mass}"/></body>')
	for o in w.obstacles {
		x.write_string('<geom type="cylinder" pos="${o.pos[0]} ${o.pos[1]} ${z}" size="${o.r} ${z}"/>')
	}
	for h in w.humans {
		at := h.path(0)
		x.write_string('<body mocap="true" pos="${at[0]} ${at[1]} ${z}"><geom type="capsule" size="${h.r} ${z}" contype="0" conaffinity="0"/></body>')
	}
	x.write_string('</worldbody><actuator>')
	for joint in ['x', 'y'] {
		x.write_string('<velocity joint="${joint}" kv="${slide_gain}" forcerange="${-slide_force} ${slide_force}"/>')
	}
	x.write_string('<velocity joint="yaw" kv="62.5" forcerange="-100 100"/>')
	x.write_string('</actuator></mujoco>')
	return x.str()
}
