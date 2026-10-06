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

// Sim is a planar point body with a payload, the Body main.v builds with new_sim, on either Drive.
// It integrates whenever it is sensed and, like any real motor controller, zeroes its velocity by
// itself when commands go stale.
pub struct Sim {
	drive Drive
mut:
	pose    []f64
	heading f64 // rad, counterclockwise from +x
	aim     f64 // rad, the heading a differential body turns toward
	vel     []f64 = [0.0, 0.0]
	payload bool  = true
	contact bool
	t0_ms   i64
	last_ms i64
	cmd_ms  i64
}

// new_sim puts a fresh body on drive at start, x and y in meters, payload aboard. main.v reads
// start from START, which defaults to the west end of the scene, and drive from DRIVE. It faces
// +x, east, the zero heading of a planar robot and the one a holonomic body keeps, which from
// START's default lies 35 degrees off the beacon.
pub fn new_sim(start []f64, drive Drive) &Sim {
	now := lcl.now_ms()
	return &Sim{
		drive:   drive
		pose:    start.clone()
		t0_ms:   now
		last_ms: now
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
		if e.kind != 'beacon' && lcl.dist(next, e.pos) < e.r + 0.25 {
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
	match verb {
		'release' {
			if !s.payload {
				return error('sim: nothing left to release')
			}
			s.payload = false
		}
		'goto', 'hold' {}
		else {
			return error('sim: no effector for ${verb}')
		}
	}
}

// halt stops the body at once, turning included.
pub fn (mut s Sim) halt() {
	s.vel = [0.0, 0.0]
	s.aim = s.heading
}

// scene is a beacon to deliver to, a pillar across the direct route and a human walking a loop
// that passes close to both. tools/scenarios.json copies it with the human standing still.
fn (s &Sim) scene(now i64) []lcl.Entity {
	a := f64(now - s.t0_ms) / 1000.0 * 0.3
	return [
		lcl.Entity{
			id:   'b1'
			kind: 'beacon'
			pos:  [3.0, 2.0]
			r:    0.3
		},
		lcl.Entity{
			id:   'o1'
			kind: 'obstacle'
			pos:  [0.0, -0.3]
			r:    0.8
		},
		lcl.Entity{
			id:   'h1'
			kind: 'human'
			pos:  [0.8 + 1.8 * math.cos(a), 1.2 + 1.2 * math.sin(a)]
			r:    0.3
		},
	]
}
