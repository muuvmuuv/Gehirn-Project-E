module body

import math
import lcl

// Drive is how a body moves, which main.v reads from DRIVE and armor.Armor.drive asks every body
// for. A holonomic body takes a planar velocity and slides along it in any direction. A
// differential body is a robot base on two wheels: it takes a Course, moves only along its
// heading and turns in place, so it never slides sideways. The stack above the armor works in
// planar velocities for both, and steer maps one onto a differential body.
pub enum Drive {
	holonomic
	differential
}

// turn_rate is how fast a differential body turns toward a Course's heading, in rad/s: about 115
// degrees a second, so it turns around in 1.6 s.
pub const turn_rate = 2.0

// align is how far a differential body's heading may lie off a command's direction while steer
// lets it drive, in rad: 30 degrees. Further off it turns in place first.
pub const align = math.pi / 6.0

// Course is the command a differential body takes: a speed along its heading, and the heading it
// turns toward at turn_rate meanwhile. armor.Armor.drive makes it with steer and actuates it as
// [speed, heading].
pub struct Course {
pub:
	speed   f64 // m/s along the body's heading, never backward
	heading f64 // rad, counterclockwise from +x, -pi to pi
}

// steer is the body adapter of PLAN's Phase 3, the turn then drive rule: it maps the planar
// velocity u, x and y in m/s, onto a differential body at heading. The body turns toward u and
// drives only while its heading lies within align of u's direction, at u's speed projected onto
// its heading, so it never moves faster than u. A zero u stands still and keeps the heading.
// armor.Armor.drive steers every differential body through it, Sim and the simulator's base of
// Phase 3 Task 4 alike, so it reads nothing of a body but its heading.
pub fn steer(u []f64, heading f64) Course {
	speed := lcl.norm(u)
	if speed == 0.0 {
		return Course{
			heading: heading
		}
	}
	aim := math.atan2(u[1], u[0])
	off := wrap(aim - heading)
	if math.abs(off) > align {
		return Course{
			heading: aim
		}
	}
	return Course{
		speed:   speed * math.cos(off)
		heading: aim
	}
}

// motion is the planar velocity of a differential body at heading under c, which Sim moves it
// with until the next command and armor.Armor.drive checks against every restraint first.
pub fn (c Course) motion(heading f64) []f64 {
	return [c.speed * math.cos(heading), c.speed * math.sin(heading)]
}

// shy is how far, in rad, armor.Armor.drive turns a differential body's command away from a solid
// or a human it slid the command along: 5 degrees. Steered exactly along the slide, the body moves
// toward a walking human again as soon as the human has moved a hair, which the armor refuses, so
// it would stand and turn while the human walks into it. shy covers the degree or less a tick by
// which the walking human of Sim's scene turns about a body inside human_stop.
pub const shy = math.pi / 36.0

// lead is how far, in m, a differential body at speed m/s closes on a solid while it turns from
// align off a slide along the solid onto it at turn_rate. armor.Armor.drive starts that slide this
// much early for a differential body, so it reaches solid_keep or human_stop heading along the
// slide; heading into the solid there, it would have to stop and turn, and then speed up again.
pub fn lead(speed f64) f64 {
	return speed * (1.0 - math.cos(align)) / turn_rate
}

// turned is the heading a differential body reaches from heading in dt seconds, turning toward aim
// at turn_rate the short way round. It lands on aim exactly once aim lies within one step, so a
// body steered along a slide past a pillar ends up on it and drives, where a turn that only
// closes in would leave it a hair toward the pillar, which the armor refuses, for ever.
fn turned(heading f64, aim f64, dt f64) f64 {
	off := wrap(aim - heading)
	step := turn_rate * dt
	if math.abs(off) <= step {
		return aim
	}
	return wrap(heading + math.copysign(step, off))
}

// wrap is the angle a, in rad, brought into -pi to pi.
fn wrap(a f64) f64 {
	return math.atan2(math.sin(a), math.cos(a))
}
