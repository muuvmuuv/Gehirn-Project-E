module sensing

import math
import lcl

// ring is the scan a ring of 360 beams from pose along heading 0 reads off the circles of solids,
// as body/ranged.v scan casts it.
fn ring(pose []f64, solids []Circle) []f64 {
	mut out := []f64{len: 360, init: lcl.scan_range}
	for i in 0 .. 360 {
		a := f64(i) * 2.0 * math.pi / 360.0
		d := [math.cos(a), math.sin(a)]
		for c in solids {
			f := lcl.sub(pose, c.pos)
			inside := lcl.dot(f, f) - c.r * c.r
			b := lcl.dot(f, d)
			disc := b * b - inside
			if inside > 0.0 && disc >= 0.0 && b <= 0.0 {
				out[i] = math.min(out[i], -b - math.sqrt(disc))
			}
		}
	}
	return out
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
	p = t.percept(reading(1980 + forget_ms, [0.0, -3.0], [person([2.0, -0.5])], []))
	ids := p.scene.map(it.id)
	assert ids.len == 2 && 'p1' in ids && 'p2' in ids
	assert p.scene.filter(it.id == 'p1')[0].pos == last
	p = t.percept(reading(2000 + forget_ms, [0.0, -3.0], [person([2.0, -0.5])], []))
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
