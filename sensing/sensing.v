// Sensing: what the field unit knows of its scene under SENSING=range. An Eva knows the world only
// through its sensors, and the entry plug shows the pilot that view; here the tracker turns the
// range ring's beams and the person detector's reports into the scene the armor, the planner, the
// dummy plug, MAGI and the bridge read, so no reader past it sees ground truth (ADR-0011).
module sensing

import math
import lcl

// grow is how far, in meters, a sensed circle reaches past the farthest hit it holds.
const grow = 0.02

// split_min is the least gap, in meters, between two consecutive hits that puts them into two
// groups; three beam spacings at their range split them where that is wider.
const split_min = 0.15

// piece_max is the widest, in meters, a piece of a group may span where the circle fitted to the
// whole group would reach the body; a piece spans a quarter of its distance from the body at most.
const piece_max = 0.5

// gate_speed is the fastest, in m/s, a track may move between two sightings and stay one track,
// the fastest walker a world file allows (body/world.v walk_max).
const gate_speed = 2.0

// gate_slack is how far, in meters, a track may jump between two sightings besides its walk, as a
// fitted circle's center does from one view to the next.
const gate_slack = 0.2

// walking is the least speed, in m/s, a track reports as motion; planner/planner.v walking holds
// the same 0.05, below which the planner counts a human or an obstacle as standing.
const walking = 0.05

// forget_ms is how long, in milliseconds, a track that nothing has seen stays at its last place
// while the ring sees into every place it may be. It also caps the time a sighting's gate grows
// with, so a person who turns up beyond 2.2 m of a hidden track's first hidden stretch starts a
// track of their own.
const forget_ms = 1000

// hide_ms is how long, in milliseconds, a person's track that nothing has seen stays while the ring
// cannot see into some place on its course. It covers the default world's walker behind o1, unseen
// for up to 6.2 s on the mock, and equals MAGI's default cooldown, so a track the ring cannot confirm
// holds a release back for about one vote; it does not cover longer hiding, such as the loop walker
// of worlds/example.json behind o1 for about 29 s, or Ritsuko on ep13-iruel for up to 142 s (ADR-0011).
const hide_ms = 10000

// core is the share of a person's radius that the ring must see into for a place to count as seen:
// the person has moved since the last sighting, so a place whose rim alone shows may still hide them.
const core = 0.5

// step is the spacing, in meters, of the places on a hidden track's course that the tracker checks.
const step = 0.1

// gain is the share of the residual against the position a track predicted that each sighting adds
// to the track's velocity, per second of the time between them.
const gain = 0.3

// turn_ms is the least time, in milliseconds, over which a track's velocity has to turn before the
// turn counts as its turn rate: about a second, which a walker on the default world's ellipse
// keeps, and over which the residual filter's lag behind a steady turn cancels out.
const turn_ms = 1000

// slim is the radius, in meters, of the slimmest person unseen looks for where the ring cannot see:
// a child, or an adult seen side on, slimmer than the 0.3 m of every human the world files hold.
const slim = 0.2

// look is the spacing, in meters, of the places along a beam that unseen checks.
const look = 0.02

// cell is the side, in meters, of the squares a Room keeps.
const cell = 0.1

// margin is how far, in meters, a Room reaches past the fence; a person may come from beyond it
// at any time.
const margin = 2.0

// spread is how fast, in m/s, the squares where a person may stand unseen grow through the ring's
// shadow: gate_speed, the fastest walker a world file allows, raised by a tenth, since steps
// between neighboring squares overstate a straight walk by up to 8%.
const spread = gate_speed * 1.1

// never is a Room's time for a square where no person may stand unseen until one walks in.
const never = 1e18

// ni and nj are the steps to a square's eight neighbors, the four sides first.
const ni = [-1, 1, 0, 0, -1, 1, -1, 1]
const nj = [0, 0, -1, 1, -1, -1, 1, 1]

