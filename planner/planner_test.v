module planner

import math
import lcl

// The armor's keeps and fence from armor.Limits, which main.v hands the planner.
const solid_keep = 0.35
const human_stop = 0.7
const top = 0.4 // m/s, the armor's v_unmanned with no human within human_slow
const tick = 0.02 // s, one tick of main.v's field loop

fn fresh() Planner {
	return Planner{
		solid_keep: solid_keep
		human_stop: human_stop
		bounds:     [-5.0, -5.0, 5.0, 5.0]
	}
}

fn solid(x f64, y f64, r f64) lcl.Entity {
	return lcl.Entity{
		id:   'o'
		kind: 'obstacle'
		pos:  [x, y]
		r:    r
	}
}

fn person(x f64, y f64, vel []f64) lcl.Entity {
	return lcl.Entity{
		id:   'h'
		kind: 'human'
		pos:  [x, y]
		r:    0.3
		vel:  vel
	}
}

fn heading_to(target []f64) lcl.Intent {
	return lcl.Intent{
		verb:   'goto'
		target: target
	}
}

// Flight is what fly saw: where the body went, tick by tick, with the scene of each tick, and how
// often the command turned more than 90 degrees from the one before, both above 0.05 m/s.
struct Flight {
mut:
	poses  [][]f64
	scenes [][]lcl.Entity
	flips  int
}

// fly moves the body from pose toward target at the planner's command for up to seconds, each
// walking human straight on at its velocity, with no armor in between, and stops once the body
// is within 0.05 m of the target.
fn fly(pose []f64, target []f64, scene []lcl.Entity, seconds f64) Flight {
	return fly_by(pose, target, scene, seconds, 0.0)
}

// fly_by is fly with walkers that stop for the body as a world's stop reaction does, when stop is
// above 0: a walker stands, and shows no velocity, while the body's center is within stop of its
// rim or would be after its next step, and walks on once it is clear.
fn fly_by(pose []f64, target []f64, scene []lcl.Entity, seconds f64, stop f64) Flight {
	mut pl := fresh()
	mut f := Flight{}
	mut at := pose.clone()
	mut now := scene.clone()
	mut last := [0.0, 0.0]
	for _ in 0 .. int(seconds / tick) {
		f.poses << at.clone()
		f.scenes << now
		if lcl.dist(at, target) < 0.05 {
			break
		}
		u := pl.next(lcl.Percept{ pose: at, scene: now }, heading_to(target), top)
		assert lcl.norm(u) <= top + 1e-12
		if lcl.norm(u) > 0.05 && lcl.norm(last) > 0.05 && lcl.dot(u, last) < 0.0 {
			f.flips++
		}
		last = u.clone()
		at = [at[0] + u[0] * tick, at[1] + u[1] * tick]
		mut then := []lcl.Entity{}
		for i, e in scene {
			step := if e.vel.len == 2 {
				[now[i].pos[0] + e.vel[0] * tick, now[i].pos[1] + e.vel[1] * tick]
			} else {
				now[i].pos
			}
			stands := stop > 0.0 && (lcl.dist(at, now[i].pos) - e.r < stop
				|| lcl.dist(at, step) - e.r < stop)
			then << lcl.Entity{
				...e
				pos: if stands { now[i].pos } else { step }
				vel: if stands { []f64{} } else { e.vel }
			}
		}
		now = then.clone()
	}
	return f
}

// arrived reports whether the flight ended within 0.05 m of target.
fn (f Flight) arrived(target []f64) bool {
	return lcl.dist(f.poses.last(), target) < 0.05
}

// nearest is the least distance from the body's center to the rim of an entity of kind over the
// flight.
fn (f Flight) nearest(kind string) f64 {
	mut least := math.inf(1)
	for i, at in f.poses {
		for e in f.scenes[i] {
			if e.kind == kind {
				least = math.min(least, lcl.dist(at, e.pos) - e.r)
			}
		}
	}
	return least
}

// crossing is the body's y where it first reaches x, or NaN if it never does.
fn (f Flight) crossing(x f64) f64 {
	for i in 1 .. f.poses.len {
		a, b := f.poses[i - 1], f.poses[i]
		if (a[0] - x) * (b[0] - x) <= 0.0 && a[0] != b[0] {
			return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
		}
	}
	return math.nan()
}

