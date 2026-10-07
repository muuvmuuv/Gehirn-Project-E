// The robot API. Anything that can sense, take a velocity command, run an effector and stop
// can wear the armor: this simulator today, a Zenoh or ROS 2 bridge to real hardware later,
// or a Vinix kernel driver behind /dev/eva0.
module body

import math
import lcl

// Body is the robot API, anything that can sense, take a velocity command, run an effector and
// stop. Sim implements it, and armor.restrain takes the one main.v builds. stopping is how far,
// in meters, the body may move along a motion at a speed in m/s that a command sets before it
// stands once a later command takes the motion out: until the next command and through its
// braking after, whatever the field loop's tick. A body that stops with the command that takes a
// motion out reports the most one sense carries it. armor.Armor.drive widens its keeps and the
// fence by it.
pub interface Body {
	dof() int
	drive() Drive
	stopping(speed f64) f64
mut:
	sense() lcl.Percept
	actuate(u []f64) !
	effect(verb string) !
	halt()
}

// stride_s is the most time, in seconds, one sense moves and turns Sim: main.v tick, the field
// loop's 20 ms, and the 10 ms by which its sleep wakes late on the Mac, so an ordinary tick moves
// the body all of it, while a longer one, a stall's or a loaded host's, leaves the body standing
// for the rest while its humans walk on, where body.Mujoco's catch_up pauses the humans too.
const stride_s = 0.03

// Sim is a planar point body with a payload in a World, the Body main.v builds with new_sim, on
// either Drive. It integrates whenever it is sensed, stride_s at most, and, like any real motor
// controller, zeroes its velocity by itself when commands go stale. The world's humans walk on at
// each sense too, all of the time since the last, on the world's clock.
pub struct Sim {
	world World
	drive Drive
mut:
	pose      []f64
	heading   f64 // rad, counterclockwise from +x
	aim       f64 // rad, the heading a differential body turns toward
	vel       []f64 = [0.0, 0.0]
	payload   bool  = true
	contact   bool
	t0_ms     i64
	last_ms   i64
	cmd_ms    i64
	walkers   []Walker // one per human of world and then per moving obstacle, each in its order
	walked_ms i64
}

// new_sim puts a fresh body on drive at the start of world w, payload aboard, and starts the
// world's clock. main.v hands it default_world or the world WORLD names, with the start START
// sets, and drive from DRIVE. It faces +x, east, the zero heading of a planar robot and the one a
// holonomic body keeps, which from the default world's start lies 35 degrees off the beacon.
pub fn new_sim(w World, drive Drive) &Sim {
	now := lcl.now_ms()
	return &Sim{
		world:     w
		drive:     drive
		pose:      w.start.clone()
		t0_ms:     now
		last_ms:   now
		walkers:   w.walkers()
		walked_ms: now
	}
}

// dof is the number of velocity channels the body takes: x and y, or a Course's speed and heading.
pub fn (s &Sim) dof() int {
	return 2
}

// drive is how the body moves, the Drive it was built on.
pub fn (s &Sim) drive() Drive {
	return s.drive
}

// stopping is how far the body moves at speed until the next command, stride_s of it at most
// whatever the tick: it moves with exactly the motion of its last command and stops with the
// command that takes a motion out.
pub fn (s &Sim) stopping(speed f64) f64 {
	return speed * stride_s
}

// sense integrates the motion since the last call, stride_s of it at most, and reports where it
// left the body. A differential body moves along the heading it had when commanded, as
// armor.Armor.drive checked, then turns, which a round body may do wherever it stands, even in
// contact.
pub fn (mut s Sim) sense() lcl.Percept {
	now := lcl.now_ms()

	// lcl.now_ms reads the wall clock, which can step back.
	dt := math.min(stride_s, math.max(0.0, f64(now - s.last_ms) / 1000.0))
	s.last_ms = now
	if now - s.cmd_ms > 200 {
		s.vel = [0.0, 0.0]
		s.aim = s.heading
	}
	next := [s.pose[0] + s.vel[0] * dt, s.pose[1] + s.vel[1] * dt]
	scene := s.scene(now)
	s.contact = false
	for e in scene {
		// A landing zone is air until its object lands, so it holds nothing up.
		if e.kind != 'beacon' && e.kind != 'impact' && touches(next, e.pos, e.r) {
			s.contact = true
		}
	}
	if !s.contact {
		s.pose = next
	}
	match s.drive {
		.holonomic {}
		.differential {
			s.heading = turned(s.heading, s.aim, dt)
		}
	}

	return lcl.Percept{
		t_ms:    now
		pose:    s.pose.clone()
		vel:     s.vel.clone()
		scene:   scene
		ground:  s.world.patches()
		payload: s.payload
		contact: s.contact
		heading: s.heading
	}
}