// Tracker is the field tier's memory of what the range ring and the person detector have seen.
// main.v's field loop hands every percept of body.Ranged to percept before any reader gets it.
pub struct Tracker {
pub:
	reach f64   // m, from the body's center to a rim, within which unseen reports a place; 0 reports none
	fence []f64 // xmin, ymin, xmax, ymax, the area a Room keeps margin beyond; empty keeps none
mut:
	room   Room
	tracks []Track
	people int         // ids made for people so far
	solids int         // ids made for sensed solids so far
	ring   lcl.Percept // the raw percept of the tick before, whose ring found each hidden stretch
}

struct Track {
mut:
	id        string
	kind      string // human or obstacle
	pos       []f64  // m, where it was last seen
	at        []f64  // m, where the scene shows it
	r         f64
	vel       []f64 = [0.0, 0.0]
	sightings int
	seen_ms   i64
	hidden    bool  // a person nothing has seen who may stand where the ring cannot see
	lo        []f64 // m, where the first hidden stretch of its course begins
	hi        []f64 // m, where that stretch ends
	back      []f64 // m/s, its velocity at back_ms, from which turn is measured
	back_ms   i64
	turn      f64 // rad/s, counterclockwise, how fast its velocity turned from back to a sighting
}

// Seen is one sighting, a person the detector reported or a circle around the ring's hits.
struct Seen {
	kind string
	pos  []f64
	r    f64
}

// Hit is where beam i of n ended, at d meters from the body.
struct Hit {
	i  int
	d  f64
	at []f64
}

// Circle is a circle that holds the hits pts.
struct Circle {
	pos []f64
	r   f64
	pts [][]f64
}

struct Pair {
	track int
	seen  int
	d     f64
}

// percept is raw as the stack reads it: its map entries as they are, then every track of a person
// and then of a solid, each at its newest sighting with ids that stay with their track, p1, p2 for
// people and s1, s2 for solids, and no scan. raw comes from body.Ranged: the map, the detector's
// people without id or velocity, and the scan. A track carries a velocity from its second sighting
// on, and none below walking; one nothing has seen stays at its last place for forget_ms. A person
// nothing has seen who may stand where the ring cannot see, behind a solid or another person, stays
// for hide_ms instead, at the place nearest the body where they may stand (Track.hide). A person
// the ring never saw goes into unseen instead, the place nearest the body within reach where one
// may stand unseen.
pub fn (mut t Tracker) percept(raw lcl.Percept) lcl.Percept {
	people := raw.scene.filter(it.kind == 'human' && it.pos.len == 2)
	mut seen := people.map(Seen{
		kind: 'human'
		pos:  it.pos.clone()
		r:    it.r
	})
	for c in circles(hits(raw, people), raw.scan.len, raw.pose) {
		seen << Seen{
			kind: 'obstacle'
			pos:  c.pos
			r:    c.r
		}
	}
	t.update(seen, raw)
	mut scene := raw.scene.filter(it.kind != 'human')
	if t.fence.len == 4 && t.room.from.len == 0 {
		t.room = new_room(t.fence)
	}
	for kind in ['human', 'obstacle'] {
		for k in t.tracks {
			if k.kind == kind {
				scene << k.entity()
			}
		}
	}
	t.room.look(raw, scene)
	return lcl.Percept{
		...raw
		scene:  scene
		scan:   []f64{}
		unseen: unseen(raw, scene, t.reach, t.room)
	}
}

