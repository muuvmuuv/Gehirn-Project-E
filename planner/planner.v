// The local planner: System 1 with a map. Where main.v's reflex only pulls the body toward the
// approved goal and pushes it off whatever is near, the planner finds the shortest way to the goal
// around the solids and, each tick, picks the velocity that gains most on that way while it keeps
// clear of where each walking human and moving obstacle is heading. main.v's field loop flies it
// under PLANNER=local in place of the reflex, and the armor restrains its command like any other.
// Deterministic code with no model in it, planned for the holonomic body.
module planner

import math
import lcl

// margin is how far, in meters, the way keeps outside the armor's solid_keep and inside its fence,
// so the body passes a pillar without the armor stripping its command, the MuJoCo base's stopping
// distance of up to 11.7 cm at 1 m/s included.
const margin = 0.15

// berth is how far, in meters, the planner keeps a human's rim outside the armor's human_stop.
const berth = 0.3

// walking is the least speed, in m/s, at which the planner follows a human as walking: half of
// body/world.v walk_min, the slowest walk a world allows, so a creep stays standing.
const walking = 0.05

// settle is how many ticks a human who stood must walk before the way stops going around it, 0.5 s
// at the field loop's 50 Hz: one that stops for the body and steps on a tick at a time as the body
// leaves its keep stays in the way, rather than turning the way back and forth each tick.
const settle = 25

// front is how much more berth, in meters, a walker gets where the body would pass in front of it
// rather than behind it, scaled by how far ahead of the walker the body would be.
const front = 0.3

// horizon is how far ahead, in seconds, the planner follows each walking human in a straight line
// and each candidate velocity: the 2 s of magi/magi.v course_horizon, past which a straight line
// says nothing honest about a walker who turns (ADR-0009).
const horizon = 2.0

// lead is how far ahead, in seconds, the planner aims at the target on the way's last leg, so it
// closes on the target at 1.5 times the distance, as main.v's reflex does, and stops on it.
const lead = 1.0 / 1.5

// sides is the number of corners of the polygon the way takes around each circle, drawn so its
// edges touch the circle: 12 add at most 3.5% to the circle's radius.
const sides = 12

// headings is the number of directions the planner tries each tick, evenly spaced from the way's.
const headings = 32

// smooth is what a candidate pays per m/s it differs from the command chosen a tick before, so a
// choice between two nearly equal ways, past a walker or around a pillar, does not flip each tick.
const smooth = 0.3

// crowd, press and wall weigh a candidate's costs against its gain on the way: crowd per square
// meter a human's rim comes inside its berth, press per meter the body comes inside solid_keep of
// a solid's rim and wall once a human's rim comes inside human_stop, each per m/s of the speed the
// armor allows, and wall per m/s the body steps toward a human inside the berth.
const crowd = 10.0
const press = 20.0
const wall = 10.0

// Planner is the field tier's local planner, which main.v's field loop asks for the core's
// command each tick under PLANNER=local. main.v builds it from armor.Limits, the keeps and the
// fence it plans around, and only the field loop's thread holds it.
pub struct Planner {
pub:
	solid_keep f64   // m from the body's center to a solid's rim, armor.Limits solid_keep
	human_stop f64   // m from the body's center to a human's rim, armor.Limits human_stop
	bounds     []f64 // m, xmin, ymin, xmax, ymax, armor.Limits bounds
mut:
	last  []f64 = [0.0, 0.0] // m/s, the command next returned last
	stood map[string]int // by id, ticks each one walked since it last stood, under settle
}

// Circle is a solid as the planner sees it, a center and a radius in meters.
struct Circle {
	x f64
	y f64
	r f64
}

// Mover is a human or an obstacle as the planner sees it, with the velocity it walks at, zero for
// one that stands or whose velocity cannot be measured.
struct Mover {
	x     f64
	y     f64
	r     f64
	wx    f64
	wy    f64
	walks bool
}

// Ahead is what one tick's candidates are scored against: the pose, the target, the way's first
// leg and length, the speed the armor allows, and the humans and solids around.
struct Ahead {
	x         f64
	y         f64
	tx        f64
	ty        f64
	dx        f64 // the first leg's unit direction
	dy        f64
	length    f64 // m, the whole way
	last_leg  bool
	top       f64 // m/s
	humans    []Mover
	obstacles []Mover
}

