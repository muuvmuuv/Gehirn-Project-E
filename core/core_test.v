module core

import os

struct Ballot {
	t_ms int
	kind string
	vote string
	why  string
}

fn test_journal_tail_skips_structured_lines() {
	path := os.join_path(os.temp_dir(), 'gehirn_core_test_${os.getpid()}.jsonl')
	defer {
		os.rm(path) or {}
	}
	os.write_lines(path, [
		'{"t_ms": 1, "text": "outcome: reached"}',
		'{"t_ms": 2, "kind": "ballot", "vote": "reject", "why": "a human within 2 m"}',
		'{"t_ms": 3, "text": ""}',
		'not json',
		'{"t_ms": 4, "text": "outcome: contact"}',
		'{"t_ms": 5, "text": "outcome: released on target"}',
		'{"t_ms": 6, "kind": "ballot", "text": "never shown"}',
	])!
	mut m := open_memory(path, 2)
	assert m.recent(12) == ['outcome: contact', 'outcome: released on target']
	m.log(Ballot{ t_ms: 7, kind: 'ballot', vote: 'fault', why: 'no reply within 10000 ms' })
	m.add('proposed hold (why), approved 3/3')
	assert m.recent(12) == ['outcome: released on target', 'proposed hold (why), approved 3/3']
	lines := os.read_lines(path)!
	assert lines[7] == '{"t_ms":7,"kind":"ballot","vote":"fault","why":"no reply within 10000 ms"}'
	assert lines[8].starts_with('{"t_ms":')
	assert lines[8].all_after(',') == '"text":"proposed hold (why), approved 3/3"}'
	assert open_memory(path, 256).recent(12).len == 4
}
