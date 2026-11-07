module sensing

import math
import lcl

// ring is the scan a ring of 360 beams from pose along heading 0 reads off the circles of solids,
// as body/ranged.v scan casts it.
fn ring(pose []f64, solids []Circle) []f64 {
	mut out := []f64{len: 360, init: lcl.scan_range}
	for i in 0 .. 360 {
		a := f64(i) * 2.0 * math.pi / 360.0
		for c in solids {
			t := lcl.ray(pose, [math.cos(a), math.sin(a)], c.pos, c.r) or { continue }
			out[i] = math.min(out[i], t)
		}
	}
	return out
}

// sighted is what body.Ranged senses at pose, heading 0, at t_ms: the ring's scan over the solids
// and the people, each person a disc of 0.3 m, and each person at least one beam ends on.
fn sighted(t_ms i64, pose []f64, people [][]f64, solids []Circle) lcl.Percept {
	mut discs := solids.clone()
	discs << people.map(disc(it, 0.3))
	scan := ring(pose, discs)
	mut seen := []lcl.Entity{}
	for p in people {
		for i in 0 .. 360 {
			a := f64(i) * 2.0 * math.pi / 360.0
			t := lcl.ray(pose, [math.cos(a), math.sin(a)], p, 0.3) or { continue }
			if t == scan[i] {
				seen << person(p)
				break
			}
		}
	}
	return lcl.Percept{
		t_ms:  t_ms
		pose:  pose
		scene: seen
		scan:  scan
	}
}

fn disc(pos []f64, r f64) Circle {
	return Circle{
		pos: pos
		r:   r
	}
}

fn arc(c []f64, r f64, from f64, to f64, n int) [][]f64 {
	return [][]f64{len: n, init: [
		c[0] + r * math.cos(from + (to - from) * f64(index) / f64(n - 1)),
		c[1] + r * math.sin(from + (to - from) * f64(index) / f64(n - 1)),
	]}
}

struct CoverCase {
	name string
	pts  [][]f64
	pose []f64
}

fn test_cover() {
	cases := [
		CoverCase{'a pillar seen from outside', arc([3.0, 0.0], 1.0, 2.2, 4.0, 40), [0.0, 0.0]},
		CoverCase{'a cup seen from inside', arc([0.0, 0.0], 2.0, -1.8, 1.8, 60), [0.0, 0.0]},
		CoverCase{'a cup seen from off its center', arc([0.5, 0.0], 1.2, -2.5, 2.5, 80), [
			0.0, 0.0]},
		CoverCase{'a straight wall', [][]f64{len: 20, init: [2.0, -1.0 + 0.1 * f64(index)]}, [
			0.0, 0.0]},
		CoverCase{'two hits', [[1.0, 0.0], [1.0, 0.02]], [0.0, 0.0]},
		CoverCase{'one hit', [[1.0, 0.0]], [0.0, 0.0]},
	]
	for c in cases {
		cs := cover(c.pts, c.pose)
		for p in c.pts {
			assert cs.any(lcl.dist(it.pos, p) <= it.r), '${c.name}: a hit outside every circle'
		}
		assert cs.all(lcl.dist(it.pos, c.pose) > it.r), '${c.name}: a circle reaches the body'
	}
}

// A pillar seen from outside fits its own circle, grown by grow.
fn test_a_pillar_fits_its_circle() {
	cs := cover(arc([3.0, 0.0], 1.0, 2.2, 4.0, 40), [0.0, 0.0])
	assert cs.len == 1
	assert lcl.dist(cs[0].pos, [3.0, 0.0]) < 1e-9 && math.abs(cs[0].r - 1.0 - grow) < 1e-9
}

// A solid that straddles the first beam stays one group across the ring's seam.
fn test_the_ring_closes() {
	scan := ring([0.0, 0.0], [disc([3.0, 0.0], 0.5)])
	assert scan[0] < lcl.scan_range && scan[359] < lcl.scan_range
	raw := lcl.Percept{
		pose: [0.0, 0.0]
		scan: scan
	}
	assert circles(hits(raw, []), 360, raw.pose).len == 1
}

fn person(pos []f64) lcl.Entity {
	return lcl.Entity{
		kind: 'human'
		pos:  pos
		r:    0.3
	}
}

fn reading(t_ms i64, pose []f64, people []lcl.Entity, solids []Circle) lcl.Percept {
	return lcl.Percept{
		t_ms:  t_ms
		pose:  pose
		scene: people
		scan:  ring(pose, solids)
	}
}

