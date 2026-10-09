module lcl

import math

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

fn test_complete() {
	line := '{"t_ms":1,"seat":"pilot","pose":[0.5,-0.25],"target":[3,2]}'
	deep := '['.repeat(max_depth) + ']'.repeat(max_depth)
	cases := {
		line:                                                true
		line + ' \n':                                        true
		'[[1, 2], [3]]':                                     true
		'{"why": "a ] or a } in a string", "u": [1]}':       true
		'{"why": "an escaped \\" and a ] after it"}':        true
		line[..36]:                                          false // what json2 never returns from
		line[..37]:                                          false
		line[..line.len - 1]:                                false
		'{"t_ms":1,"pose":[0.5{"t_ms":2,"pose":[1,2]}':      false // a cut line and the next one
		line + line:                                         false
		'{"why": "a } in a string never closes the object"': false
		']':                                                 false
		'':                                                  false
		deep:                                                true
		'[' + deep + ']':                                    false // what could overflow json2's stack
	}
	for s, want in cases {
		assert complete(s) == want, s
	}
}

struct DescribeCase {
	name string
	p    Percept
	want string
}

// describe gives every entity of the scene one line in the scene's layout, a moving obstacle as an
// obstacle and a ditch as any kind, and leaves out every velocity; a scene without a human gets
// no_human after them, so no model reads a missing human line as an unknown distance, and a scene
// with one gets no such line, so its text stays as it was; a patch of ground gets a line last with
// the share of its speed the body keeps there.
fn test_describe() {
	terrain := [
		Entity{
			id:   'b1'
			kind: 'beacon'
			pos:  [3.0, 4.0]
			r:    0.3
		},
		Entity{
			id:   'boat'
			kind: 'obstacle'
			pos:  [0.0, -1.0]
			r:    0.35
			vel:  [0.4, 0.0]
		},
		Entity{
			id:   'trench'
			kind: 'ditch'
			pos:  [-1.6, 1.2]
			r:    0.5
		},
	]
	mut peopled := terrain.clone()
	peopled << Entity{
		id:   'h1'
		kind: 'human'
		pos:  [0.0, 3.0]
		r:    0.3
		vel:  [0.0, 0.5]
	}
	lake := [
		Entity{
			id:     'lake'
			kind:   'ground'
			pos:    [1.8, 0.8]
			r:      1.4
			factor: 0.5
		},
	]
	self := 'self at (0.00, 0.00), carrying payload: false, in contact: false'
	lines := 'beacon b1 at (3.00, 4.00), radius 0.30, distance 5.00
obstacle boat at (0.00, -1.00), radius 0.35, distance 1.00
ditch trench at (-1.60, 1.20), radius 0.50, distance 2.00'
	human := 'human h1 at (0.00, 3.00), radius 0.30, distance 3.00'
	ground := 'ground lake at (1.80, 0.80), radius 1.40, slows the body to 50%'
	cases := [
		DescribeCase{'no human, with ground', Percept{
			pose:   [0.0, 0.0]
			scene:  terrain
			ground: lake
		}, '${self}\n${lines}\nno human in sight\n${ground}'},
		DescribeCase{'no human, no ground', Percept{
			pose:  [0.0, 0.0]
			scene: terrain
		}, '${self}\n${lines}\nno human in sight'},
		DescribeCase{'the body alone', Percept{
			pose: [0.0, 0.0]
		}, '${self}\nno human in sight'},
		DescribeCase{'a walking human, with ground', Percept{
			pose:   [0.0, 0.0]
			scene:  peopled
			ground: lake
		}, '${self}\n${lines}\n${human}\n${ground}'},
		DescribeCase{'a walking human, no ground', Percept{
			pose:  [0.0, 0.0]
			scene: peopled
		}, '${self}\n${lines}\n${human}'},
	]
	for c in cases {
		assert c.p.describe() == c.want, c.name
	}
}
