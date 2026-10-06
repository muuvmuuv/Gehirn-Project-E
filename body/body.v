// The robot API. Anything that can sense, take a velocity command, run an effector and stop
// can wear the armor: this simulator today, a Zenoh or ROS 2 bridge to real hardware later,
// or a Vinix kernel driver behind /dev/eva0.
module body

import math
import lcl

// Body is the robot API, anything that can sense, take a velocity command, run an effector and
// stop. Sim implements it, and armor.restrain takes the one main.v builds.
pub interface Body {
	dof() int
	drive() Drive
mut:
	sense() lcl.Percept
	actuate(u []f64) !
	effect(verb string) !
	halt()
}

// Sim is a planar point body with a payload in a World, the Body main.v builds with new_sim, on
// either Drive. It integrates whenever it is sensed and, like any real motor controller, zeroes
// its velocity by itself when commands go stale. The world's humans walk on at each sense too.
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
	walkers   []Walker // one per human of world, in its order
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
		walkers:   w.humans.map(Walker{ at: it.path(0) })
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

// sense integrates the motion since the last call and reports where it left the body. A
// differential body moves along the heading it had when commanded, as armor.Armor.drive checked,
// then turns, which a round body may do wherever it stands, even in contact.
pub fn (mut s Sim) sense() lcl.Percept {
	now := lcl.now_ms()

	// lcl.now_ms reads the wall clock, which can step back.
	dt := math.max(0.0, f64(now - s.last_ms) / 1000.0)
	s.last_ms = now
	if now - s.cmd_ms > 200 {
		s.vel = [0.0, 0.0]
		s.aim = s.heading
	}
	next := [s.pose[0] + s.vel[0] * dt, s.pose[1] + s.vel[1] * dt]
	scene := s.scene(now)
	s.contact = false
	for e in scene {
		if e.kind != 'beacon' && touches(next, e.pos, e.r) {
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

// scene is the world at now, with every human walked on to now. On default_world it is beacon
// b1, pillar o1 and human h1 on its loop at every time.
fn (mut s Sim) scene(now i64) []lcl.Entity {
	// lcl.now_ms reads the wall clock, which can step back.
	dt_ms := math.max(i64(0), now - s.walked_ms)
	for i, h in s.world.humans {
		s.walkers[i].step(h, now - s.t0_ms, dt_ms, s.pose)
	}
	s.walked_ms = now
	return s.world.scene(s.walkers)
}

// scene is w as a percept's scene, with its humans where walkers, one per human, have them: its
// beacons, obstacles and humans in that order, each kind in the world's order.
fn (w World) scene(walkers []Walker) []lcl.Entity {
	mut scene := []lcl.Entity{cap: w.beacons.len + w.obstacles.len + walkers.len}
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
		}
	}
	return scene
}