// next is the core's command for the body at p toward goal, a planar velocity in m/s, for
// main.v's field loop in place of the reflex: zero unless goal is a goto, and at most top, the
// fastest the armor lets the body move at p (armor.Armor.top_speed). It heads along the shortest
// way to the target around every solid and standing human, each widened by the armor's keep and
// the planner's own margin, and of a fixed set of headings and speeds takes the one that gains
// most on that way against how close it would bring the body over the next 2 s to each human and
// each solid, walkers and moving obstacles followed in a straight line. Inside a human's berth a
// step toward
// that human costs it, though with several humans near it may step toward one to clear another.
// It closes on the target as the reflex does, at 1.5 times the distance, and gives zero on it. A
// percept or goal it cannot measure gives zero; a human or an obstacle whose velocity it cannot
// measure counts as standing.
// ponytail: it wades through ground at the speed it plans off ground and leaves the slowing to the
// armor; cost a patch at 1 / factor per meter once a world shows a detour beating the wade.
pub fn (mut pl Planner) next(p lcl.Percept, goal lcl.Intent, top f64) []f64 {
	if p.pose.len != 2 {
		return []f64{len: p.pose.len}
	}
	pl.track(p)
	u := pl.choose(p, goal, top)
	pl.last = u.clone()
	return u
}

// track counts, by id, the ticks each human and obstacle of p has walked since it last stood, as
// long as that stays under settle, for choose to keep it in the way. An obstacle that never walks
// stays at 0.
fn (mut pl Planner) track(p lcl.Percept) {
	mut stood := map[string]int{}
	for e in p.scene {
		if e.kind == 'beacon' {
			continue
		}
		if !walks(e.vel) {
			stood[e.id] = 0
		} else if e.id in pl.stood {
			n := (pl.stood[e.id] or { 0 }) + 1
			if n < settle {
				stood[e.id] = n
			}
		}
	}
	pl.stood = stood.move()
}

// choose is next's command without the bookkeeping: zero on anything it cannot measure.
fn (pl Planner) choose(p lcl.Percept, goal lcl.Intent, top f64) []f64 {
	if goal.verb != 'goto' || goal.target.len != 2 || !finite(goal.target) || !finite(p.pose)
		|| !(top > 0.0) || !math.is_finite(top) || pl.bounds.len != 4 || pl.last.len != 2 {
		return [0.0, 0.0]
	}
	x, y := p.pose[0], p.pose[1]
	tx, ty := goal.target[0], goal.target[1]
	if x == tx && y == ty {
		return [0.0, 0.0]
	}
	mut solids := []Circle{}
	mut obstacles := []Mover{}
	mut humans := []Mover{}
	for e in p.scene {
		if e.kind == 'beacon' || e.pos.len != 2 || !finite(e.pos) || !(e.r >= 0.0)
			|| !math.is_finite(e.r) {
			continue
		}
		if e.kind == 'human' {
			m := mover(e)
			humans << m
			if !m.walks || e.id in pl.stood {
				solids << widened(m.x, m.y, e.r + pl.human_stop + berth, x, y, tx, ty)
			}
			continue
		}
		o := mover(e)
		obstacles << o
		if !o.walks || e.id in pl.stood {
			solids << widened(o.x, o.y, e.r + pl.solid_keep + margin, x, y, tx, ty)
		}
	}
	dx, dy, length, last_leg := pl.way(x, y, tx, ty, solids.filter(it.r > 0.0))
	a := Ahead{
		x:         x
		y:         y
		tx:        tx
		ty:        ty
		dx:        dx
		dy:        dy
		length:    length
		last_leg:  last_leg
		top:       top
		humans:    humans
		obstacles: obstacles
	}

	// Rest comes first and a candidate must beat the best so far, so equal scores keep the earlier
	// one and a score that is not a number never wins.
	mut best := pl.score(a, 0.0, 0.0)
	mut bx, mut by := 0.0, 0.0
	approach := if last_leg { math.min(top, length / lead) } else { top }
	s := pl.score(a, dx * approach, dy * approach)
	if s > best {
		best, bx, by = s, dx * approach, dy * approach
	}
	along := math.atan2(dy, dx)
	for k in 0 .. headings {
		h := along + 2.0 * math.pi * f64(k) / headings
		for f in [1.0 / 3.0, 2.0 / 3.0, 1.0] {
			vx, vy := top * f * math.cos(h), top * f * math.sin(h)
			c := pl.score(a, vx, vy)
			if c > best {
				best, bx, by = c, vx, vy
			}
		}
	}
	if !math.is_finite(bx) || !math.is_finite(by) {
		return [0.0, 0.0]
	}
	return [bx, by]
}

