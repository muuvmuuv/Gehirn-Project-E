module plug

import math
import os
import lcl

fn test_complete() {
	line := '{"t_ms":1,"seat":"pilot","pose":[0.5,-0.25],"target":[3,2]}'
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
	}
	for s, want in cases {
		assert complete(s) == want, s
	}
}

// A recorder whose last line a kill cut right after a number in an array still loads, without
// that line.
fn test_load_dummy_skips_a_cut_line() {
	path := os.join_path(os.vtmp_dir(), 'gehirn_cut_recorder_${os.getpid()}.jsonl')
	tick := '{"t_ms":1,"seat":"pilot","pose":[0,0],"target":[3,2],"u_seat":[0.6,0]}\n'
	os.write_file(path, tick.repeat(600) + tick[..34])!
	defer {
		os.rm(path) or {}
	}
	d := load_dummy(path, os.join_path(os.vtmp_dir(), 'gehirn_no_such_weights.json'))!
	assert d.size() == 600 && d.ready()
}

// scene is body/body.v Sim.scene with the human held still, as tools/test_export_dummy.py SCENE.
const scene = [
	lcl.Entity{
		id:   'b1'
		kind: 'beacon'
		pos:  [3.0, 2.0]
		r:    0.3
	},
	lcl.Entity{
		id:   'o1'
		kind: 'obstacle'
		pos:  [0.0, -0.3]
		r:    0.8
	},
	lcl.Entity{
		id:   'h1'
		kind: 'human'
		pos:  [1.5, 0.0]
		r:    0.3
	},
]

// shared_features is what tools/test_export_dummy.py SHARED expects from tools/export_dummy.py
// features for the same percept, so the training set and the dummy plug see alike.
const shared_features = [2.3323807579381204, -0.7383642874308872, -0.22239888175629136,
	0.7711310417560499, 0.014280075529516156, -0.7854041541233885, 0.7855339622647798]

fn close(a []f64, b []f64) bool {
	return a.len == b.len && a.len > 0
		&& []bool{len: a.len, init: math.abs(a[index] - b[index]) < 1e-12}.all(it)
}

fn seen(pose []f64, target []f64, entities []lcl.Entity) []f64 {
	return observe(lcl.Percept{ pose: pose, scene: entities }, target) or { []f64{} }
}

fn test_observe() {
	assert close(seen([1.0, 0.8], [3.0, 2.0], scene), shared_features)

	// Inside a rim the closeness stops at 1, past sight the distance stops at sight.
	f := seen([0.5, -0.9], [3.0, 2.0], scene)
	assert f.len == inputs && f[0] == sight && f[3] == 1.0, '${f}'

	// Out of sight, or with nobody there, a kind reads as zeros.
	assert seen([-4.0, -4.0], [3.0, 2.0], scene)[4..] == [0.0, 0.0, 0.0]
	assert seen([1.0, 0.8], [3.0, 2.0], scene[..2])[4..] == [0.0, 0.0, 0.0]

	// Without a goal frame the policy sees nothing.
	assert seen([3.0, 2.0], [3.0, 2.0], scene) == []
	assert seen([1.0, 0.8], [], scene) == []
}

// shared_policy is tools/test_train_dummy.py SHARED_NET, whose SHARED_Y tools/train_dummy.py
// predict computes for SHARED_X, so the trainer and the dummy plug compute alike.
const shared_policy = '{"v": 1, "w1": [[0.5, -0.25, 0.0, 1.0, 0.0, 0.0, -0.5], [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]], "b1": [0.1, -0.2], "w2": [[1.0, -1.0], [0.5, 0.25]], "b2": [0.3, -0.1]}'

fn weights_file(name string, text string) string {
	path := os.join_path(os.vtmp_dir(), 'gehirn_${name}_${os.getpid()}.json')
	os.write_file(path, text) or { panic(err) }
	return path
}

fn test_policy_act() {
	path := weights_file('shared_policy', shared_policy)
	defer {
		os.rm(path) or {}
	}
	p := load_policy(path)!
	assert close(p.act([2.0, -0.5, 0.25, 0.75, 0.0, -1.0, 0.5]), [1.2134674883172833,
		0.3754798388849572])
}

struct PolicyCase {
	name string
	text string
	want string // the error, or empty when the weights load
}