struct WayCase {
	name   string
	pose   []f64
	target []f64
	scene  []lcl.Entity
	at_x   f64 // where the side is read
	side   f64 // the sign of the body's y less its start's where it crosses at_x, 0 for within 0.2 m
}

// The way around solids and standing humans: the body reaches the target, never comes inside a
// solid's keep or a standing human's berth, never leaves the fence, and passes on the side the
// shortest way takes, never parked behind a pillar or between two.
fn test_way() {
	cases := [
		WayCase{'one pillar on the line, passed on the shorter side', [-3.0, 0.0], [3.0, 0.3], [
			solid(0.0, 0.0, 0.8)], 0.0, 1.0},
		WayCase{'two pillars with room between, passed between', [-3.0, 0.0], [3.0, 0.0], [
			solid(0.0, 1.25, 0.5), solid(0.0, -1.25, 0.5)], 0.0, 0.0},
		WayCase{'two pillars too close to pass between, passed around both', [-3.0, 0.0], [
			3.0, 0.1], [solid(0.0, 0.75, 0.5), solid(0.0, -0.75, 0.5)], 0.0, 1.0},
		WayCase{'a target behind a pillar', [-3.0, 0.1], [1.6, 0.0], [
			solid(0.0, 0.0, 0.8)], 0.0, 1.0},
		WayCase{'a target inside the margin around a pillar', [-3.0, -0.1], [1.25, 0.0], [
			solid(0.0, 0.0, 0.8)], 0.0, -1.0},
		WayCase{'a pose inside the margin around a pillar', [-1.25, 0.0], [3.0, 0.3], [
			solid(0.0, 0.0, 0.8)], 0.0, 1.0},
		WayCase{'overlapping pillars across the way', [-3.0, 0.0], [3.0, -0.2], [
			solid(0.0, 0.8, 0.6), solid(0.0, 0.0, 0.6), solid(0.0, -0.8, 0.6)], 0.0, -1.0},
		WayCase{'a pillar the fence closes off to the north', [-3.0, 4.3], [3.0, 4.3], [
			solid(0.0, 4.0, 0.5)], 0.0, -1.0},
		WayCase{'a standing human on the line', [-3.0, 0.0], [3.0, 0.3], [
			person(0.0, 0.0, [])], 0.0, 1.0},
	]
	for c in cases {
		f := fly(c.pose, c.target, c.scene, 60.0)
		assert f.arrived(c.target), '${c.name}: ended at ${f.poses.last()}'
		assert f.nearest('obstacle') >= solid_keep, c.name
		assert f.nearest('human') >= human_stop + berth - 1e-6, c.name
		assert f.poses.all(math.abs(it[0]) <= 5.0 && math.abs(it[1]) <= 5.0), c.name
		y := f.crossing(c.at_x) - c.pose[1]
		if c.side == 0.0 {
			assert math.abs(y) < 0.2, '${c.name}: crossed at ${y}'
		} else {
			assert y * c.side > 0.0, '${c.name}: crossed at ${y}'
		}
	}
}

// A gap narrower than the margins leave, here 0.75 m between the rims of a wall of pillars across
// the fence, is passed at the armor's solid_keep: no way leads around the wall, so the body heads
// straight for the target and through the gap, rather than standing before it.
fn test_a_gap_the_margins_close_is_passed_at_solid_keep() {
	mut pillars := []lcl.Entity{}
	for side in [-1.0, 1.0] {
		for k in 0 .. 4 {
			pillars << solid(side * (0.375 + 0.6 + 1.1 * f64(k)), 0.0, 0.6)
		}
	}
	f := fly([0.0, -3.0], [0.0, 3.0], pillars, 60.0)
	assert f.arrived([0.0, 3.0]), 'ended at ${f.poses.last()}'
	assert f.nearest('obstacle') >= solid_keep
}

// A walker who stops for the body at the planner's berth and steps on a tick at a time as the body
// leaves it is passed without the command turning back and forth: it stays in the way as standing
// until it has walked settle ticks, where the way used to go around it and through it on
// alternate ticks, 597 turns in this flight.
fn test_a_walker_who_stops_for_the_body_does_not_flip_its_way() {
	f := fly_by([0.0, 0.0], [3.5, 2.5], [person(1.8, 0.0, [0.0, 0.5]),
		solid(2.0, -2.5, 0.6)], 120.0, human_stop + berth)
	assert f.arrived([3.5, 2.5]), 'ended at ${f.poses.last()}'
	assert f.flips <= 10, '${f.flips} turns'
	assert f.nearest('human') >= human_stop
}

