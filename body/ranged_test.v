module body

import math
import lcl

struct RayCase {
	name string
	o    []f64
	d    []f64
	c    []f64
	r    f64
	want ?f64
}

fn test_ray() {
	cases := [
		RayCase{'a circle straight ahead', [0.0, 0.0], [1.0, 0.0], [3.0, 0.0], 0.5, 2.5},
		RayCase{'a circle off to the side', [0.0, 0.0], [0.0, 1.0], [0.3, 2.0], 0.5, 2.0 - math.sqrt(0.16)},
		RayCase{'a circle grazed', [0.0, 0.0], [1.0, 0.0], [2.0, 0.5], 0.5, 2.0},
		RayCase{'a circle missed', [0.0, 0.0], [1.0, 0.0], [2.0, 0.6], 0.5, none},
		RayCase{'a circle behind', [0.0, 0.0], [1.0, 0.0], [-3.0, 0.0], 0.5, none},
		RayCase{'from inside a circle', [0.0, 0.0], [1.0, 0.0], [0.1, 0.0], 0.5, 0.0},
	]
	for c in cases {
		got := ray(c.o, c.d, c.c, c.r)
		if want := c.want {
			t := got or { -1.0 }
			assert math.abs(t - want) < 1e-12, c.name
		} else {
			assert got == none, c.name
		}
	}
}

// Each beam ends on the nearest obstacle or human it meets and reads lcl.scan_range past them; a
// beacon, a ditch and a landing zone reflect nothing.
fn test_scan_ends_on_the_nearest_solid_or_person() {
	scene := [
		lcl.Entity{
			id:   'b1'
			kind: 'beacon'
			pos:  [2.0, 0.0]
			r:    0.3
		},
		lcl.Entity{
			id:   'd1'
			kind: 'ditch'
			pos:  [0.0, 2.0]
			r:    0.5
		},
		lcl.Entity{
			id:   'o1'
			kind: 'obstacle'
			pos:  [4.0, 0.0]
			r:    0.5
		},
		lcl.Entity{
			id:   'h1'
			kind: 'human'
			pos:  [6.0, 0.0]
			r:    0.3
		},
		lcl.Entity{
			id:   'h2'
			kind: 'human'
			pos:  [-2.0, 0.0]
			r:    0.3
		},
	]
	ranges, ends := scan(scene, [0.0, 0.0], 0.0)
	assert ranges.len == beams && ends.len == beams
	assert math.abs(ranges[0] - 3.5) < 1e-12 && ends[0] == 2
	assert math.abs(ranges[180] - 1.7) < 1e-12 && ends[180] == 4
	assert ranges[90] == lcl.scan_range && ends[90] == -1
	assert 3 !in ends
}

// The ring turns with the heading: its first beam points along it.
fn test_scan_counts_from_the_heading() {
	scene := [
		lcl.Entity{
			id:   'o1'
			kind: 'obstacle'
			pos:  [0.0, 3.0]
			r:    0.5
		},
	]
	ranges, _ := scan(scene, [0.0, 0.0], math.pi / 2.0)
	assert math.abs(ranges[0] - 2.5) < 1e-9
}

// Ranged reports the map as it is, a person in view without id or velocity, and no obstacle and
// no person hidden behind one, while truth keeps the whole scene.
fn test_ranged_reports_the_map_and_the_people_in_view() {
	w := World{
		start:     [0.0, 0.0]
		beacons:   [Spot{'b1', [3.0, 3.0], 0.3}]
		obstacles: [Spot{'o1', [2.0, 0.0], 0.6}]
		ditches:   [Spot{'d1', [-3.0, 3.0], 0.5}]
		humans:    [
			Human{
				id:       'seen'
				r:        0.3
				behavior: .stand
				reaction: .through
				pos:      [0.0, -2.0]
			},
			Human{
				id:       'hidden'
				r:        0.3
				behavior: .stand
				reaction: .through
				pos:      [4.0, 0.0]
			},
		]
	}
	mut r := ranged(new_sim(w, .holonomic))
	p := r.sense()
	assert p.scene.map(it.kind) == ['beacon', 'human', 'ditch']
	assert p.scene.map(it.id) == ['b1', '', 'd1']
	assert p.scene[1].pos == [0.0, -2.0] && p.scene[1].vel.len == 0
	assert p.scan.len == beams
	assert math.abs(p.scan[0] - 1.4) < 1e-9
	assert r.truth().map(it.id) == ['b1', 'o1', 'seen', 'hidden', 'd1']
}

// Under ground truth the body's percept carries no scan, so it encodes as before.
fn test_a_plain_body_scans_nothing() {
	mut s := new_sim(default_world(), .holonomic)
	p := s.sense()
	assert p.scan.len == 0
	assert s.truth() == p.scene
}