fn test_load_policy() {
	row7 := '[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]'
	cases := [
		PolicyCase{'the weights tools/train_dummy.py writes', shared_policy, ''},
		PolicyCase{'an extra field', shared_policy.replace('"v": 1', '"v": 1, "mse": 0.01'), ''},
		PolicyCase{'no JSON', 'w1 = 1', 'plug: weights are no policy in JSON'},
		PolicyCase{'a cut file', shared_policy[..40], 'plug: weights are no policy in JSON'},
		PolicyCase{'a file cut right after a number', shared_policy.all_before(', 0.0, 0.0, -0.5]'), 'plug: weights are no policy in JSON'},
		PolicyCase{'another version', shared_policy.replace('"v": 1', '"v": 2'), 'plug: weights of version 2, not 1'},
		PolicyCase{'no version', shared_policy.replace('"v": 1, ', ''), 'plug: weights of version 0, not 1'},
		PolicyCase{'no units', '{"v": 1, "w1": [], "b1": [], "w2": [[], []], "b2": [0, 0]}', 'plug: weights with 0 units; accepted 1 to 256'},
		PolicyCase{'too many units', '{"v": 1, "b1": [${[]string{len: 257, init: '0'}.join(', ')}]}', 'plug: weights with 257 units; accepted 1 to 256'},
		PolicyCase{'a row one input short', shared_policy.replace(row7, '[0.1, 0.2]'), 'plug: weights of another shape than 7 inputs, 2 units and 2 outputs'},
		PolicyCase{'a unit without its row', shared_policy.replace(', ${row7}]', ']'), 'plug: weights of another shape than 7 inputs, 2 units and 2 outputs'},
		PolicyCase{'one output', shared_policy.replace('"w2": [[1.0, -1.0], [0.5, 0.25]]',
			'"w2": [[1.0, -1.0]]'), 'plug: weights of another shape than 7 inputs, 2 units and 2 outputs'},
		PolicyCase{'an output bias too many', shared_policy.replace('[0.3, -0.1]',
			'[0.3, -0.1, 0.0]'), 'plug: weights of another shape than 7 inputs, 2 units and 2 outputs'},
		PolicyCase{'an infinite weight', shared_policy.replace('0.25]', '1e999]'), 'plug: weights hold a number that is not finite or beyond 1e6'},
		PolicyCase{'an infinite bias', shared_policy.replace('[0.1, -0.2]', '[-1e999, -0.2]'), 'plug: weights hold a number that is not finite or beyond 1e6'},
		PolicyCase{'a weight at the bound', shared_policy.replace('0.25]', '-1e6]'), ''},
		PolicyCase{'a weight past the bound', shared_policy.replace('0.25]', '-1.000001e6]'), 'plug: weights hold a number that is not finite or beyond 1e6'},
		PolicyCase{'a finite output bias whose norm overflows', shared_policy.replace('[0.3, -0.1]',
			'[1e200, -0.1]'), 'plug: weights hold a number that is not finite or beyond 1e6'},
	]
	for c in cases {
		path := weights_file('policy', c.text)
		got := if _ := load_policy(path) { '' } else { err.msg() }
		os.rm(path) or {}
		assert got == c.want, c.name
	}
	missing := os.join_path(os.vtmp_dir(), 'gehirn_no_such_weights.json')
	got := if _ := load_policy(missing) { '' } else { err.msg() }
	assert got == 'plug: cannot read the weights'
}

// Without a weights file the dummy plug clones the recorder as before, with one it flies the
// policy and never reads the recorder, and with a broken one it refuses to load at all.
fn test_load_dummy() {
	recorder := weights_file('recorder',
		'{"t_ms":1,"seat":"pilot","pose":[0,0],"target":[3,2],"u_seat":[0.6,0]}\n'.repeat(600))
	good := weights_file('good', shared_policy)
	bad := weights_file('bad', shared_policy.replace('"v": 1', '"v": 2'))
	defer {
		for path in [recorder, good, bad] {
			os.rm(path) or {}
		}
	}
	missing := os.join_path(os.vtmp_dir(), 'gehirn_no_such_weights.json')
	knn := load_dummy(recorder, missing)!
	assert !knn.trained() && knn.ready() && knn.size() == 600
	policy := load_dummy(recorder, good)!
	assert policy.trained() && policy.ready() && policy.size() == 0
	if _ := load_dummy(recorder, bad) {
		assert false, 'a dummy plug loaded weights of version 2'
	} else {
		assert err.msg() == 'plug: weights of version 2, not 1'
	}

	// The policy acts in the goal's frame, only toward a goal and short of it.
	at := lcl.Percept{
		pose:  [1.0, 0.8]
		scene: scene
	}
	y := policy.policy.act(shared_features)
	g := [2.0 / math.sqrt(5.44), 1.2 / math.sqrt(5.44)]
	assert close(policy.act(at, [3.0, 2.0]), [y[0] * g[0] - y[1] * g[1], y[0] * g[1] + y[1] * g[0]])
	assert policy.act(at, []) == [0.0, 0.0]
	assert policy.act(at, [1.2, 0.9]) == [0.0, 0.0]
}
