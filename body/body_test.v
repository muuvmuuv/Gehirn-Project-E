module body

import math
import lcl

// today is the scene Sim played before worlds were files, copied with its float expressions in
// their order. default_world has to give it bit for bit at every time, so every earlier
// measurement stays comparable.
fn today(t0_ms i64, now i64) []lcl.Entity {
	a := f64(now - t0_ms) / 1000.0 * 0.3
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

// bits is e with the exact bits of its numbers, so a comparison tells every last digit apart.
fn bits(e lcl.Entity) string {
	return '${e.id} ${e.kind} ${e.pos.map(math.f64_bits(it))} ${math.f64_bits(e.r)}'
}

// The default world is today's at every time: ids, kinds, radii and the order b1, o1, h1, and
// positions to the bit over six loops of h1 every 7 ms, then an hour, a day and 30 days in, with
// the body moved onto h1 each time, since h1 walks through it.
fn test_scene() {
	mut s := new_sim(default_world(), .holonomic)
	assert s.pose == [-3.5, -2.5]
	mut times := []i64{}
	for t := i64(0); t <= 130_000; t += 7 {
		times << t
	}
	times << [i64(3_600_000), 86_400_000, 2_592_000_000]
	for t in times {
		want := today(s.t0_ms, s.t0_ms + t)
		assert s.scene(s.t0_ms + t).map(bits(it)) == want.map(bits(it)), '${t} ms'
		s.pose = want[2].pos.clone()
	}
}

fn close(a []f64, b []f64) bool {
	return a.len == b.len && lcl.dist(a, b) < 1e-3
}

struct PathCase {
	name     string
	h        Human
	clock_ms i64
	want     []f64
}

fn test_path() {
	ellipse := Human{
		behavior: .loop
		center:   [1.0, 1.0]
		radii:    [2.0, 1.0]
		rate:     0.5
		phase:    math.pi / 2
	}
	line := [[0.0, 0.0], [2.0, 0.0], [2.0, 2.0]]
	once := Human{
		behavior: .waypoints
		points:   line
		speed:    1.0
	}
	cycling := Human{
		...once
		cycle: true
	}
	cases := [
		PathCase{'a loop starts at its phase', ellipse, 0, [1.0, 2.0]},
		PathCase{'a loop turns at its rate', ellipse, 3142, [-1.0, 1.0]},
		PathCase{'a loop with a negative rate turns clockwise', Human{
			...ellipse
			rate: -0.5
		}, 3142, [3.0, 1.0]},
		PathCase{'waypoints start at the first', once, 0, [0.0, 0.0]},
		PathCase{'waypoints walk at their speed', once, 1000, [1.0, 0.0]},
		PathCase{'waypoints turn at a corner', once, 3000, [2.0, 1.0]},
		PathCase{'waypoints that do not cycle stop at the last', once, 60_000, [2.0, 2.0]},
		PathCase{'cycling waypoints walk back to the first', cycling, 5000, [1.293, 1.293]},
		PathCase{'cycling waypoints start over', cycling, 7828, [1.0, 0.0]},
		PathCase{'a waypoint twice in a row is passed', Human{
			...once
			points: [[0.0, 0.0], [0.0, 0.0], [1.0, 0.0]]
		}, 500, [0.5, 0.0]},
		PathCase{'a clock before the start stays at the first waypoint', once, -1000, [
			0.0, 0.0]},
		PathCase{'a standing human is at pos', Human{
			behavior: .stand
			pos:      [1.0, -1.0]
		}, 9000, [1.0, -1.0]},
		PathCase{'a human walking toward the body starts at pos', Human{
			behavior: .toward
			pos:      [-2.0, 3.0]
		}, 9000, [-2.0, 3.0]},
	]
	for c in cases {
		got := c.h.path(c.clock_ms)
		assert close(got, c.want), '${c.name}: ${got}'
	}
}

// walk steps a walker of h every dt_ms from from_ms to to_ms after the world began, with the body
// at pose, and returns the closest its rim came to the body's center.
fn walk(mut w Walker, h Human, from_ms i64, to_ms i64, dt_ms i64, pose []f64) f64 {
	mut closest := math.inf(1)
	for t := from_ms + dt_ms; t <= to_ms; t += dt_ms {
		w.step(h, t, dt_ms, pose)
		closest = math.min(closest, lcl.dist(w.at, pose) - h.r)
	}
	return closest
}

// A human walking through ignores the body: it is where its walk puts it.
fn test_a_human_who_walks_through_ignores_the_body() {
	h := Human{
		r:        0.3
		behavior: .waypoints
		reaction: .through
		points:   [[0.0, 0.0], [4.0, 0.0]]
		speed:    1.0
	}
	mut w := Walker{
		at: h.path(0)
	}
	assert walk(mut w, h, 0, 2000, 20, [2.0, 0.0]) < 0.0
	assert close(w.at, [2.0, 0.0])
}

// A stop human stands while its rim is within keep of the body, so its walk across the body's
// position ends short of it, and walks on from where it stood once the body has gone.
fn test_a_stop_human_waits_for_the_body_and_walks_on() {
	h := Human{
		r:        0.3
		behavior: .waypoints
		reaction: .stop
		points:   [[0.0, 0.0], [4.0, 0.0]]
		speed:    1.0
		keep:     1.0
	}
	mut w := Walker{
		at: h.path(0)
	}
	closest := walk(mut w, h, 0, 5000, 20, [2.5, 0.0])
	assert closest >= 1.0 && closest < 1.0 + 0.021, '${closest}'
	stood := w.at.clone()
	assert w.waited_ms > 3000
	walk(mut w, h, 5000, 6000, 20, [2.5, 5.0])
	assert close(w.at, [stood[0] + 1.0, 0.0]), '${w.at}'
}

// An aside human never comes within keep of the body, gets around a body standing on its way,
// even one dead ahead of it, counterclockwise, and catches up with its walk beyond.
fn test_an_aside_human_steps_around_the_body() {
	for pose in [[2.0, 0.0], [2.0, 0.1], [2.0, -0.1]] {
		h := Human{
			r:        0.3
			behavior: .waypoints
			reaction: .aside
			points:   [[0.0, 0.0], [4.0, 0.0]]
			speed:    0.5
			keep:     0.5
		}
		mut w := Walker{
			at: h.path(0)
		}
		closest := walk(mut w, h, 0, 12_000, 20, pose)
		assert closest >= 0.5 - 1e-9, '${pose}: ${closest}'
		assert close(w.at, [4.0, 0.0]), '${pose}: ${w.at}'
	}
	assert close(around([1.0, 0.0], [-1.0, 0.0]), [0.0, -1.0])
}

// An aside human whose place the body takes waits on the rim, keep from the body.
fn test_an_aside_human_waits_beside_a_body_on_its_place() {
	h := Human{
		r:        0.3
		behavior: .stand
		reaction: .aside
		pos:      [1.0, 1.0]
		keep:     0.6
	}
	mut w := Walker{
		at: h.path(0)
	}
	walk(mut w, h, 0, 3000, 20, [1.0, 1.2])
	assert math.abs(lcl.dist(w.at, [1.0, 1.2]) - 0.9) < 1e-9, '${w.at}'
	walk(mut w, h, 3000, 6000, 20, [4.0, 4.0])
	assert close(w.at, [1.0, 1.0]), '${w.at}'
}

// A stop human never steps inside keep, however late a sense comes, so it never walks into the
// body, where Sim would hold both for good while the human waits.
fn test_a_stop_human_never_steps_inside_keep() {
	pose := [0.0, 0.0]
	for dt in [i64(20), 30, 40, 71, 500] {
		for x := 1.0; x < 2.0; x += 0.01 {
			walkers := [
				Human{
					r:        0.3
					behavior: .toward
					reaction: .stop
					pos:      [x, 0.0]
					speed:    walk_max
					keep:     keep_min
				},
				Human{
					r:        0.3
					behavior: .waypoints
					reaction: .stop
					points:   [[x, 0.0], [-x, 0.0]]
					speed:    walk_max
					keep:     keep_min
				},
			]
			for h in walkers {
				mut w := Walker{
					at: h.path(0)
				}
				closest := walk(mut w, h, 0, 2000, dt, pose)
				assert closest >= keep_min, '${h.behavior} from ${x} every ${dt} ms: ${closest}'
			}
		}
	}
}

// A human walking toward the body walks at its speed, and with stop it stands keep from the body.
fn test_a_human_walks_toward_the_body() {
	h := Human{
		r:        0.3
		behavior: .toward
		reaction: .stop
		pos:      [0.0, 0.0]
		speed:    0.5
		keep:     1.5
	}
	mut w := Walker{
		at: h.path(0)
	}
	walk(mut w, h, 0, 2000, 20, [10.0, 0.0])
	assert close(w.at, [1.0, 0.0]), '${w.at}'
	closest := walk(mut w, h, 2000, 30_000, 20, [5.0, 0.0])
	assert closest >= 1.5 && closest < 1.5 + 0.011, '${closest}'
}

// Sim walks its humans by the time between senses, however uneven: one walking toward the body
// covers its speed times each gap, and an aside one the body pushed off its place walks back at
// walk_max times each gap at most. A wall clock stepped back moves neither.
fn test_sim_walks_humans_by_the_time_between_senses() {
	mut s := new_sim(World{
		start:   [-4.0, -4.0]
		beacons: [Spot{
			id:  'b1'
			pos: [4.0, 4.0]
			r:   0.3
		}]
		humans:  [
			Human{
				id:       'h1'
				r:        0.3
				behavior: .toward
				reaction: .stop
				pos:      [4.0, -4.0]
				speed:    0.5
				keep:     0.5
			},
			Human{
				id:       'h2'
				r:        0.3
				behavior: .stand
				reaction: .aside
				pos:      [0.0, 0.0]
				keep:     0.6
			},
		]
	}, .holonomic)
	mut now := s.t0_ms
	for dt in [i64(13), 40, 71, 20, 7, 71] {
		before := s.walkers[0].at.clone()
		now += dt
		s.scene(now)
		assert math.abs(lcl.dist(before, s.walkers[0].at) - 0.5 * f64(dt) / 1000.0) < 1e-9, '${dt} ms'
		assert s.walkers[1].at == [0.0, 0.0]
	}
	s.pose = [0.0, 0.2]
	now += 20
	s.scene(now)
	assert lcl.dist(s.walkers[1].at, s.pose) - 0.3 >= 0.6 - 1e-9
	s.pose = [-4.0, -4.0]
	for dt in [i64(13), 40, 71, 20, 7, 71] {
		before := s.walkers[1].at.clone()
		now += dt
		s.scene(now)
		assert math.abs(lcl.dist(before, s.walkers[1].at) - walk_max * f64(dt) / 1000.0) < 1e-9, '${dt} ms'
	}
	before := s.walkers.map(it.at.clone())
	s.scene(now - 100)
	assert s.walkers.map(it.at) == before
}

// Sim holds the body still while it touches a human, as it does for any solid, whoever moves.
fn test_sim_counts_contact_with_a_human() {
	mut s := new_sim(World{
		start:   [0.0, 0.0]
		beacons: [Spot{
			id:  'b1'
			pos: [4.0, 4.0]
			r:   0.3
		}]
		humans:  [
			Human{
				id:       'h1'
				r:        0.3
				behavior: .stand
				reaction: .through
				pos:      [0.5, 0.0]
			},
		]
	}, .holonomic)
	p := s.sense()
	assert p.contact
	assert p.scene.map(it.id) == ['b1', 'h1']
}

// sensed is s's percept dt_ms after its last one, as if that much time had passed.
fn sensed(mut s Sim, dt_ms i64) lcl.Percept {
	s.last_ms = lcl.now_ms() - dt_ms
	return s.sense()
}

// Far from the default world's pillar and human, so nothing holds the body still.
const clear = [-4.0, -4.0]

// apart is the default world with the body starting at clear.
fn apart() World {
	return World{
		...default_world()
		start: clear
	}
}

// A holonomic Sim moves along its command in any direction, never turns, and reports no heading.
fn test_a_holonomic_sim_slides_along_its_command() {
	mut s := new_sim(apart(), .holonomic)
	s.actuate([0.0, 0.5])!
	p := sensed(mut s, 100)
	assert p.vel == [0.0, 0.5]
	assert p.pose[0] == clear[0] && p.pose[1] > clear[1]
	assert p.heading == 0.0
}

// A differential Sim moves only along the heading it had when commanded, then turns toward the
// Course's heading at turn_rate, so it never slides sideways.
fn test_a_differential_sim_drives_along_its_heading_and_turns() {
	mut s := new_sim(apart(), .differential)
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
	mut s := new_sim(apart(), .differential)
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
		mut s := new_sim(apart(), drive)
		s.actuate([0.3, 1.0])!
		p := sensed(mut s, -100)
		assert p.pose == clear, '${drive}'
		assert p.heading == 0.0, '${drive}'
	}
}

