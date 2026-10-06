module body

import math
import lcl

// sensed is s's percept dt_ms after its last one, as if that much time had passed.
fn sensed(mut s Sim, dt_ms i64) lcl.Percept {
	s.last_ms = lcl.now_ms() - dt_ms
	return s.sense()
}

// Far from the scene's pillar and human, so nothing holds the body still.
const clear = [-4.0, -4.0]

// A holonomic Sim moves along its command in any direction, never turns, and reports no heading.
fn test_a_holonomic_sim_slides_along_its_command() {
	mut s := new_sim(clear, .holonomic)
	s.actuate([0.0, 0.5])!
	p := sensed(mut s, 100)
	assert p.vel == [0.0, 0.5]
	assert p.pose[0] == clear[0] && p.pose[1] > clear[1]
	assert p.heading == 0.0
}

// A differential Sim moves only along the heading it had when commanded, then turns toward the
// Course's heading at turn_rate, so it never slides sideways.
fn test_a_differential_sim_drives_along_its_heading_and_turns() {
	mut s := new_sim(clear, .differential)
	s.actuate([0.5, math.pi / 2.0])!
	p := sensed(mut s, 100)
	assert p.vel == [0.5, 0.0]
	assert p.pose[1] == clear[1] && p.pose[0] > clear[0]
	assert p.heading > 0.0 && p.heading < math.pi / 2.0

	s.actuate([0.5, math.pi / 2.0])!
	q := sensed(mut s, 100)
	step := lcl.sub(q.pose, p.pose)
	assert math.abs(math.atan2(step[1], step[0]) - p.heading) < 1e-9
	assert q.vel == Course{0.5, 0.0}.motion(p.heading)
}

// A differential Sim stops turning when it halts and when its command goes stale, as it stops
// moving.
fn test_a_differential_sim_stops_turning_with_its_command() {
	mut s := new_sim(clear, .differential)
	s.actuate([0.0, math.pi])!
	s.halt()
	assert sensed(mut s, 100).heading == 0.0

	s.actuate([0.0, math.pi])!
	s.cmd_ms -= 300
	p := sensed(mut s, 100)
	assert p.heading == 0.0
	assert p.pose == clear
}

// A wall clock stepped back between two senses moves and turns neither body, and a holonomic one
// still reports no heading.
fn test_a_sim_stands_while_the_clock_steps_back() {
	for drive in [Drive.holonomic, .differential] {
		mut s := new_sim(clear, drive)
		s.actuate([0.3, 1.0])!
		p := sensed(mut s, -100)
		assert p.pose == clear, '${drive}'
		assert p.heading == 0.0, '${drive}'
	}
}
