module core

import x.json2
import lcl

fn test_read_proposal() {
	// Each reply maps to the label of the intent it becomes, or to '' for an unreadable one.
	cases := {
		'{"verb": "goto", "target": [3, 2], "why": "b1"}':        'goto(3.00, 2.00)'
		'{"check": "x", "verb": "goto", "target": [3, 2]}':       'goto(3.00, 2.00)'
		'{"verb": " GOTO ", "target": [3.0, 2.0], "why": "b1"}':  'goto(3.00, 2.00)'
		'{"verb": "hold", "target": [], "why": "wait"}':          'hold'
		'{"verb": "hold", "why": "wait"}':                        'hold'
		'{"verb": "release", "target": [3, 2], "why": "at b1"}':  'release'
		'{"verb": "self_destruct", "target": [], "why": "done"}': 'self_destruct'
		'{"verb": "goto", "why": "somewhere"}':                   ''
		'{"verb": "goto", "target": [], "why": "somewhere"}':     ''
		'{"verb": "goto", "target": null, "why": "somewhere"}':   ''
		'{"verb": "goto", "target": [1, 2, 3], "why": "3d"}':     ''
		'{"verb": "goto", "target": [1e999, 2], "why": "far"}':   ''
		'{"verb": "goto", "target": [1, "a"], "why": "odd"}':     ''
		'{"verb": "goto", "target": "3, 2", "why": "text"}':      ''
		'{"target": [3, 2], "why": "no verb"}':                   ''
		'not json':                                               ''
	}
	for raw, want in cases {
		got := read_proposal(raw, 'llm:test') or {
			assert want == '', '${raw}: ${err}'
			assert err.msg() == 'unreadable proposal'
			continue
		}
		assert got.label() == want, raw
		assert got.origin == 'llm:test'
	}
}

struct SchemaDoc {
	required []string
}

fn test_proposal_schema_requires_check_first_and_target_before_why() {
	s := proposal_schema.schema
	doc := json2.decode[SchemaDoc](s)!
	assert doc.required == ['check', 'verb', 'target', 'why']
	assert s.index('"check"') or { -1 } < s.index('"verb"') or { -1 }
	assert s.index('"target"') or { -1 } < s.index('"why"') or { -1 }
	assert s.contains('"enum":${json2.encode(lcl.known_verbs)}')
}
