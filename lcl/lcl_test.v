module lcl

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

// describe gives every entity of the scene one line in the scene's layout, a moving obstacle as an
// obstacle and a ditch as any kind, and leaves out every velocity.
fn test_describe() {
	p := Percept{
		pose:  [0.0, 0.0]
		scene: [
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
	}
	assert p.describe() == 'self at (0.00, 0.00), carrying payload: false, in contact: false
beacon b1 at (3.00, 4.00), radius 0.30, distance 5.00
obstacle boat at (0.00, -1.00), radius 0.35, distance 1.00
ditch trench at (-1.60, 1.20), radius 0.50, distance 2.00'
}