// unseen is the place nearest the body, by its rim, where a person of radius slim may stand with
// that rim within reach of the body's center while the ring of raw sees into no part of them:
// behind something a beam met, clear of every obstacle and person of scene, so inside neither, and
// where room says a person may have come unseen since the ring last saw into it. It
// holds at most that one place, since the armor reads only the nearest, as a person for its
// separation and its release check: the hidden sector the owner chose to count as a person on
// 2026-11-07 (ADR-0011). It looks along each beam that ended within reach, every look meters from
// just behind its return, which finds the place to within look and a beam spacing.
// ponytail: places on the beams only, against the sensed circles, so a wall whose circle overstates
// it hides a place just behind it that unseen skips; checks every place per beam until the nearest,
// some thousands a tick beside a pillar, so a ring of finer beams or a reach well past 2 m wants a
// search that steps from shadow edge to shadow edge instead.
fn unseen(raw lcl.Percept, scene []lcl.Entity, reach f64, room Room) []lcl.Entity {
	n := raw.scan.len
	if n == 0 || raw.pose.len != 2 || !(reach > 0.0) {
		return []lcl.Entity{}
	}
	solids := scene.filter(it.kind in ['obstacle', 'human'])
	mut best := []f64{}
	mut far := reach + slim // m, from the body's center to the nearest place's center found so far
	for i, d in raw.scan {
		if !(d >= 0.0 && d + slim < far) {
			continue
		}
		a := raw.heading + f64(i) * 2.0 * math.pi / f64(n)
		dir := [math.cos(a), math.sin(a)]
		for s := d + slim; s < far; s += look {
			at := [raw.pose[0] + s * dir[0], raw.pose[1] + s * dir[1]]
			if solids.all(lcl.dist(at, it.pos) >= it.r + slim) && room.open(at, raw.t_ms)
				&& shadowed(raw, at, slim) {
				best, far = at.clone(), s
				break
			}
		}
	}
	if best.len == 0 {
		return []lcl.Entity{}
	}
	return [lcl.Entity{
		id:   'unseen'
		kind: 'human'
		pos:  best
		r:    slim
	}]
}

// update matches each sighting to the nearest track of its kind that it may have walked from since
// that track was last seen, each track and each sighting once and the nearest pairs first, the
// tracks the ring did not lose before the people it may hide, starts a track for each sighting left
// over, moves each person nothing saw in raw to where they may hide, and drops each track nothing has
// seen for forget_ms, or for hide_ms where the person may hide. A sighting may have walked from a
// track when it lies within the distance gate_speed covers since the track's last sighting,
// forget_ms of it at most, plus gate_slack, of its last place, or for a hidden track of the first
// hidden stretch of its course, no farther ahead of where that course has led than the track's
// radius plus gate_slack, and with the way to it from that stretch hidden from the ring of the tick
// before (hid_path). So a person who steps out of hiding takes their track back, where they stood a
// tick before in that stretch or walked from it unseen, as one who turned or stopped does, while a
// person the tracker follows in view keeps their own track, and a newcomer from behind another solid,
// whose way from that stretch crosses ground the ring of the tick before saw into, or from the same
// shadow ahead of the course, starts a track of their own, and the hidden track stays.
fn (mut t Tracker) update(seen []Seen, raw lcl.Percept) {
	t_ms := raw.t_ms
	mut pairs := []Pair{}
	for i, k in t.tracks {
		gate := gate_speed * f64(math.min(math.max(i64(0), t_ms - k.seen_ms), forget_ms)) / 1000.0 +
			gate_slack
		for j, s in seen {
			from := if k.hidden { nearest(s.pos, k.lo, k.hi) } else { k.pos }
			d := lcl.dist(s.pos, from)
			if s.kind != k.kind || !(d <= gate) {
				continue
			}
			if k.hidden && (k.ahead(s.pos, t_ms) > k.r + gate_slack
				|| !hid_path(t.ring, from, s.pos, k.r)) {
				continue
			}
			pairs << Pair{i, j, d}
		}
	}
	pairs.sort(a.d < b.d)
	mut took := []bool{len: t.tracks.len}
	mut used := []bool{len: seen.len}
	for hidden in [false, true] {
		for p in pairs {
			if took[p.track] || used[p.seen] || t.tracks[p.track].hidden != hidden {
				continue
			}
			took[p.track] = true
			used[p.seen] = true
			t.tracks[p.track].sight(seen[p.seen], t_ms)
		}
	}
	for i, mut k in t.tracks {
		if !took[i] && k.kind == 'human' {
			k.hide(raw)
		}
	}
	t.tracks = t.tracks.filter(t_ms - it.seen_ms <= if it.hidden { hide_ms } else { forget_ms })
	for j, s in seen {
		if used[j] {
			continue
		}
		id := if s.kind == 'human' {
			t.people++
			'p${t.people}'
		} else {
			t.solids++
			's${t.solids}'
		}
		t.tracks << Track{
			id:        id
			kind:      s.kind
			pos:       s.pos.clone()
			at:        s.pos.clone()
			r:         s.r
			sightings: 1
			seen_ms:   t_ms
		}
	}
	t.ring = raw
}