// A person walking straight at 0.5 m/s has no velocity on the first sighting and that velocity from
// the second on, under the same id, and the percept carries no scan.
fn test_a_straight_walker_has_its_velocity() {
	mut t := Tracker{}
	for k in 0 .. 50 {
		p := t.percept(reading(1000 + 20 * k, [0.0, 0.0], [
			person([-3.0 + 0.01 * f64(k), 2.0]),
		], []))
		assert p.scan.len == 0
		assert p.scene.len == 1 && p.scene[0].id == 'p1' && p.scene[0].kind == 'human'
		if k == 0 {
			assert p.scene[0].vel.len == 0
		} else {
			assert lcl.dist(p.scene[0].vel, [0.5, 0.0]) < 1e-9, 'tick ${k}'
		}
	}
}

// Two people keep their ids while they walk past each other in lanes 1 m apart, and one nobody
// sees any longer stays at its last place for forget_ms and is gone after.
fn test_an_id_stays_with_its_track() {
	mut t := Tracker{}
	mut p := lcl.Percept{}
	for k in 0 .. 100 {
		x := -2.0 + 0.02 * f64(k)
		p = t.percept(reading(20 * k, [0.0, -3.0], [person([x, 0.5]),
			person([-x, -0.5])], []))
		assert p.scene.map(it.id) == ['p1', 'p2'], 'tick ${k}'
		assert p.scene[0].pos[1] == 0.5 && p.scene[1].pos[1] == -0.5, 'tick ${k}'
	}
	last := p.scene[0].pos
	p = t.percept(reading(1980 + forget_ms, [0.0, -3.0], [person([-0.98, -0.5])], []))
	ids := p.scene.map(it.id)
	assert ids.len == 2 && 'p1' in ids && 'p2' in ids
	assert p.scene.filter(it.id == 'p1')[0].pos == last
	p = t.percept(reading(2000 + forget_ms, [0.0, -3.0], [person([-1.0, -0.5])], []))
	assert p.scene.map(it.id) == ['p2']
}

// A pillar reads as one solid that stands, under one id, while the body drives past it, and the
// hits on a person in front of it stay with the person.
fn test_a_pillar_stands_and_a_person_before_it_is_no_solid() {
	pillar := disc([3.0, 0.0], 0.8)
	mut t := Tracker{}
	for k in 0 .. 50 {
		pose := [0.0, -1.0 + 0.04 * f64(k)]
		front := person([1.6, pose[1]])
		p := t.percept(reading(20 * k, pose, [front], [pillar, disc(front.pos, front.r)]))
		solids := p.scene.filter(it.kind == 'obstacle')
		assert solids.len == 1 && solids[0].id == 's1', 'tick ${k}'
		assert solids[0].vel.len == 0, 'tick ${k}'
		assert lcl.dist(solids[0].pos, pillar.pos) < 1e-9, 'tick ${k}'
		assert math.abs(solids[0].r - pillar.r - grow) < 1e-9, 'tick ${k}'
	}
}

// The map passes in its order, ahead of the tracks.
fn test_the_map_passes_first() {
	mut t := Tracker{}
	raw := lcl.Percept{
		t_ms:  5
		pose:  [0.0, 0.0]
		scene: [
			lcl.Entity{
				id:   'b1'
				kind: 'beacon'
				pos:  [3.0, 2.0]
				r:    0.3
			},
			person([1.0, 1.0]),
			lcl.Entity{
				id:       'rock'
				kind:     'impact'
				pos:      [-2.0, 0.0]
				r:        0.5
				lands_in: 3.0
			},
		]
		scan:  ring([0.0, 0.0], [disc([0.0, 4.0], 0.5)])
	}
	p := t.percept(raw)
	assert p.scene.map(it.id) == ['b1', 'rock', 'p1', 's1']
	assert p.scene[1].lands_in == 3.0
}

struct ShadowCase {
	name    string
	solids  []Circle
	heading f64
	at      []f64
	r       f64
	want    bool
}

