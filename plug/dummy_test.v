module plug

import os

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
	d := load_dummy(path)
	assert d.size() == 600 && d.ready()
}
