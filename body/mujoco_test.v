module body

import math
import os
import lcl

// Every test sits in a $if mujoco ? block, since the MuJoCo body builds only with -d mujoco and
// `v test .` compiles this file without it (ADR-0008). A test moves the body's clock by moving
// t0_ms back, 40 ms at a time, as two field ticks would.

// far is the default world with the base starting far from its pillar and its human.
fn far() World {
	return World{
		...default_world()
		start: [-4.0, -4.0]
	}
}

// crossing is a world whose one human, of radius r, walks south at speed through the base at the
// origin and on, 0.1 m east of the base's center, with obstacles beside the base.
fn crossing(r f64, speed f64, obstacles []Spot) World {
	return World{
		start:     [0.0, 0.0]
		beacons:   [Spot{
			id:  'b1'
			pos: [3.0, 2.0]
			r:   0.3
		}]
		obstacles: obstacles
		humans:    [
			Human{
				id:       'h1'
				r:        r
				behavior: .waypoints
				reaction: .through
				points:   [[0.1, r + 2.0], [0.1, -r - 3.0]]
				speed:    speed
			},
		]
	}
}

// child is the case a copy of this test binary runs in testsuite_begin, when the test that starts
// it sets BODY_TEST_CHILD: a command with a speed that is not a number, which MuJoCo reports as a
// bad control on the next step.
fn testsuite_begin() {
	$if mujoco ? {
		if os.getenv('BODY_TEST_CHILD') == 'bad command' {
			mut b := new_mujoco(far()) or { exit(3) }
			b.actuate([math.nan(), 0.0]) or { exit(3) }
			b.t0_ms -= 40
			p := b.sense()
			println('percept at ${p.pose}')
			exit(0)
		}
	}
}

// A MuJoCo body is differential: it drives along the heading of its last percept and turns toward
// the Course's heading meanwhile, so the base never slides sideways at the start, and it ends up
// heading and moving where the Course leads.
fn test_a_mujoco_body_drives_along_its_heading_and_turns() {
	$if mujoco ? {
		mut b := new_mujoco(far())!
		assert b.dof() == 2
		assert b.drive() == .differential
		start := b.sense()
		assert start.pose == [-4.0, -4.0]
		assert start.heading == 0.0
		b.actuate([0.5, math.pi / 2.0])!
		b.t0_ms -= 40
		p := b.sense()
		assert p.pose[1] == -4.0 && p.pose[0] > -4.0, '${p.pose}'
		assert p.heading > 0.0 && p.heading < math.pi / 2.0, '${p.heading}'
		mut q := p
		for _ in 0 .. 25 {
			b.actuate([0.5, math.pi / 2.0])!
			b.t0_ms -= 40
			q = b.sense()
		}
		assert math.abs(q.heading - math.pi / 2.0) < 1e-3, '${q.heading}'
		assert lcl.dist(q.vel, [0.0, 0.5]) < 0.01, '${q.vel}'
		assert q.pose[1] > -4.0 + 0.2, '${q.pose}'
	}
}

// Once its last command is 200 ms old a MuJoCo body brakes to a stop and stops turning, as Sim
// does, and so does halt.
fn test_a_mujoco_body_stops_with_its_command() {
	$if mujoco ? {
		for stale in [true, false] {
			mut b := new_mujoco(far())!
			for _ in 0 .. 10 {
				b.actuate([0.5, 0.0])!
				b.t0_ms -= 40
				b.sense()
			}
			b.actuate([0.5, 1.0])!
			if stale {
				b.cmd_ms -= 300
			} else {
				b.halt()
			}
			b.t0_ms -= 20
			heading := b.sense().heading
			mut p := b.sense()
			for _ in 0 .. 10 {
				b.t0_ms -= 40
				p = b.sense()
			}
			assert lcl.norm(p.vel) < 1e-3, '${stale}: ${p.vel}'
			assert math.abs(p.heading - heading) < 0.02, '${stale}: ${p.heading} against ${heading}'
		}
	}
}

// A stall of the field loop pauses the model: one sense takes at most catch_up steps, 50 ms of
// its clock, drops the rest, and the human walks those 50 ms only, while the percept's t_ms stays
// the field unit's clock.
fn test_a_stall_pauses_the_mujoco_body() {
	$if mujoco ? {
		mut b := new_mujoco(default_world())!
		b.sense()
		before := b.steps
		b.t0_ms -= 1000
		p := b.sense()
		assert b.steps - before == catch_up
		assert b.dropped >= 1000 / step_ms - catch_up
		h := p.scene.filter(it.kind == 'human')[0]
		assert h.pos == default_world().humans[0].path(b.steps * step_ms)
		assert math.abs(p.t_ms - lcl.now_ms()) < 1000
		steps := b.steps
		b.sense()
		assert b.steps - steps <= 1
	}
}