fn test_shadowed() {
	pillar := disc([3.0, 0.0], 0.8)
	edge := [5.0 * math.cos(13.0 * math.pi / 180.0), 5.0 * math.sin(13.0 * math.pi / 180.0)]
	cases := [
		ShadowCase{'behind a pillar', [pillar], 0.0, [5.0, 0.0], 0.15, true},
		ShadowCase{'behind a pillar, the body turned', [pillar], math.pi / 2.0, [5.0, 0.0], 0.15, true},
		ShadowCase{'beside a pillar in plain view', [pillar], 0.0, [5.0, 3.0], 0.15, false},
		ShadowCase{'before a pillar', [pillar], 0.0, [1.5, 0.0], 0.15, false},
		ShadowCase{'behind a pillar beyond the ring', [pillar], 0.0, [12.0, 0.0], 0.15, true},
		ShadowCase{'in plain view beyond the ring', [], 0.0, [12.0, 0.0], 0.15, false},
		ShadowCase{'its core behind the pillar', [pillar], 0.0, edge, 0.15, true},
		ShadowCase{'its rim past the pillar', [pillar], 0.0, edge, 0.3, false},
		ShadowCase{'behind a person', [disc([2.0, 0.0], 0.3)], 0.0, [4.0, 0.0], 0.15, true},
		ShadowCase{'around the body', [pillar], 0.0, [0.1, 0.0], 0.15, false},
		ShadowCase{'between two beams', [], 0.0, [30.0 * math.cos(math.pi / 360.0),
			30.0 * math.sin(math.pi / 360.0)], 0.15, false},
	]
	for c in cases {
		// beam i of a body turned by the heading is beam i + heading of the unturned ring
		turn := int(math.round(c.heading * 180.0 / math.pi))
		scan := ring([0.0, 0.0], c.solids)
		raw := lcl.Percept{
			pose:    [0.0, 0.0]
			heading: c.heading
			scan:    []f64{len: 360, init: scan[(index + turn) % 360]}
		}
		assert shadowed(raw, c.at, c.r) == c.want, c.name
	}
	assert !shadowed(lcl.Percept{ pose: [0.0, 0.0] }, [5.0, 0.0], 0.15), 'an empty scan'
	assert !shadowed(lcl.Percept{
		pose:    [0.0, 0.0]
		heading: math.nan()
		scan:    ring([0.0, 0.0], [pillar])
	}, [5.0, 0.0], 0.15), 'a heading that is no number'
}

struct HideCase {
	name    string
	from    []f64 // m, where the person starts
	vel     []f64 // m/s, how the person walks
	stop_s  f64   // s, when the person stops or turns
	then    []f64 // m/s, how the person walks after
	solids  []Circle
	until_s f64
	kept    bool // whether the tracker keeps the person unseen past forget_ms
	gap_s   f64  // s, the least time the person goes unseen in the case
}

// A person who walks behind a pillar keeps their track while hidden, up to hide_ms, at a place no
// farther from the body than they are and with its velocity, and keeps its id and gets a velocity
// at once when seen again, also far from where they went or off the course after a turn; one who
// leaves the ring's reach in plain view is forgotten after forget_ms.
fn test_percept() {
	pillar := disc([3.0, 0.0], 0.8)
	cases := [
		HideCase{'walks behind a pillar and out again', [4.5, -2.5], [0.0, 0.5], 99.0, [], [
			pillar], 10.0, true, 3.0},
		HideCase{'walks out again far from where they went', [5.0, -3.0], [0.0, 0.6], 99.0, [], [
			disc([3.0, 0.0], 1.0)], 9.0, true, 4.5},
		HideCase{'turns behind a pillar and walks out off the course', [4.5, -2.5], [0.0, 0.5], 5.0, [
			0.3, 0.4], [pillar], 10.0, true, 3.5},
		HideCase{'stops behind a pillar', [4.5, -2.5], [0.0, 0.5], 5.0, [0.0, 0.0], [pillar], 15.0, true, 11.0},
		HideCase{'walks toward the body behind a pillar', [6.0, -1.6], [-0.45, 0.24], 5.0, [
			0.0, 0.0], [pillar], 15.0, true, 11.0},
		HideCase{'leaves the ring in plain view', [8.5, 1.0], [0.5, 0.0], 99.0, [], [], 6.0, false, 2.0},
	]
	for c in cases {
		mut t := Tracker{}
		mut last := i64(-1) // ms, when the detector last reported the person
		mut gap := i64(0)
		for k in 0 .. int(c.until_s * 50.0) + 1 {
			t_ms := i64(20 * k)
			mut at := lcl.add(c.from, lcl.scale(c.vel, math.min(f64(t_ms) / 1000.0, c.stop_s)))
			if c.then.len == 2 && f64(t_ms) / 1000.0 > c.stop_s {
				at = lcl.add(at, lcl.scale(c.then, f64(t_ms) / 1000.0 - c.stop_s))
			}
			raw := sighted(t_ms, [0.0, 0.0], [at], c.solids)
			people := t.percept(raw).scene.filter(it.kind == 'human')
			ids := people.map(it.id)
			if raw.scene.len == 1 {
				assert ids == ['p1'], '${c.name}: ${ids} seen at ${t_ms} ms'
				if last >= 0 && last < t_ms - 20 {
					assert people[0].vel.len == 2, '${c.name}: back at ${t_ms} ms without a velocity'
				}
				last = t_ms
				continue
			}
			if last < 0 {
				continue
			}
			gap = math.max(gap, t_ms - last)
			life := if c.kept { hide_ms } else { forget_ms }
			want := if t_ms - last <= life { ['p1'] } else { []string{} }
			assert ids == want, '${c.name}: ${ids} at ${t_ms} ms, unseen for ${t_ms - last} ms'
			if ids.len == 1 && c.kept {
				assert lcl.norm(people[0].pos) - 1e-9 <= lcl.norm(at), '${c.name}: shown farther than the person at ${t_ms} ms'
				assert people[0].vel.len == 2, '${c.name}: hidden without a velocity at ${t_ms} ms'
			}
		}
		assert gap >= i64(c.gap_s * 1000.0), '${c.name}: unseen for ${gap} ms at most'
	}
}