// sight moves the track to s, seen at t_ms. Its velocity is the step from the first sighting to the
// second, and from then on moves by gain of the residual against where the track predicted itself.
// Its turn rate is how far that velocity turned from the one it kept back, once turn_ms or more ago,
// over the time between, and the velocity it keeps back moves on to this one; a track has none
// until its velocity is turn_ms old.
fn (mut k Track) sight(s Seen, t_ms i64) {
	dt := f64(t_ms - k.seen_ms) / 1000.0
	if dt > 0.0 {
		if k.sightings == 1 {
			k.vel = lcl.scale(lcl.sub(s.pos, k.pos), 1.0 / dt)
		} else {
			res := lcl.sub(s.pos, lcl.add(k.pos, lcl.scale(k.vel, dt)))
			k.vel = lcl.add(k.vel, lcl.scale(res, gain / dt))
		}
		k.sightings++
		k.seen_ms = t_ms
		if k.back.len == 0 {
			k.back, k.back_ms = k.vel.clone(), t_ms
		} else if t_ms - k.back_ms >= turn_ms {
			cross := k.back[0] * k.vel[1] - k.back[1] * k.vel[0]
			k.turn = math.atan2(cross, lcl.dot(k.back, k.vel)) / (f64(t_ms - k.back_ms) / 1000.0)
			k.back, k.back_ms = k.vel.clone(), t_ms
		}
	}
	k.pos = s.pos.clone()
	k.at = s.pos.clone()
	k.r = s.r
	k.hidden = false
}

// hide places a track nothing saw in raw. Its course runs from where it was last seen along its
// velocity for the time since, so it holds the place of a person who stopped and of one who walked
// on. Where the ring of raw cannot see into some place on that course, the person may stand there
// unseen: the track is hidden and shows at the one of those places nearest the body, so it is never
// farther from the body than a person who kept the course it estimated or stopped on it, and keeps
// its velocity, so MAGI's course rule and the planner still see them walk. Otherwise it shows at its
// last place, as one the ring sees through. A track hidden after its first sighting has no velocity,
// so it stays at that place, as a person who stands there would. The track keeps the first hidden
// stretch of its course, from the last sighting on, for update's gate. A hidden track whose person
// was turning shows instead at the hidden place nearest the body on the arc their turn rate bends
// that course into, where that place is nearer the body still, so a walker who keeps turning as
// they did is shown on their way rather than off it, and the track is never farther from the body
// than on its straight course; the arc changes neither whether the track is hidden nor its stretch.
// ponytail: a straight course or one arc of the turn rate measured over the last second or more of
// sightings, judged on the ring of one tick and kept for hide_ms at most, so a walker who reverses
// the turn while hidden, or turns after less than turn_ms in view, is shown at the straight
// course's place and one who turns harder than measured passes inside the arc, so each can be shown
// farther than they are, as can one who sped up in the last ticks before the ring lost them; one
// hidden longer or never seen goes unreported; and a person who steps out of the same shadow beside
// that stretch, a newcomer or one whose own track is hidden too, or a newcomer from a shadow that
// joined it only after the person hid, as a moving solid's or one the body's drive turned, takes
// the track (PLAN, Known issue 43); should a measurement show such a person within 2 m of a
// release, count a hidden sector within 2 m as a person, the owner's fallback (docs/decisions.md,
// 2026-10-08).
fn (mut k Track) hide(raw lcl.Percept) {
	end := k.reach(raw.t_ms)

	// A velocity from two sightings 20 ms apart can be some m/s off, so the places are capped, and
	// math.min reads a NaN length as the cap.
	n := int(math.min(lcl.dist(k.pos, end) / step, 1000.0)) + 1
	mut best := []f64{}
	k.lo, k.hi = []f64{}, []f64{}
	mut past := false // beyond the first hidden stretch
	for i in 0 .. n + 1 {
		at := lcl.add(k.pos, lcl.scale(lcl.sub(end, k.pos), f64(i) / f64(n)))
		if !shadowed(raw, at, core * k.r) {
			past = k.lo.len > 0
			continue
		}
		if k.lo.len == 0 {
			k.lo = at.clone()
		}
		if !past {
			k.hi = at.clone()
		}
		if best.len == 0 || lcl.dist(raw.pose, at) < lcl.dist(raw.pose, best) {
			best = at.clone()
		}
	}
	near := nearest(raw.pose, k.pos, end)
	if shadowed(raw, near, core * k.r)
		&& (best.len == 0 || lcl.dist(raw.pose, near) < lcl.dist(raw.pose, best)) {
		best = near.clone()
	}
	k.hidden = best.len > 0
	if k.hidden && k.lo.len == 0 {
		k.lo, k.hi = best.clone(), best.clone()
	}
	if k.hidden && k.turn != 0.0 {
		tau := f64(raw.t_ms - k.seen_ms) / 1000.0
		for i in 0 .. n + 1 {
			at := k.along(tau * f64(i) / f64(n))
			if lcl.dist(raw.pose, at) < lcl.dist(raw.pose, best) && shadowed(raw, at, core * k.r) {
				best = at.clone()
			}
		}
	}
	k.at = if k.hidden { best } else { k.pos.clone() }
}