// The way leaves out the corners within margin of the fence, so where the shorter side of a pillar
// lies against the fence, the way takes the other.
fn test_the_way_stays_inside_the_fence() {
	_, dy, _, _ := fresh().way(-3.0, 4.3, 3.0, 4.3, [
		Circle{0.0, 4.0, 0.5 + solid_keep + margin},
	])
	assert dy < 0.0
}

// A step aside from a walker never takes the body inside a solid's keep, though the pillar lies on
// the side away from the walker.
fn test_a_step_aside_keeps_off_a_solid() {
	f := fly([0.0, 0.0], [4.5, 0.0], [solid(1.2, 0.9, 0.3), person(3.0, -0.3, [-0.5, 0.0])], 30.0)
	assert f.arrived([4.5, 0.0])
	assert f.nearest('obstacle') >= solid_keep
	assert f.nearest('human') >= human_stop
}

// With a walker already near, the command's closest approach to it over the horizon stays outside
// human_stop at the top speed a seat allows, though a closer pass would gain more.
fn test_a_near_walker_stays_outside_human_stop() {
	for h in [person(1.04, -0.31, [-0.4, 0.49]), person(1.06, 0.16, [-0.16, -0.46]),
		person(0.3, -1.01, [-0.58, 0.5])] {
		mut pl := fresh()
		u := pl.next(lcl.Percept{ pose: [0.0, 0.0], scene: [h] }, heading_to([4.5, 0.0]), 1.0)
		cx, cy := closest(-h.pos[0], -h.pos[1], u[0] - h.vel[0], u[1] - h.vel[1], horizon)
		assert hyp(cx, cy) - h.r >= human_stop, '${h.pos} ${h.vel}: ${u}'
	}
}

// A walker crossing ahead of the body is passed behind and with room: by the time the body reaches
// the walker's course, the walker has crossed the body's way, and its rim never comes within
// human_stop plus 0.1 m, which the extra berth on a walker's front side keeps.
fn test_a_walker_crossing_ahead_is_passed_behind() {
	for start in [[1.5, -1.2], [2.0, -3.0]] {
		f := fly([0.0, 0.0], [4.5, 0.0], [person(start[0], start[1], [0.0, 0.5])], 30.0)
		assert f.arrived([4.5, 0.0]), start.str()
		assert f.nearest('human') >= human_stop + 0.1, start.str()
		for i, at in f.poses {
			if at[0] >= start[0] {
				walker := f.scenes[i][0].pos
				assert walker[1] > at[1] + human_stop, 'the walker at ${walker}, the body at ${at}'
				break
			}
		}
	}
}

// A walker heading straight at the body makes it step off the walker's course while it still
// gains on the goal, rather than stand or back away along that course, and the walker's rim never
// comes inside human_stop.
fn test_a_walker_heading_at_the_body_is_stepped_around() {
	f := fly([0.0, 0.0], [4.5, 0.0], [person(3.5, 0.0, [-0.5, 0.0])], 30.0)
	assert f.arrived([4.5, 0.0])
	assert f.nearest('human') >= human_stop
	for i, at in f.poses {
		if f.scenes[i][0].pos[0] <= at[0] {
			assert at[0] > 0.0, 'the body lost ground: ${at}'
			assert math.abs(at[1]) >= human_stop + 0.3, 'the body stayed in the course: ${at}'
			break
		}
	}
}

// Inside a human's berth a step toward that human pays wall per m/s, so with one human near, whether
// it stands between the body and the goal or walks past, the body steps toward them in none of
// these cases; it is a cost, not a rule, and with two humans near it may step toward one to clear
// the other.
fn test_never_toward_a_human_inside_the_berth() {
	for h in [person(0.9, 0.2, []), person(0.9, 0.2, [0.0, 0.4]),
		person(0.9, -0.4, [-0.3, 0.3])] {
		mut pl := fresh()
		u := pl.next(lcl.Percept{ pose: [0.0, 0.0], scene: [h] }, heading_to([4.5, 0.0]), top)
		assert lcl.dot(u, h.pos) <= 0.0, '${h.pos} ${h.vel}: ${u}'
	}
}

struct ZeroCase {
	name string
	pose []f64
	goal lcl.Intent
	top  f64
}