struct NewcomerCase {
	name   string
	solids []Circle
	a      []f64 // m, where the person who hides starts
	a_vel  []f64 // m/s, how they walk
	a_stop f64   // s, when they stop
	b      []f64 // m, where the other person starts
	b_vel  []f64 // m/s, how the other person walks from b_from on
	b_from f64   // s
}

// A newcomer who steps out where the hidden person may not have walked starts a track of their own:
// in plain view, from behind another solid, also within 2.2 m of the first hidden stretch of the
// hidden person's course, into a gap of one beam the ring of the tick before saw beside the end of
// that stretch or that their own body now covers, or with a seen gap partway along the way from it,
// or from behind the same pillar beyond the gate of that stretch or ahead of where the course has
// led; and a person the tracker follows in view at the far edge of the same shadow, standing or
// crossing the course, keeps their own. The hidden person keeps theirs, in the scene, for as long as
// they stay hidden within hide_ms.
fn test_update() {
	deg := math.pi / 180.0
	u := [math.cos(36.4 * deg), math.sin(36.4 * deg)]
	c35 := [math.cos(35.0 * deg), math.sin(35.0 * deg)]

	// Each pole's shadow starts one beam past the shadow of the solid at angle 0: 23.6 degrees out
	// for the far pole, 18.6 for the near one.
	far := 23.6 * deg + math.asin(0.3)
	near := 18.6 * deg + math.asin(0.2 / 0.8)
	cases := [
		NewcomerCase{'in plain view', [disc([3.0, 0.0], 0.8)], [4.5, -1.5], [0.0, 0.5], 3.0, [
			0.0, 4.0], [0.0, 0.0], 5.0},
		NewcomerCase{'from behind another solid', [disc([1.0, 0.0], 0.4),
			disc([2.2, 2.0], 0.5)], [1.8, -1.5], [0.0, 0.5], 3.0, [3.5, 3.9], [0.0, -0.5], 5.0},
		NewcomerCase{'from behind the same pillar, 3 m off the course', [
			disc([3.0, 0.0], 0.8)], [4.5, -1.5], [0.0, 0.5], 3.0, [7.5, 0.0], [0.0, 0.5], 5.0},
		NewcomerCase{'from behind the same pillar, ahead of the course', [
			disc([3.0, 0.0], 0.8)], [4.5, -1.5], [0.0, 0.3], 99.0, [5.0, 0.5], [0.0, 0.5], 5.0},
		NewcomerCase{'from behind another solid, within 2.2 m of the stretch', [
			disc([1.0, 0.0], 0.4), disc([2.0, 2.2], 0.5)], [1.8, -1.5], [0.0, 0.5], 3.0, [
			3.0, 3.3], [-0.203, -0.457], 5.0},
		NewcomerCase{'from behind another solid, into a gap of one beam beside the end of the stretch', [
			disc([0.8, 0.0], 0.3), disc([math.cos(far), math.sin(far)], 0.3)], lcl.sub([
			1.6, -0.3], u), lcl.scale(u, 0.5), 2.0, lcl.scale(c35, 4.5), [0.5 * c35[1], -0.5 * c35[0]], 7.5},
		NewcomerCase{'from behind a nearer solid, into a gap of one beam their body now covers', [
			disc([1.0, 0.0], 0.3), disc([0.8 * math.cos(near), 0.8 * math.sin(near)], 0.2)], [
			2.0, -1.5], [0.0, 0.5], 3.5, lcl.scale(c35, 1.4), [0.1 * c35[1], -0.1 * c35[0]], 9.0},
		NewcomerCase{'from behind another solid, across a seen gap partway along', [
			disc([1.0, 0.0], 0.4), disc([0.7071, 0.7071], 0.255)], [1.8, -1.5], [0.0, 0.5], 3.0, [
			1.4142, 1.4142], [-0.3536, 0.3536], 5.5},
		NewcomerCase{'in view at the far edge of the same shadow, standing', [
			disc([1.0, 0.0], 0.4)], [1.8, -1.5], [0.0, 0.5], 3.0, [1.8, 0.95], [0.0, 0.0], 5.0},
		NewcomerCase{'in view at the far edge of the same shadow, crossing the course', [
			disc([1.0, 0.0], 0.4)], [1.8, -1.5], [0.0, 0.5], 3.0, [1.0, 0.95], [0.4, 0.0], 5.0},
	]
	for c in cases {
		mut t := Tracker{}
		mut last := i64(-1) // ms, when the detector last reported the person who hides
		mut b_seen := false
		for k in 0 .. 601 {
			t_ms := i64(20 * k)
			a := lcl.add(c.a, lcl.scale(c.a_vel, math.min(f64(t_ms) / 1000.0, c.a_stop)))
			b := lcl.add(c.b, lcl.scale(c.b_vel, math.max(f64(t_ms) / 1000.0 - c.b_from, 0.0)))
			raw := sighted(t_ms, [0.0, 0.0], [a, b], c.solids)
			people := t.percept(raw).scene.filter(it.kind == 'human')
			for e in people {
				if lcl.dist(e.pos, a) < 1e-9 {
					assert e.id == 'p1', '${c.name}: the person who hides is ${e.id} at ${t_ms} ms'
				}
				if lcl.dist(e.pos, b) < 1e-9 {
					assert e.id != 'p1', '${c.name}: the other person took p1 at ${t_ms} ms'
				}
			}
			if raw.scene.any(lcl.dist(it.pos, a) < 1e-9) {
				last = t_ms
			} else if last >= 0 && t_ms - last <= hide_ms {
				assert people.any(it.id == 'p1'), '${c.name}: p1 gone at ${t_ms} ms'
			}
			b_seen = b_seen || raw.scene.any(lcl.dist(it.pos, b) < 1e-9)
		}
		assert last >= 0 && b_seen, '${c.name}: someone never seen'
	}
}