// along is where the course of a track stands t seconds after its last sighting on the arc its
// turn rate bends its velocity into, its straight course where it has none.
fn (k Track) along(t f64) []f64 {
	half := k.turn * t / 2.0
	chord := if half == 0.0 { t } else { t * math.sin(half) / half }
	c, s := math.cos(half), math.sin(half)
	return lcl.add(k.pos, lcl.scale([k.vel[0] * c - k.vel[1] * s, k.vel[0] * s + k.vel[1] * c],
		chord))
}

// reach is where the course of a track ends at t_ms: its last place moved along its velocity for
// the time since it was seen.
fn (k Track) reach(t_ms i64) []f64 {
	return lcl.add(k.pos, lcl.scale(k.vel, f64(t_ms - k.seen_ms) / 1000.0))
}

// ahead is how far, in meters, p lies past the end of the course of k at t_ms, along that course,
// or 0 for a track that has no course.
fn (k Track) ahead(p []f64, t_ms i64) f64 {
	end := k.reach(t_ms)
	l := lcl.dist(k.pos, end)
	if !(l > 0.0) {
		return 0.0
	}
	return lcl.dot(lcl.sub(p, end), lcl.sub(end, k.pos)) / l
}

// entity is the track as a percept's scene lists it, with its velocity only once it has one of
// walking or more.
fn (k Track) entity() lcl.Entity {
	moving := k.sightings >= 2 && lcl.norm(k.vel) >= walking
	return lcl.Entity{
		id:   k.id
		kind: k.kind
		pos:  k.at.clone()
		r:    k.r
		vel:  if moving { k.vel.clone() } else { []f64{} }
	}
}

// hits is where each beam of raw's scan ended short of lcl.scan_range, in beam order, without the
// hits on a person the detector reported, which that person's track covers. Beam i of n points i
// turns of 360 / n degrees counterclockwise from the heading, as body/ranged.v scan casts it.
fn hits(raw lcl.Percept, people []lcl.Entity) []Hit {
	mut out := []Hit{}
	n := raw.scan.len
	if raw.pose.len != 2 || n == 0 {
		return out
	}
	for i, d in raw.scan {
		if !(d >= 0.0 && d < lcl.scan_range) {
			continue
		}
		a := raw.heading + f64(i) * 2.0 * math.pi / f64(n)
		at := [raw.pose[0] + d * math.cos(a), raw.pose[1] + d * math.sin(a)]
		if people.any(lcl.dist(at, it.pos) <= it.r + grow) {
			continue
		}
		out << Hit{i, d, at}
	}
	return out
}