// actuate sets the velocity command: the planar velocity of a holonomic body, or the speed and
// heading of a differential body's Course. It lapses after 200 ms unless refreshed.
pub fn (mut s Sim) actuate(u []f64) ! {
	if u.len != 2 {
		return error('sim: expected 2 dof, got ${u.len}')
	}
	match s.drive {
		.holonomic {
			s.vel = u.clone()
		}
		.differential {
			s.vel = Course{u[0], u[1]}.motion(s.heading)
			s.aim = u[1]
		}
	}

	s.cmd_ms = lcl.now_ms()
}

// effect runs the effector behind a verb.
pub fn (mut s Sim) effect(verb string) ! {
	s.payload = effector('sim', verb, s.payload)!
}

// effector runs the effector behind verb on a body that holds payload, for Sim and the MuJoCo
// body, and returns whether the body still holds it. who names the body in an error.
fn effector(who string, verb string, payload bool) !bool {
	match verb {
		'release' {
			if !payload {
				return error('${who}: nothing left to release')
			}
			return false
		}
		'goto', 'hold' {
			return payload
		}
		else {
			return error('${who}: no effector for ${verb}')
		}
	}
}

// halt stops the body at once, turning included.
pub fn (mut s Sim) halt() {
	s.vel = [0.0, 0.0]
	s.aim = s.heading
}

// scene is the world at now, with every human and moving obstacle walked on to now and each one
// walking with the velocity of its last step, and each falling object's zone or crater on the
// world's clock. On default_world it is beacon b1, pillar o1 and human h1 on its loop at every
// time.
fn (mut s Sim) scene(now i64) []lcl.Entity {
	// lcl.now_ms reads the wall clock, which can step back.
	dt_ms := math.max(i64(0), now - s.walked_ms)
	for i, h in s.world.humans {
		s.walkers[i].step(h, now - s.t0_ms, dt_ms, s.pose)
	}
	for j, o in s.world.moving {
		s.walkers[s.world.humans.len + j].step(o, now - s.t0_ms, dt_ms, s.pose)
	}
	s.walked_ms = now
	return s.world.scene(s.walkers, now - s.t0_ms)
}

// walkers is a Walker for each human of w where its walk starts, then one for each moving
// obstacle, the order Sim.scene and the MuJoCo body step them in.
fn (w World) walkers() []Walker {
	mut all := w.humans.map(Walker{ at: it.path(0) })
	all << w.moving.map(Walker{ at: it.path(0) })
	return all
}

// scene is w as a percept's scene clock_ms after the world began, with its humans and moving
// obstacles where walkers, in the order World.walkers makes them, have them, each walking with its
// walker's velocity: its beacons, standing obstacles, humans, moving obstacles, ditches and falling
// objects in that order, each kind in the world's order. A falling object is its landing zone, of
// kind impact with the seconds until it lands, until clock_ms reaches its landing, and its crater,
// a ditch, from then on. scripts/scenes/ep12-sahaquiel.sh waits on each crater's first recorder
// line, as `"id":"shard-1","kind":"ditch"`.
fn (w World) scene(walkers []Walker, clock_ms i64) []lcl.Entity {
	mut scene := []lcl.Entity{cap: w.beacons.len + w.obstacles.len + walkers.len + w.ditches.len +
		w.falling.len}
	for b in w.beacons {
		scene << lcl.Entity{
			id:   b.id
			kind: 'beacon'
			pos:  b.pos.clone()
			r:    b.r
		}
	}
	for o in w.obstacles {
		scene << lcl.Entity{
			id:   o.id
			kind: 'obstacle'
			pos:  o.pos.clone()
			r:    o.r
		}
	}
	for i, h in w.humans {
		scene << lcl.Entity{
			id:   h.id
			kind: 'human'
			pos:  walkers[i].at.clone()
			r:    h.r
			vel:  walkers[i].vel.clone()
		}
	}
	for j, o in w.moving {
		k := w.humans.len + j
		scene << lcl.Entity{
			id:   o.id
			kind: 'obstacle'
			pos:  walkers[k].at.clone()
			r:    o.r
			vel:  walkers[k].vel.clone()
		}
	}
	for d in w.ditches {
		scene << lcl.Entity{
			id:   d.id
			kind: 'ditch'
			pos:  d.pos.clone()
			r:    d.r
		}
	}
	for f in w.falling {
		left := f.lands - f64(clock_ms) / 1000.0
		scene << lcl.Entity{
			id:       f.id
			kind:     if left > 0.0 { 'impact' } else { 'ditch' }
			pos:      f.pos.clone()
			r:        f.r
			lands_in: math.max(0.0, left)
		}
	}
	return scene
}

// patches is w's ground as a percept carries it, apart from the scene: entities of kind ground,
// each with its factor, in the world's order.
fn (w World) patches() []lcl.Entity {
	return w.ground.map(lcl.Entity{
		id:     it.id
		kind:   'ground'
		pos:    it.pos.clone()
		r:      it.r
		factor: it.factor
	})
}