// A sensed solid that a person steps in front of is forgotten after forget_ms, as before people
// could hide: it lies behind the person, whom the body meets first.
fn test_a_hidden_solid_goes_after_forget_ms() {
	pole := disc([4.0, 0.0], 0.2)
	mut t := Tracker{}
	mut gone := i64(-1) // ms, when the ring last saw the pole
	for k in 0 .. 201 {
		t_ms := i64(20 * k)
		front := [2.0, math.min(-1.0 + 0.02 * f64(k), 0.0)]
		solids :=
			t.percept(sighted(t_ms, [0.0, 0.0], [front], [pole])).scene.filter(it.kind == 'obstacle')
		if solids.len > 0 {
			gone = t_ms
		}
	}
	assert gone >= 0 && gone < 4000 - forget_ms, 'the pole held until ${gone} ms'
}

struct PathCase {
	name   string
	solids []Circle
	a      []f64
	b      []f64
	want   bool
}

// hid_path finds the way hidden within one shadow and none across ground the ring sees, between two
// shadows or past a shadow's end, but leaves out the last gate_slack before b, where the person
// shows.
fn test_hid_path() {
	pillar := disc([1.0, 0.0], 0.4)
	cases := [
		PathCase{'within one shadow', [pillar], [1.8, -0.3], [2.6, 0.3], true},
		PathCase{'across ground the ring sees between two shadows', [pillar, disc([2.0, 2.2], 0.5)], [
			1.8, 0.3], [2.6, 2.4], false},
		PathCase{'out of the shadow where a person stepping out is first seen', [pillar], [
			1.8, 0.0], [1.8, 0.5], true},
		PathCase{'out of the shadow 0.4 m before b', [pillar], [1.8, 0.0], [1.8, 0.9], false},
		PathCase{'shorter than the last stretch', [], [3.0, 0.0], [3.0, 0.15], true},
	]
	for c in cases {
		assert hid_path(sighted(0, [0.0, 0.0], [], c.solids), c.a, c.b, 0.3) == c.want, c.name
	}
}

struct TrackCase {
	name   string
	pos    []f64 // m, where the person was last seen, at 0 ms
	vel    []f64 // m/s
	t_ms   i64
	solids []Circle
	hidden bool
	at     []f64 // m, where the scene shows them, within 0.1 m
	lo     f64   // where the first hidden stretch begins and ends along the axis the person walks
	hi     f64
}