// shadowed reports whether the ring of raw cannot see into the circle at at of radius r: a beam
// crosses it, and every beam that does ended on a return short of where it enters, so the place lies
// in the shadow of something nearer. A beam that met nothing within lcl.scan_range is no return, so
// a place beyond the ring's reach is no hiding place, and the body inside the circle sees it.
fn shadowed(raw lcl.Percept, at []f64, r f64) bool {
	n := raw.scan.len
	if n == 0 || raw.pose.len != 2 || at.len != 2 || lcl.dist(raw.pose, at) <= r {
		return false
	}
	spacing := 2.0 * math.pi / f64(n)
	mid := math.atan2(at[1] - raw.pose[1], at[0] - raw.pose[0]) - raw.heading
	half := math.asin(r / lcl.dist(raw.pose, at))

	// A NaN would make the beam range below unbounded, and the cast to int of one undefined.
	if !math.is_finite(mid) || !math.is_finite(half) {
		return false
	}
	mut crossed := false
	for i in int(math.ceil((mid - half) / spacing)) .. int(math.floor((mid + half) / spacing)) + 1 {
		a := raw.heading + f64(i) * spacing
		enter := lcl.ray(raw.pose, [math.cos(a), math.sin(a)], at, r) or { continue }
		d := raw.scan[(i % n + n) % n]
		if d >= enter || d >= lcl.scan_range {
			return false
		}
		crossed = true
	}
	return crossed
}

// hid_path reports whether the ring of raw saw into no place on the line from a to b but its last
// gate_slack, so a person of radius r hidden at a could have walked to b unseen. One who steps out
// of hiding at b stood unseen at raw's tick a step from b, so raw saw into no place of their core
// within about 0.1 m of b, and none on the line from a either where a lies in the same shadow,
// which is convex.
fn hid_path(raw lcl.Percept, a []f64, b []f64, r f64) bool {
	l := lcl.dist(a, b)
	w := l - gate_slack // m, the part of the way to check
	if !(w > 0.0) {
		return true
	}
	n := int(w / step) + 1
	for i in 0 .. n + 1 {
		at := lcl.add(a, lcl.scale(lcl.sub(b, a), w / l * f64(i) / f64(n)))
		if !shadowed(raw, at, core * r) {
			return false
		}
	}
	return true
}

// nearest is the point of the segment from a to b nearest p.
fn nearest(p []f64, a []f64, b []f64) []f64 {
	ab := lcl.sub(b, a)
	l2 := lcl.dot(ab, ab)
	if l2 == 0.0 {
		return a
	}
	return lcl.add(a, lcl.scale(ab, math.max(0.0, math.min(1.0, lcl.dot(lcl.sub(p, a), ab) / l2))))
}

// circles groups consecutive hits of a ring of n beams, closing the ring, and covers each group
// with circles that hold every one of its hits and none of which reaches pose, the body's center.
fn circles(hs []Hit, n int, pose []f64) []Circle {
	mut groups := [][]Hit{}
	for h in hs {
		if groups.len > 0 && joined(groups.last().last(), h, n) {
			groups[groups.len - 1] << h
		} else {
			groups << [h]
		}
	}
	if groups.len > 1 && joined(groups.last().last(), groups[0][0], n) {
		mut wrapped := groups.pop()
		wrapped << groups[0]
		groups[0] = wrapped
	}
	mut out := []Circle{}
	for g in groups {
		for c in cover(g.map(it.at), pose) {
			out = merged(out, c)
		}
	}
	return out
}

// merged is cs with c added, or without it where a circle of cs already holds every hit of c, as a
// pillar's circle holds a hit grazing its rim or the arc on the far side of a person's shadow, or
// with c in place of every circle of cs whose every hit c holds. Every circle of cs and c keeps off
// the body's center, so the result does.
fn merged(cs []Circle, c Circle) []Circle {
	for m in cs {
		if holds(m, c.pts) {
			return cs
		}
	}
	mut out := []Circle{cap: cs.len + 1}
	for m in cs {
		if !holds(c, m.pts) {
			out << m
		}
	}
	out << c
	return out
}