// mover is human or obstacle e as the planner follows it: walking at its velocity when walks
// reads it so, and standing otherwise.
fn mover(e lcl.Entity) Mover {
	w := walks(e.vel)
	return Mover{
		x:     e.pos[0]
		y:     e.pos[1]
		r:     e.r
		wx:    if w { e.vel[0] } else { 0.0 }
		wy:    if w { e.vel[1] } else { 0.0 }
		walks: w
	}
}

// walks reports whether a human or an obstacle with velocity vel walks: vel is two finite numbers
// whose squared length is finite too, at walking or faster.
fn walks(vel []f64) bool {
	return vel.len == 2 && math.is_finite(vel[0] * vel[0] + vel[1] * vel[1])
		&& hyp(vel[0], vel[1]) >= walking
}

// widened is the circle of radius r around cx, cy that the way keeps out of, shrunk just enough to
// leave the pose x, y and the target tx, ty outside the polygon way draws around it: a body that
// already stands inside it moves on along the polygon's edges, and a target inside it stays
// reachable. Its radius is 0 or less when the pose or the target lies on its center.
fn widened(cx f64, cy f64, r f64, x f64, y f64, tx f64, ty f64) Circle {
	inside := 1e-6
	near := math.min(hyp(x - cx, y - cy), hyp(tx - cx, ty - cy))
	return Circle{cx, cy, math.min(r, near * math.cos(math.pi / sides) - inside)}
}

// way is the unit direction of the first leg of the shortest way from x, y to tx, ty that enters no
// circle of solids, the whole way's length, and whether that first leg ends at the target. The way
// runs over the corners of a polygon drawn around each circle, those within margin of the fence
// left out, and A* finds it; no clear segment reaches a corner inside another circle.
// ponytail: where the margins and berths close every way, as a gap under 2 * (solid_keep + margin),
// 1 m, between solids or between a solid and the fence does, or standing humans' 1 m circles do on
// ep13-iruel (PLAN, Known issue 38), it heads straight for the target, and score's press at
// solid_keep and the armor slide the body along what is in the way. Once a world needs a way
// around there, try again without the margins and berths before heading straight.
fn (pl Planner) way(x f64, y f64, tx f64, ty f64, solids []Circle) (f64, f64, f64, bool) {
	straight := hyp(tx - x, ty - y)
	if clear(x, y, tx, ty, solids) {
		return (tx - x) / straight, (ty - y) / straight, straight, true
	}
	mut xs := [x, tx]
	mut ys := [y, ty]
	b := pl.bounds
	for c in solids {
		out := c.r / math.cos(math.pi / sides)
		for i in 0 .. sides {
			a := 2.0 * math.pi * f64(i) / sides
			vx, vy := c.x + out * math.cos(a), c.y + out * math.sin(a)
			if vx < b[0] + margin || vx > b[2] - margin || vy < b[1] + margin || vy > b[3] - margin
				|| hyp(vx - x, vy - y) < 1e-6 {
				continue
			}
			xs << vx
			ys << vy
		}
	}

	// A* over the corners: cost is the length from the pose, and the straight distance to the
	// target never overestimates what is left, so the target's cost is the shortest way's once
	// it is taken.
	n := xs.len
	mut cost := []f64{len: n, init: math.inf(1)}
	mut from := []int{len: n, init: -1}
	mut done := []bool{len: n}
	cost[0] = 0.0
	for {
		mut k := -1
		mut least := math.inf(1)
		for i in 0 .. n {
			if !done[i] {
				f := cost[i] + hyp(tx - xs[i], ty - ys[i])
				if f < least {
					least, k = f, i
				}
			}
		}
		if k < 0 || k == 1 {
			break
		}
		done[k] = true
		for j in 1 .. n {
			c := cost[k] + hyp(xs[j] - xs[k], ys[j] - ys[k])
			if !done[j] && c < cost[j] && clear(xs[k], ys[k], xs[j], ys[j], solids) {
				cost[j], from[j] = c, k
			}
		}
	}
	if from[1] < 0 {
		return (tx - x) / straight, (ty - y) / straight, straight, true
	}
	mut j := 1
	for from[j] != 0 {
		j = from[j]
	}
	leg := hyp(xs[j] - x, ys[j] - y)
	return (xs[j] - x) / leg, (ys[j] - y) / leg, cost[1], j == 1
}