// hide holds a person where their core may be hidden though their rim shows, finds a hidden stretch
// as narrow as a thin pole's shadow, shows the hidden place nearest the body, and keeps the first
// hidden stretch of the course for the gate.
fn test_hide() {
	pillar := disc([3.0, 0.0], 0.8)
	edge := [5.0 * math.cos(13.0 * math.pi / 180.0), 5.0 * math.sin(13.0 * math.pi / 180.0)]
	cases := [
		TrackCase{'its core behind a pillar, its rim past it', edge, [0.0, 0.0], 500, [
			pillar], true, edge, edge[1], edge[1]},
		TrackCase{'in plain view', [5.0, 3.0], [0.0, 0.0], 500, [pillar], false, [5.0, 3.0], 0.0, 0.0},
		TrackCase{'walked on into the shadow', [4.5, -2.5], [0.0, 0.5], 5000, [pillar], true, [
			4.5, 0.0], -1.06, 0.0},
		TrackCase{'past a thin pole', [-3.0, 5.0], [0.6, 0.0], 10000, [
			disc([1.0, 2.0], 0.15)], true, [2.2, 5.0], 2.2, 2.8},
		TrackCase{'past two thin poles, the nearer second', [-4.0, 5.0], [0.8, 0.0], 10000, [
			disc([-1.26, 1.8], 0.15), disc([0.2, 2.0], 0.15)], true, [0.25, 5.0], -3.8, -3.2},
	]
	for c in cases {
		mut k := Track{
			kind:      'human'
			pos:       c.pos
			at:        c.pos
			r:         0.3
			vel:       c.vel
			sightings: 2
		}
		k.hide(sighted(c.t_ms, [0.0, 0.0], [], c.solids))
		assert k.hidden == c.hidden, c.name
		assert lcl.dist(k.at, c.at) <= 0.1, '${c.name}: shown at ${k.at}'
		if c.hidden {
			axis := if c.vel[0] == 0.0 { 1 } else { 0 }
			assert math.abs(k.lo[axis] - c.lo) <= 0.1 && math.abs(k.hi[axis] - c.hi) <= 0.1, '${c.name}: ${k.lo} to ${k.hi}'
		}
	}

	// A track the ring sees through again shows at its last place.
	mut k := Track{
		kind:      'human'
		pos:       [4.5, -2.5]
		at:        [4.5, -2.5]
		r:         0.3
		vel:       [0.0, 0.5]
		sightings: 2
	}
	k.hide(sighted(5000, [0.0, 0.0], [], [pillar]))
	assert k.hidden
	k.hide(sighted(5020, [0.0, 0.0], [], []))
	assert !k.hidden && k.at == [4.5, -2.5]
}

// ArcWant is what an arc case asks of a hidden track beside never lying farther from the body than
// the straight course's place.
enum ArcWant {
	on_the_arc  // within 3 cm of the walker's way, where the straight course strays 0.1 m or more
	not_farther // nothing more
	unchanged   // at the straight course's place
}

struct ArcCase {
	name   string
	from   []f64 // m, where the walker is at 0 s
	head   f64   // rad, the heading they start on, counterclockwise from east
	turn   f64   // rad/s, how fast they turn, counterclockwise
	flip_s f64   // s, from when they turn the other way at the same rate
	stop_s f64   // s, when they stop
	show_s f64   // s, when they come into the world, so the track's history starts there
	want   ArcWant
}

// walker is where the walker of c stands at t s.
fn (c ArcCase) walker(t f64) []f64 {
	p := arc_at(c.from, c.head, c.turn, math.min(t, math.min(c.flip_s, c.stop_s)))
	if t <= c.flip_s || c.stop_s <= c.flip_s {
		return p
	}
	return arc_at(p, c.head + c.turn * c.flip_s, -c.turn, math.min(t, c.stop_s) - c.flip_s)
}

// arc_at is where a walker stands t s after leaving p on heading h at 0.5 m/s, turning at w rad/s.
fn arc_at(p []f64, h f64, w f64, t f64) []f64 {
	if w == 0.0 {
		return [p[0] + 0.5 * t * math.cos(h), p[1] + 0.5 * t * math.sin(h)]
	}
	return [p[0] + 0.5 / w * (math.sin(h + w * t) - math.sin(h)),
		p[1] - 0.5 / w * (math.cos(h + w * t) - math.cos(h))]
}

// off is how far p lies from the way through the points of path.
fn off(p []f64, path [][]f64) f64 {
	mut d := lcl.dist(p, path[0])
	for j in 1 .. path.len {
		d = math.min(d, lcl.dist(p, nearest(p, path[j - 1], path[j])))
	}
	return d
}

