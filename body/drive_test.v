module body

import math

struct SteerCase {
	name    string
	u       []f64
	heading f64
	want    Course
}

fn test_steer() {
	off := math.pi / 9.0 // 20 degrees, inside align
	back := [-0.5, -0.01] // just past -x, at about 0.02 - pi
	across := Course{
		speed:   math.hypot(back[0], back[1]) * math.cos(0.1 + math.atan(0.02))
		heading: math.atan2(back[1], back[0])
	}
	cases := [
		SteerCase{'drives along its heading', [0.5, 0.0], 0.0, Course{0.5, 0.0}},
		SteerCase{'drives the projection within align', [0.5, 0.0], off, Course{0.5 * math.cos(off), 0.0}},
		SteerCase{'turns in place beyond align', [0.0, 0.5], 0.0, Course{0.0, math.pi / 2.0}},
		SteerCase{'turns in place to a command behind it', [-0.5, 0.0], 0.0, Course{0.0, math.pi}},
		SteerCase{'stands on a zero command and keeps its heading', [0.0, 0.0], 1.0, Course{0.0, 1.0}},
		SteerCase{'measures the error the short way across pi', back, math.pi - 0.1, across},
	]
	for c in cases {
		got := steer(c.u, c.heading)
		assert math.abs(got.speed - c.want.speed) < 1e-12, '${c.name}: ${got}'
		assert math.abs(got.heading - c.want.heading) < 1e-12, '${c.name}: ${got}'
	}
}

// A differential body never moves faster than the command it was steered by, at any heading.
fn test_steer_never_speeds_up_a_command() {
	for i in 0 .. 72 {
		h := f64(i) * math.pi / 36.0 - math.pi
		c := steer([0.3, 0.4], h)
		assert c.speed >= 0.0 && c.speed <= 0.5 + 1e-12, '${h}'
		assert math.abs(norm2(c.motion(h)) - c.speed) < 1e-12, '${h}'
	}
}

fn norm2(v []f64) f64 {
	return math.sqrt(v[0] * v[0] + v[1] * v[1])
}

struct TurnedCase {
	name    string
	heading f64
	aim     f64
	dt      f64
	want    f64
}

fn test_turned() {
	step := turn_rate * 0.02
	cases := [
		TurnedCase{'lands on an aim within one step', 0.0, step / 2.0, 0.02, step / 2.0},
		TurnedCase{'lands on an aim exactly one step away', 0.0, step, 0.02, step},
		TurnedCase{'turns one step toward a far aim', 0.0, 1.0, 0.02, step},
		TurnedCase{'turns clockwise toward an aim clockwise of it', 0.0, -1.0, 0.02, -step},
		TurnedCase{'turns the short way across pi', math.pi - 0.01, -math.pi + 0.01, 0.002,
			math.pi - 0.01 + turn_rate * 0.002},
		TurnedCase{'wraps past pi', math.pi - 0.01, -math.pi + 0.1, 0.02, -math.pi - 0.01 + step},
		TurnedCase{'stays on its aim', 1.0, 1.0, 0.02, 1.0},
		TurnedCase{'stays put in no time', 0.0, 1.0, 0.0, 0.0},
	]
	for c in cases {
		got := turned(c.heading, c.aim, c.dt)
		assert math.abs(got - c.want) < 1e-12, '${c.name}: ${got}'
	}
}

// lead grows with speed from nothing at rest, and at v_max a differential body closes on a solid
// by under 7 cm while it turns onto the slide.
fn test_lead() {
	assert lead(0.0) == 0.0
	assert math.abs(lead(1.0) - 0.0669872981) < 1e-9
	assert math.abs(lead(0.5) - lead(1.0) / 2.0) < 1e-12
}