// No goto, the target reached, a pose, target or top speed it cannot use: zero, as long as the
// pose.
fn test_next() {
	nan := math.nan()
	cases := [
		ZeroCase{'hold', [0.0, 0.0], lcl.Intent{
			verb: 'hold'
		}, top},
		ZeroCase{'release', [3.0, 2.0], lcl.Intent{
			verb:   'release'
			target: [3.0, 2.0]
		}, top},
		ZeroCase{'an unknown verb with a target', [0.0, 0.0], lcl.Intent{
			verb:   'self_destruct'
			target: [3.0, 2.0]
		}, top},
		ZeroCase{'the target reached', [3.0, 2.0], heading_to([3.0, 2.0]), top},
		ZeroCase{'a target of one number', [0.0, 0.0], heading_to([3.0]), top},
		ZeroCase{'a target that is NaN', [0.0, 0.0], heading_to([nan, 2.0]), top},
		ZeroCase{'a pose that is infinite', [math.inf(1), 0.0], heading_to([3.0, 2.0]), top},
		ZeroCase{'no speed allowed', [0.0, 0.0], heading_to([3.0, 2.0]), 0.0},
		ZeroCase{'a top speed that is NaN', [0.0, 0.0], heading_to([3.0, 2.0]), nan},
		ZeroCase{'a pose of three numbers', [0.0, 0.0, 0.0], heading_to([3.0, 2.0]), top},
	]
	for c in cases {
		mut pl := fresh()
		u := pl.next(lcl.Percept{ pose: c.pose, scene: [solid(1.0, 1.0, 0.5)] }, c.goal, c.top)
		assert u == []f64{len: c.pose.len}, c.name
	}
}

// With nothing around the body heads straight for the target at the speed allowed, and slows onto
// it at 1.5 times the distance, as main.v's reflex does.
fn test_an_empty_scene_heads_straight_and_slows_onto_the_target() {
	mut pl := fresh()
	far := pl.next(lcl.Percept{ pose: [0.0, 0.0] }, heading_to([4.5, 0.0]), top)
	assert lcl.dist(far, [top, 0.0]) < 1e-12, far.str()
	near := pl.next(lcl.Percept{ pose: [4.9, 0.0] }, heading_to([5.0, 0.0]), top)
	assert lcl.dist(near, [0.15, 0.0]) < 1e-9, near.str()
}

// A walking human's velocity that is not two finite numbers, or slower than walking, counts as
// standing, and the command stays finite and within the top speed.
fn test_a_velocity_it_cannot_measure_counts_as_standing() {
	standing := fresh().choose(lcl.Percept{
		pose:  [0.0, 0.0]
		scene: [person(2.0, 0.5, [])]
	}, heading_to([4.5, 0.0]), top)
	for vel in [[math.nan(), 0.0], [0.4], [0.1, 0.2, 0.3], [math.inf(-1), 0.0],
		[1e200, 1e200], [0.0, 0.0], [1e-300, 0.0], [0.04, 0.0]] {
		u := fresh().choose(lcl.Percept{
			pose:  [0.0, 0.0]
			scene: [person(2.0, 0.5, vel)]
		}, heading_to([4.5, 0.0]), top)
		assert u == standing, '${vel}: ${u}'
		assert lcl.norm(u) <= top
	}
}

// The same percept and the same last command give the same command, and the last command keeps
// the side the body steps to: a walker straight ahead on the way is passed on the side chosen
// before.
fn test_the_same_percept_and_state_give_the_same_command() {
	p := lcl.Percept{
		pose:  [0.0, 0.0]
		scene: [person(2.6, 0.0, [-0.5, 0.0]), solid(-2.0, 2.0, 0.5)]
	}
	mut a := fresh()
	mut b := fresh()
	assert a.next(p, heading_to([4.5, 0.0]), top) == b.next(p, heading_to([4.5, 0.0]), top)
	assert a.next(p, heading_to([4.5, 0.0]), top) == b.next(p, heading_to([4.5, 0.0]), top)
	for side in [1.0, -1.0] {
		mut pl := Planner{
			...fresh()
			last: [0.2, 0.3 * side]
		}
		u := pl.next(lcl.Percept{
			pose:  [0.0, 0.0]
			scene: [person(2.6, 0.0, [-0.5, 0.0])]
		}, heading_to([4.5, 0.0]), top)
		assert u[1] * side > 0.0, '${side}: ${u}'
	}
}