// A person's track hidden behind a pillar shows on the arc that the turn they walked bends their
// course into, where that lies nearer the body: a walker who keeps turning toward the body shows
// on their way, where the straight course strays; one who reverses the turn while hidden, whose arc
// bends away, shows no farther than on the straight course; and one who walks straight, one who
// stops while hidden and one seen for less than turn_ms show where the straight course shows them.
// On every hidden tick the track lies no farther from the body than the straight course's place,
// which a copy of the track without its turn rate shows.
fn test_hide_on_an_arc() {
	pillar := disc([2.0, 0.0], 0.5)
	north := math.pi / 2.0
	cases := [
		ArcCase{'turns behind a pillar', [4.5, -2.5], north, 0.1, 99.0, 99.0, 0.0, .on_the_arc},
		ArcCase{'reverses the turn behind a pillar', [4.5, -2.0], 2.0 * math.pi / 3.0, -0.1, 2.7, 99.0, 0.0, .not_farther},
		ArcCase{'walks straight behind a pillar', [4.5, -2.5], 1.75, 0.0, 99.0, 99.0, 0.0, .unchanged},
		ArcCase{'stops behind a pillar', [4.5, -2.5], 1.75, 0.0, 99.0, 5.5, 0.0, .unchanged},
		ArcCase{'turns behind a pillar, seen for less than turn_ms', [4.5, -2.5], north, 0.1, 99.0, 99.0, 2.6, .unchanged},
	]
	for c in cases {
		mut t := Tracker{}
		mut path := [][]f64{} // m, where the walker went since the detector last reported them
		mut hidden := 0 // ticks the track was held hidden
		mut stray := 0.0 // m, how far the straight course's place strayed from that way
		for i in 0 .. 601 {
			t_ms := i64(20 * i)
			at := c.walker(f64(t_ms) / 1000.0)
			people := if f64(t_ms) / 1000.0 >= c.show_s { [at] } else { [][]f64{} }
			raw := sighted(t_ms, [0.0, 0.0], people, [pillar])
			t.percept(raw)
			if raw.scene.len == 1 {
				path = [at]
				continue
			}
			path << at
			held := t.tracks.filter(it.kind == 'human' && it.hidden)
			if path.len < 2 || held.len == 0 {
				continue
			}
			mut straight := Track{
				...held[0]
				turn: 0.0
			}
			straight.hide(raw)
			shown := held[0].at
			hidden++
			stray = math.max(stray, off(straight.at, path))
			assert lcl.norm(shown) <= lcl.norm(straight.at) + 1e-9, '${c.name}: ${shown} farther than ${straight.at} at ${t_ms} ms'
			match c.want {
				.on_the_arc {
					assert off(shown, path) <= 0.03, '${c.name}: ${shown} ${off(shown, path)} m off the way at ${t_ms} ms'
				}
				.not_farther {}
				.unchanged {
					assert lcl.dist(shown, straight.at) <= 1e-9, '${c.name}: ${shown} against ${straight.at} at ${t_ms} ms'
				}
			}
		}
		assert hidden >= 50, '${c.name}: held hidden for ${hidden} ticks'
		if c.want == .on_the_arc {
			assert stray >= 0.1, '${c.name}: the straight course strayed ${stray} m at most'
		}
	}
}

struct UnseenCase {
	name   string
	solids []Circle
	people [][]f64
	reach  f64
	lo     f64 // m, the least rim distance the place may have, or -1 for no place
	hi     f64 // m, the greatest
}

// unseen finds the place nearest the body where a slim person may stand while the ring sees into
// no part of them: behind a pillar, clear of it, and nearer than the place straight behind it, or
// behind a person; none on open floor, behind a pillar whose shadow starts past reach, or with no
// reach. Every place it finds lies in the ring's shadow and clear of every solid of the scene.
fn test_unseen() {
	pillar := disc([1.2, 0.0], 0.4)
	cases := [
		UnseenCase{'open floor', [], [], 2.0, -1.0, -1.0},
		UnseenCase{'behind a pillar within reach, nearer than straight behind it', [
			pillar,
		], [], 2.0, 1.4, 1.6},
		UnseenCase{'behind a pillar whose shadow starts past reach', [
			disc([3.0, 0.0], 0.8),
		], [], 2.0, -1.0, -1.0},
		UnseenCase{'no reach', [
			pillar,
		], [], 0.0, -1.0, -1.0},
		UnseenCase{'behind a person', [], [
			[1.0, 0.0],
		], 2.0, 0.7, 2.0},
	]
	o := [0.0, 0.0]
	for c in cases {
		raw := sighted(0, o, c.people, c.solids)
		mut scene := raw.scene.clone()
		for s in c.solids {
			scene << lcl.Entity{
				id:   's'
				kind: 'obstacle'
				pos:  s.pos
				r:    s.r
			}
		}
		got := unseen(raw, scene, c.reach, Room{})
		if c.lo < 0.0 {
			assert got.len == 0, c.name
			continue
		}
		assert got.len == 1, c.name
		u := got[0]
		rim := lcl.dist(o, u.pos) - u.r
		assert u.kind == 'human' && u.id == 'unseen' && u.r == slim, c.name
		assert rim >= c.lo && rim <= c.hi, '${c.name}: rim ${rim}'
		assert shadowed(raw, u.pos, u.r), '${c.name}: in view'
		assert c.solids.all(lcl.dist(u.pos, it.pos) >= it.r + slim), '${c.name}: inside a solid'
	}
}