// A MuJoCo body reports the world Sim reports, in Sim's order, with its human where the human's
// walk puts it on the model's clock, and carries and releases its payload as Sim does.
fn test_a_mujoco_body_reports_its_world_like_sim() {
	$if mujoco ? {
		mut b := new_mujoco(default_world())!
		mut s := new_sim(default_world(), .differential)
		mut p := b.sense()
		for _ in 0 .. 25 {
			b.t0_ms -= 40
			p = b.sense()
		}
		assert p.scene.map('${it.id} ${it.kind} ${it.r}') == s.sense().scene.map('${it.id} ${it.kind} ${it.r}')
		assert p.scene[2].pos == default_world().humans[0].path(b.steps * step_ms)
		assert p.payload
		assert !p.contact
		b.effect('goto')!
		b.effect('release')!
		assert !b.sense().payload
		b.effect('release') or { assert err.msg() == 'mujoco body: nothing left to release' }
		b.effect('dance') or { assert err.msg() == 'mujoco body: no effector for dance' }
		b.actuate([0.5]) or { assert err.msg() == 'mujoco body: expected 2 dof, got 1' }
	}
}

struct CrossingCase {
	name  string
	world World
	ticks int // of 40 ms, until the human is past
}

// A human walks through a standing MuJoCo body as through Sim's: it touches the body, which holds
// still while they touch and is moved nowhere, on the open floor, beside a pillar 1 cm south of
// its rim, where a human that pushed the base would squeeze it into the pillar and fling it out
// at about 8 m/s, and with the largest and fastest human a world allows.
fn test_a_human_walks_through_a_mujoco_body() {
	$if mujoco ? {
		pillar := Spot{
			id:  'o1'
			pos: [0.0, -(body_radius + 0.01 + 0.45)]
			r:   0.45
		}
		cases := [
			CrossingCase{'the open floor', crossing(0.3, 1.0, []), 150},
			CrossingCase{'beside a pillar', crossing(0.3, walk_max, [pillar]), 100},
			CrossingCase{'the largest human', crossing(max_radius, walk_max, [pillar]), 300},
		]
		for c in cases {
			mut b := new_mujoco(c.world)!
			mut touched := false
			mut p := b.sense()
			for _ in 0 .. c.ticks {
				b.t0_ms -= 40
				p = b.sense()
				touched = touched || p.contact
				assert p.pose == c.world.start && lcl.norm(p.vel) == 0.0, '${c.name}: ${p.pose} ${p.vel}'
			}
			assert touched, c.name
			assert !p.contact, c.name
		}
	}
}

// A MuJoCo body driving into a standing human holds still once they touch, as Sim does, after
// braking over its stopping distance at 0.5 m/s, 0.025 m by mjcf's gain and mass.
fn test_a_mujoco_body_holds_while_a_human_touches_it() {
	$if mujoco ? {
		w := World{
			start:   [0.0, 0.0]
			beacons: [Spot{
				id:  'b1'
				pos: [3.0, 2.0]
				r:   0.3
			}]
			humans:  [
				Human{
					id:       'h1'
					r:        0.3
					behavior: .stand
					reaction: .through
					pos:      [1.5, 0.0]
				},
			]
		}
		mut b := new_mujoco(w)!
		mut p := b.sense()
		mut first := []f64{}
		for _ in 0 .. 75 {
			b.actuate([0.5, 0.0])!
			b.t0_ms -= 40
			p = b.sense()
			if p.contact && first.len == 0 {
				first = p.pose.clone()
			}
		}
		assert first.len == 2
		assert p.contact
		assert lcl.norm(p.vel) < 1e-3, '${p.vel}'
		assert p.pose[0] < 1.5 - 0.3 - body_radius + 0.025 + 1e-3, '${p.pose}'
	}
}

// A bad number in a step ends the run with one line before sense builds a percept, so no NaN
// reaches the armor, the recorder or HQ.
fn test_a_bad_step_ends_the_run_before_a_percept() {
	$if mujoco ? {
		res := os.execute('BODY_TEST_CHILD="bad command" ${os.quoted_path(os.executable())}')
		assert res.exit_code == 1, res.output

		// v test -stats has the copy print which file it tests first.
		last := res.output.trim_space().split_into_lines().last()
		assert last == 'field: mujoco: Nan, Inf or huge value in CTRL at ACTUATOR 0. The simulation is unstable. Time = 0.0020 s.'
		assert !res.output.contains('percept'), res.output
	}
}

// mjcf writes every obstacle and human of a world with its radius, and no beacon.
fn test_mjcf() {
	$if mujoco ? {
		w := World{
			...default_world()
			obstacles: [Spot{
				id:  'o1'
				pos: [0.0, -0.3]
				r:   0.8
			}, Spot{
				id:  'o2'
				pos: [2.0, -2.5]
				r:   0.6
			}]
		}
		x := mjcf(w)
		assert x.count('type="cylinder"') == 3
		assert x.contains('pos="2.0 -2.5 0.2" size="0.6 0.2"')
		assert x.count('mocap="true"') == 1
		assert x.count('contype="0" conaffinity="0"') == 1
		assert x.contains('size="0.3 0.2"')
		assert x.contains('<body name="base" pos="-3.5 -2.5 0.2">')
		assert !x.contains('3.0 2.0')
	}
}