// holds reports whether every point of pts lies inside c, its rim included.
fn holds(c Circle, pts [][]f64) bool {
	return pts.all(lcl.dist(c.pos, it) <= c.r)
}

// joined reports whether hit b on the next beam after a's of a ring of n lies close enough to a to
// share its group.
fn joined(a Hit, b Hit, n int) bool {
	spacing := 2.0 * math.pi / f64(n)
	return (a.i + 1) % n == b.i
		&& lcl.dist(a.at, b.at) < math.max(split_min, 3.0 * math.max(a.d, b.d) * spacing)
}

// cover is circles that hold every point of pts, in order: the one fit gives, unless it would reach
// pose, the body's center, as for a group seen from inside a cup of discs; then one around the
// centroid of each piece of pts that spans piece_max, or a quarter of its first point's distance
// from pose, at most, which keeps each piece's circle off pose.
fn cover(pts [][]f64, pose []f64) []Circle {
	c := fit(pts)
	if lcl.dist(pose, c.pos) > c.r {
		return [c]
	}
	mut out := []Circle{}
	mut from := 0
	for i in 1 .. pts.len + 1 {
		if i == pts.len
			|| lcl.dist(pts[from], pts[i]) > math.min(piece_max, lcl.dist(pose, pts[from]) / 4.0) {
			out << around(pts[from..i], centroid(pts[from..i]))
			from = i
		}
	}
	return out
}

// fit is a circle that holds every point of pts, grow beyond the farthest: around the least squares
// circle through three or more points, else, for one or two points or points on a line, around
// their centroid.
fn fit(pts [][]f64) Circle {
	m := centroid(pts)
	return around(pts, if pts.len >= 3 { kasa(pts, m) or { m } } else { m })
}

// around is the circle at center that holds every point of pts, grow beyond the farthest.
fn around(pts [][]f64, center []f64) Circle {
	mut r := 0.0
	for p in pts {
		r = math.max(r, lcl.dist(center, p))
	}
	return Circle{
		pos: center
		r:   r + grow
		pts: pts
	}
}

fn centroid(pts [][]f64) []f64 {
	mut c := [0.0, 0.0]
	for p in pts {
		c = lcl.add(c, p)
	}
	return lcl.scale(c, 1.0 / f64(pts.len))
}

// kasa is the center of the algebraic least squares circle through pts, solved about their
// centroid m, or none when pts lie on a line, where no circle fits.
fn kasa(pts [][]f64, m []f64) ?[]f64 {
	mut suu, mut suv, mut svv := 0.0, 0.0, 0.0
	mut ru, mut rv := 0.0, 0.0
	for p in pts {
		u, v := p[0] - m[0], p[1] - m[1]
		suu += u * u
		suv += u * v
		svv += v * v
		ru += u * (u * u + v * v)
		rv += v * (u * u + v * v)
	}
	det := suu * svv - suv * suv
	if !(det > 1e-10 * (suu * svv + suv * suv)) {
		return none
	}
	uc := (ru * svv - rv * suv) / (2.0 * det)
	vc := (rv * suu - ru * suv) / (2.0 * det)
	return [m[0] + uc, m[1] + vc]
}

// Room is where a person may stand unseen, so that a shadow the ring saw empty a moment ago holds
// no one until a person could have walked into it: for each square of cell meters over the fence
// and margin beyond it, the time from which a person's center may lie there while the ring sees no
// part of them. A square the ring sees through, or one inside a sensed obstacle, holds no one; a
// square in the ring's shadow holds one from the time a person could have walked to it at spread
// through the shadow from a square that held one, or from beyond the Room's edge, where a person may
// always come from, stepping in no sooner than the ring last saw it. At the start every square holds
// one, since the ring has seen nothing yet.
// ponytail: squares of 0.1 m at a person's fastest walk through the shadow as it stands this tick,
// so a person who walked through a part the ring saw into later counts as reaching it; costs a pass
// over some 20000 squares a tick, 0.5 ms in a release build and 4 ms in a dev build, so a larger
// area wants squares around the body only.
struct Room {
mut:
	x0   f64
	y0   f64
	nx   int
	ny   int
	from []f64 // ms on the percepts' clock from which a person may stand there unseen, never where none may
	seen []f64 // ms when the ring last saw through the square or an obstacle filled it, -never before
}