// The tracker hands the place to every reader past it, the armor first, and finds it a tick at a
// time from the scan alone, with no person it ever saw.
fn test_a_tracker_reports_where_a_person_may_stand_unseen() {
	mut t := Tracker{
		reach: 2.0
	}
	p := t.percept(sighted(0, [0.0, 0.0], [], [disc([1.2, 0.0], 0.4)]))
	assert p.unseen.len == 1
	assert p.scan.len == 0
	mut far := Tracker{}
	assert far.percept(sighted(0, [0.0, 0.0], [], [disc([1.2, 0.0], 0.4)])).unseen.len == 0, 'a tracker with no reach'
}

// A Room holds no one in a shadow the ring saw empty until a person could have walked into it: a
// boat that rolls in front of the body hides a place within reach, which counts only once a person
// at spread could have come up the boat's shadow from the Room's edge, while a pillar there from the
// start hides one at once, since the ring never saw behind it.
fn test_a_room_holds_no_one_where_the_ring_saw_until_one_could_walk_in() {
	o := [0.0, 0.0]
	boat := disc([1.0, 0.0], 0.37)
	mut t := Tracker{
		reach: 2.0
		fence: [-5.0, -5.0, 5.0, 5.0]
	}
	assert t.percept(sighted(0, o, [][]f64{}, []Circle{})).unseen.len == 0, 'open floor'
	assert t.percept(sighted(20, o, [][]f64{}, [boat])).unseen.len == 0, 'the boat as it arrives'
	assert t.percept(sighted(1000, o, [][]f64{}, [boat])).unseen.len == 0, 'a second on'

	// From the Room's edge at x = 7 m to the place behind the boat at about 1.6 m, at spread.
	due := i64((7.0 - 1.6) / spread * 1000.0)
	late := t.percept(sighted(due + 500, o, [][]f64{}, [boat]))
	assert late.unseen.len == 1, 'once a person could have walked in'
	assert lcl.dist(o, late.unseen[0].pos) - slim < 2.0

	mut fresh := Tracker{
		reach: 2.0
		fence: [-5.0, -5.0, 5.0, 5.0]
	}
	assert fresh.percept(sighted(0, o, [][]f64{}, [disc([1.2, 0.0], 0.4)])).unseen.len == 1, 'a pillar from the start'
}

struct ThroughCase {
	name   string
	solids []Circle
	x      f64
	y      f64
	want   bool
}

// through sees a square on open floor within the ring's reach and the body's own place, and not
// behind or inside a pillar, beyond 10 m, or where the bearing is no number.
fn test_through() {
	pillar := disc([3.0, 0.0], 0.8)
	cases := [
		ThroughCase{'open floor', [], 4.0, 3.0, true},
		ThroughCase{'the body itself', [pillar], 0.1, 0.0, true},
		ThroughCase{'before a pillar', [pillar], 1.5, 0.0, true},
		ThroughCase{'inside a pillar', [pillar], 3.0, 0.0, false},
		ThroughCase{'behind a pillar', [pillar], 5.0, 0.0, false},
		ThroughCase{'beside a pillar', [pillar], 5.0, 3.0, true},
		ThroughCase{'beyond the ring', [], 12.0, 0.0, false},
	]
	for c in cases {
		raw := lcl.Percept{
			pose: [0.0, 0.0]
			scan: ring([0.0, 0.0], c.solids)
		}
		assert through(raw, c.x, c.y) == c.want, c.name
	}
	assert !through(lcl.Percept{
		pose:    [0.0, 0.0]
		heading: math.nan()
		scan:    ring([0.0, 0.0], [pillar])
	}, 5.0, 0.0), 'a heading that is no number'
}

// A Room with no squares, as a Tracker with no fence keeps, and a place beyond a Room's edge hold
// a person at any time.
fn test_open() {
	assert Room{}.open([0.0, 0.0], 0)
	m := new_room([-5.0, -5.0, 5.0, 5.0])
	assert m.open([0.0, 0.0], 0), 'every square at the start'
	assert m.open([9.0, 0.0], 0), 'beyond the edge'
}
