module body

import math
import lcl

// beams is how many beams the ring of Ranged casts, one a degree (ADR-0011).
const beams = 360

// Ranged is a Body that knows its scene through a range ring and a person detector instead of
// ground truth, the body main.v builds around Sim or the MuJoCo base under SENSING=range
// (ADR-0011). Its percept holds the world's map, its beacons, ditches, landing zones and craters,
// then the people the detector reports, at their true positions with no id and no velocity, and
// the ring's scan; sensing.Tracker turns that into the scene the stack reads. truth stays the
// wrapped body's ground truth, for the recorder alone.
pub struct Ranged {
mut:
	inner Body
}

// ranged wraps b, so that its percept carries a scan and the detector's people in place of its
// obstacles and humans.
pub fn ranged(b Body) &Ranged {
	return &Ranged{
		inner: b
	}
}

// dof is the wrapped body's.
pub fn (r &Ranged) dof() int {
	return r.inner.dof()
}

// drive is the wrapped body's.
pub fn (r &Ranged) drive() Drive {
	return r.inner.drive()
}

// stopping is the wrapped body's.
pub fn (r &Ranged) stopping(speed f64) f64 {
	return r.inner.stopping(speed)
}

// truth is the wrapped body's ground truth.
pub fn (r &Ranged) truth() []lcl.Entity {
	return r.inner.truth()
}

// sense senses the wrapped body and swaps its scene for what the ring and the detector give: the
// map's entries as they are, each human that at least one beam ends on, so a person hidden behind
// a solid or beyond lcl.scan_range goes unreported, and the scan.
pub fn (mut r Ranged) sense() lcl.Percept {
	p := r.inner.sense()
	ranges, ends := scan(p.scene, p.pose, p.heading)
	mut scene := []lcl.Entity{cap: p.scene.len}
	for j, e in p.scene {
		match e.kind {
			'obstacle' {}
			'human' {
				if j in ends {
					scene << lcl.Entity{
						kind: 'human'
						pos:  e.pos.clone()
						r:    e.r
					}
				}
			}
			else {
				scene << e
			}
		}
	}
	return lcl.Percept{
		...p
		scene: scene
		scan:  ranges
	}
}

// actuate is the wrapped body's.
pub fn (mut r Ranged) actuate(u []f64) ! {
	r.inner.actuate(u)!
}

// effect is the wrapped body's.
pub fn (mut r Ranged) effect(verb string) ! {
	r.inner.effect(verb)!
}

// halt is the wrapped body's.
pub fn (mut r Ranged) halt() {
	r.inner.halt()
}

// scan casts the ring from pose, its first beam along heading and each next one a degree
// counterclockwise, against every obstacle and human of scene, and returns each beam's range,
// lcl.scan_range where it meets nothing closer, with the index in scene of what each beam ends on,
// -1 for none. A beacon is a mark on the floor and ditches, landing zones and craters are holes or
// air, so they reflect nothing. sensing hits places each beam the same way.
fn scan(scene []lcl.Entity, pose []f64, heading f64) ([]f64, []int) {
	mut ranges := []f64{len: beams, init: lcl.scan_range}
	mut ends := []int{len: beams, init: -1}
	if pose.len != 2 {
		return ranges, ends
	}
	for i in 0 .. beams {
		a := heading + f64(i) * 2.0 * math.pi / f64(beams)
		d := [math.cos(a), math.sin(a)]
		for j, e in scene {
			if e.kind !in ['obstacle', 'human'] || e.pos.len != 2 {
				continue
			}
			t := ray(pose, d, e.pos, e.r) or { continue }
			if t < ranges[i] {
				ranges[i] = t
				ends[i] = j
			}
		}
	}
	return ranges, ends
}

// ray is how far from o along the unit direction d a beam meets the rim of the circle at c of
// radius r: 0 when o lies inside the circle, as when a walker walks through the body, and none when
// the beam misses it or the circle lies behind o.
fn ray(o []f64, d []f64, c []f64, r f64) ?f64 {
	f := lcl.sub(o, c)
	inside := lcl.dot(f, f) - r * r
	if inside <= 0.0 {
		return 0.0
	}
	b := lcl.dot(f, d)
	disc := b * b - inside
	if disc < 0.0 || b > 0.0 {
		return none
	}
	return -b - math.sqrt(disc)
}
