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

// forget_ms is how long, in milliseconds, a track that nothing has seen stays at its last place.
const forget_ms = 1000

// gain is the share of the residual against the position a track predicted that each sighting adds
// to the track's velocity, per second of the time between them.
const gain = 0.3

// Tracker is the field tier's memory of what the range ring and the person detector have seen.
// main.v's field loop hands every percept of body.Ranged to percept before any reader gets it.
pub struct Tracker {
mut:
	tracks []Track
	people int // ids made for people so far
	solids int // ids made for sensed solids so far
}

struct Track {
mut:
	id        string
	kind      string // human or obstacle
	pos       []f64
	r         f64
	vel       []f64 = [0.0, 0.0]
	sightings int
	seen_ms   i64
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
// on, and none below walking; one nothing has seen stays at its last place for forget_ms.
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
	t.update(seen, raw.t_ms)
	mut scene := raw.scene.filter(it.kind != 'human')
	for kind in ['human', 'obstacle'] {
		for k in t.tracks {
			if k.kind == kind {
				scene << k.entity()
			}
		}
	}
	return lcl.Percept{
		...raw
		scene: scene
		scan:  []f64{}
	}
}

// update matches each sighting to the nearest track of its kind that it may have walked from since
// that track was last seen, each track and each sighting once and the nearest pairs first, starts a
// track for each sighting left over, and drops each track nothing has seen for forget_ms.
fn (mut t Tracker) update(seen []Seen, t_ms i64) {
	mut pairs := []Pair{}
	for i, k in t.tracks {
		gate := gate_speed * f64(math.max(i64(0), t_ms - k.seen_ms)) / 1000.0 + gate_slack
		for j, s in seen {
			if s.kind == k.kind {
				d := lcl.dist(k.pos, s.pos)
				if d <= gate {
					pairs << Pair{i, j, d}
				}
			}
		}
	}
	pairs.sort(a.d < b.d)
	mut took := []bool{len: t.tracks.len}
	mut used := []bool{len: seen.len}
	for p in pairs {
		if took[p.track] || used[p.seen] {
			continue
		}
		took[p.track] = true
		used[p.seen] = true
		t.tracks[p.track].sight(seen[p.seen], t_ms)
	}
	t.tracks = t.tracks.filter(t_ms - it.seen_ms <= forget_ms)
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
			r:         s.r
			sightings: 1
			seen_ms:   t_ms
		}
	}
}

// sight moves the track to s, seen at t_ms. Its velocity is the step from the first sighting to the
// second, and from then on moves by gain of the residual against where the track predicted itself.
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
	}
	k.pos = s.pos.clone()
	k.r = s.r
}

// entity is the track as a percept's scene lists it, with its velocity only once it has one of
// walking or more.
fn (k Track) entity() lcl.Entity {
	moving := k.sightings >= 2 && lcl.norm(k.vel) >= walking
	return lcl.Entity{
		id:   k.id
		kind: k.kind
		pos:  k.pos.clone()
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