// new_room is a Room over fence, xmin, ymin, xmax, ymax, and margin beyond it, every square holding
// a person from the start.
fn new_room(fence []f64) Room {
	nx := int(math.ceil((fence[2] - fence[0] + 2.0 * margin) / cell))
	ny := int(math.ceil((fence[3] - fence[1] + 2.0 * margin) / cell))
	return Room{
		x0:   fence[0] - margin
		y0:   fence[1] - margin
		nx:   nx
		ny:   ny
		from: []f64{len: nx * ny, init: -never}
		seen: []f64{len: nx * ny, init: -never}
	}
}

// open reports whether a person's center may lie at at unseen at t_ms. A Room with no squares, and a
// place beyond its edge, hold one always.
fn (m Room) open(at []f64, t_ms i64) bool {
	i := int(math.floor((at[0] - m.x0) / cell))
	j := int(math.floor((at[1] - m.y0) / cell))
	if m.from.len == 0 || i < 0 || j < 0 || i >= m.nx || j >= m.ny {
		return true
	}
	return m.from[j * m.nx + i] <= f64(t_ms)
}

// look clears every square raw's ring sees through and every square inside an obstacle of scene,
// and grows the squares that may hold a person through the rest, a pass forward and one back.
fn (mut m Room) look(raw lcl.Percept, scene []lcl.Entity) {
	if m.from.len == 0 || raw.pose.len != 2 || raw.scan.len == 0 {
		return
	}
	solids := scene.filter(it.kind == 'obstacle')
	mut shut := []bool{len: m.from.len}
	for j in 0 .. m.ny {
		for i in 0 .. m.nx {
			x := m.x0 + (f64(i) + 0.5) * cell
			y := m.y0 + (f64(j) + 0.5) * cell
			k := j * m.nx + i
			if solids.any(math.hypot(x - it.pos[0], y - it.pos[1]) < it.r) || through(raw, x, y) {
				m.from[k] = never
				m.seen[k] = f64(raw.t_ms)
				shut[k] = true
			}
		}
	}
	side := cell / spread * 1000.0 // ms a person needs to the next square across a side
	corner := side * math.sqrt2
	for pass in 0 .. 2 {
		for jj in 0 .. m.ny {
			j := if pass == 0 { jj } else { m.ny - 1 - jj }
			for ii in 0 .. m.nx {
				i := if pass == 0 { ii } else { m.nx - 1 - ii }
				k := j * m.nx + i
				if shut[k] {
					continue
				}
				// A person steps in from a neighbor no sooner than they stood there and than the ring
				// last saw this square, and from beyond the edge at any time.
				mut best := m.from[k]
				for q in 0 .. 8 {
					x, y := i + ni[q], j + nj[q]
					by := if q < 4 { side } else { corner }
					there := if x < 0 || y < 0 || x >= m.nx || y >= m.ny {
						-never
					} else {
						m.from[y * m.nx + x]
					}
					best = math.min(best, math.max(there, m.seen[k]) + by)
				}
				m.from[k] = best
			}
		}
	}
}

// through reports whether raw's ring sees through the square at x, y: the beam nearest its bearing
// ended at or past its center, so a person of radius slim centered anywhere in it would have
// stopped that beam, which passes within 0.16 m of every point of the square out to lcl.scan_range,
// and the detector would have reported them. The body's own place counts as seen.
fn through(raw lcl.Percept, x f64, y f64) bool {
	d := math.hypot(x - raw.pose[0], y - raw.pose[1])
	if d <= slim {
		return true
	}
	if d >= lcl.scan_range {
		return false
	}
	n := raw.scan.len
	a := math.atan2(y - raw.pose[1], x - raw.pose[0]) - raw.heading
	if !math.is_finite(a) {
		return false
	}
	i := int(math.round(a / (2.0 * math.pi / f64(n))))
	return raw.scan[(i % n + n) % n] >= d
}
