module main

import lcl

fn test_take_view() {
	mut s := State{}
	for i in 0 .. 8 {
		s.take_view(lcl.FieldView{
			umbilical: 'connected'
			outcomes:  [lcl.Outcome{
				kind: 'reached ${i}'
			}, lcl.Outcome{
				kind: 'armor refused release ${i}'
			}]
		}, 1000 + i)
	}
	assert s.view_at == 1007
	assert s.outcomes == ['reached 7', 'reached 6', 'reached 5', 'reached 4', 'reached 3',
		'reached 2']
	assert s.refusals[0] == 'armor refused release 7' && s.refusals.len == keep
}

fn test_take_event() {
	mut s := State{}
	verdict := lcl.HqEvent{
		proposal: lcl.Intent{
			verb: 'release'
		}
		yes:      2
		needed:   3
		votes:    [lcl.Vote{}, lcl.Vote{}, lcl.Vote{}]
	}
	s.take_event(verdict, 5000)
	assert s.verdict == verdict && s.verdict_at == 5000
	assert s.proposals == ['release 否決 2/3, need 3']

	// A fault leaves the last verdict standing.
	s.take_event(lcl.HqEvent{
		fault: 'qwen3:8b: HTTP 429'
	}, 6000)
	assert s.fault == 'qwen3:8b: HTTP 429' && s.fault_at == 6000
	assert s.verdict_at == 5000 && s.proposals.len == 1
}

struct LeftCase {
	name      string
	umbilical string
	internal  i64
	view_at   i64
	now       i64
	want      string
}

fn test_left_ms() {
	cases := [
		LeftCase{'connected shows the whole budget', 'connected', 300000, 1000, 9000, '5:00'},
		LeftCase{'internal counts down between views', 'internal', 300000, 1000, 2500, '4:59'},
		LeftCase{'internal counts down a minute later', 'internal', 120000, 1000, 61000, '1:00'},
		LeftCase{'the last moment of power still shows', 'internal', 1000, 1000, 1999, '0:01'},
		LeftCase{'internal never goes below zero', 'internal', 1000, 1000, 9000, '0:00'},
		LeftCase{'depleted shows nothing left', 'depleted', 0, 1000, 9000, '0:00'},
	]
	for c in cases {
		s := State{
			view:    lcl.FieldView{
				umbilical:   c.umbilical
				internal_ms: c.internal
			}
			view_at: c.view_at
		}
		assert clock(s.left_ms(c.now)) == c.want, c.name
	}
}

fn test_heard() {
	assert heard(0, 5000) == 'never heard'
	assert heard(4000, 5000) == 'live'
	assert heard(3999, 5000) == 'silent 1 s'
	assert heard(1000, 13500) == 'silent 12 s'
}

fn test_mark() {
	assert mark('approve') == '可決'
	assert mark('reject') == '否決'
	assert mark('fault') == '故障'
	assert mark('') == '故障'
}

fn test_wrap() {
	for text, want in {
		'harm clear: highest goes_to_person 0.05 < 0.60, reversible': [
			'harm clear: highest',
			'goes_to_person 0.05',
			'< 0.60, reversible',
		]
		'':                                                           []string{}
		'nothing':                                                    ['nothing']
		'averyveryveryveryverylongword':                              [
			'averyveryveryveryver',
			'ylongword',
		]
	} {
		assert wrap(text, 20) == want, text
	}
}