// A walker reports the step of its last walk over that time as its velocity, whatever its
// behavior, none while it stands, and keeps it over a step of no time; Sim.scene hands it on.
fn test_a_walker_reports_the_velocity_of_its_last_step() {
	h1 := default_world().humans[0]
	mut w := Walker{
		at: h1.path(0)
	}
	for t := i64(20); t <= 21_000; t += 20 {
		w.step(h1, t, 20, [-3.5, -2.5])
		a := 0.3 * f64(t - 10) / 1000.0
		assert close(w.vel, [-0.54 * math.sin(a), 0.36 * math.cos(a)]), '${t} ms: ${w.vel}'
	}

	along := Human{
		r:        0.3
		behavior: .waypoints
		reaction: .stop
		points:   [[0.0, 0.0], [4.0, 0.0]]
		speed:    0.5
		keep:     1.0
	}
	mut x := Walker{
		at: along.path(0)
	}
	walk(mut x, along, 0, 1000, 20, [0.0, 4.0])
	assert close(x.vel, [0.5, 0.0]), '${x.vel}'
	x.step(along, 1000, 0, [0.0, 4.0])
	assert close(x.vel, [0.5, 0.0]), 'a step of no time: ${x.vel}'
	walk(mut x, along, 1000, 3000, 20, [2.0, 0.0])
	assert x.waited_ms > 0 && x.vel == [], 'a stop human waiting: ${x.vel}'

	stand := Human{
		r:        0.3
		behavior: .stand
		reaction: .through
		pos:      [1.0, 1.0]
	}
	mut y := Walker{
		at: stand.path(0)
	}
	walk(mut y, stand, 0, 100, 20, [0.0, 0.0])
	assert y.vel == []

	mut s := new_sim(default_world(), .holonomic)
	scene := s.scene(s.t0_ms + 20)
	assert scene.map(it.vel.len) == [0, 0, 2]
	assert scene[2].vel == s.walkers[0].vel
}