// clear reports whether the segment from ax, ay to bx, by enters no circle of solids. Touching one,
// as each edge of a polygon drawn around it does, is no entering.
fn clear(ax f64, ay f64, bx f64, by f64, solids []Circle) bool {
	ex, ey := bx - ax, by - ay
	ee := ex * ex + ey * ey
	for c in solids {
		t := if ee > 0.0 {
			math.max(0.0, math.min(1.0, ((c.x - ax) * ex + (c.y - ay) * ey) / ee))
		} else {
			0.0
		}
		if hyp(ax + ex * t - c.x, ay + ey * t - c.y) < c.r - 1e-9 {
			return false
		}
	}
	return true
}

// score is what the velocity vx, vy is worth from a: its gain on the way in m/s, less what it pays
// for differing from the last command, for coming close to a human or a solid within horizon, and
// for stepping toward a human inside the berth; the armor keeps the fence. The gain is its speed
// along the first leg, or on the last leg how much nearer the target it brings the body within
// lead, so it slows onto the target instead of passing it.
fn (pl Planner) score(a Ahead, vx f64, vy f64) f64 {
	gain := if a.last_leg {
		(a.length - hyp(a.tx - a.x - vx * lead, a.ty - a.y - vy * lead)) / lead
	} else {
		vx * a.dx + vy * a.dy
	}
	mut cost := smooth * hyp(vx - pl.last[0], vy - pl.last[1])
	for h in a.humans {
		rx, ry := a.x - h.x, a.y - h.y
		cx, cy := closest(rx, ry, vx - h.wx, vy - h.wy, horizon)
		gap := hyp(cx, cy) - h.r
		want := pl.human_stop + berth

		// How far ahead of a walker, along its course, the body is at the closest approach, as a
		// cosine; NaN, which adds nothing, for a human that stands or where they would meet.
		ahead := (cx * h.wx + cy * h.wy) / (hyp(cx, cy) * hyp(h.wx, h.wy))
		short := want + (if ahead > 0.0 { front * ahead } else { 0.0 }) - gap
		if short > 0.0 {
			cost += crowd * a.top * short * short
		}
		if gap < pl.human_stop {
			cost += wall * a.top
		}

		// Inside the berth a step toward the human costs, so a base that brakes along its last
		// motion, as the MuJoCo base does, seldom moves toward a human who walks inside human_stop.
		near := hyp(rx, ry)
		toward := -(vx * rx + vy * ry) / near
		if near - h.r < want && toward > 0.0 {
			cost += wall * toward
		}
	}

	// A solid that stands counts only until the body could have covered the way, so an approach
	// that ends at a target beside a pillar slows before it; one that walks, over the horizon.
	speed := hyp(vx, vy)
	until := if speed * horizon > a.length { a.length / speed } else { horizon }
	for o in a.obstacles {
		over := if o.walks { horizon } else { until }
		cx, cy := closest(a.x - o.x, a.y - o.y, vx - o.wx, vy - o.wy, over)
		gap := hyp(cx, cy) - o.r
		if gap < pl.solid_keep {
			cost += press * a.top * (pl.solid_keep - gap)
		}
	}
	return gain - cost
}

// closest is where something rx, ry from another stands relative to it at their closest within
// until seconds, while it moves at ux, uy relative to the other.
fn closest(rx f64, ry f64, ux f64, uy f64, until f64) (f64, f64) {
	uu := ux * ux + uy * uy
	t := if uu > 0.0 { math.max(0.0, math.min(until, -(rx * ux + ry * uy) / uu)) } else { 0.0 }
	return rx + ux * t, ry + uy * t
}

fn hyp(x f64, y f64) f64 {
	return math.sqrt(x * x + y * y)
}

fn finite(v []f64) bool {
	return v.all(math.is_finite(it))
}
