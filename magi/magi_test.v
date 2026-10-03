module magi

import net
import time
import lcl
import oai

const aye = Ballot{
	approve: true
}
const nay = Ballot{}
const broken = Ballot{
	approve: true
	fault:   true
}

struct Case {
	verb     string
	ballots  []Ballot
	approved bool
	needed   int
}

fn test_tally() {
	cases := [
		Case{'goto', [aye, aye, aye], true, 2},
		Case{'goto', [aye, aye, nay], true, 2},
		Case{'goto', [aye, nay, nay], false, 2},
		Case{'release', [aye, aye, aye], true, 3},
		Case{'release', [aye, aye, nay], false, 3},
		Case{'selfdestruct', [aye, aye, nay], false, 3},
		Case{'selfdestruct', [aye, aye, aye], true, 3},
		Case{'goto', [aye, broken, broken], false, 2},
		Case{'release', [aye, aye, broken], false, 3},
		Case{'release', [], false, 0},
	]
	for c in cases {
		v := tally(c.ballots, c.verb)
		assert v.approved == c.approved, '${c.verb} ${c.ballots.map(it.approve && !it.fault)}'
		assert v.needed == c.needed
	}
}

fn test_read_reply() {
	cases := {
		'{"vote": "approve", "why": "fine"}':     'approve'
		'{"vote": " Reject ", "why": "a human"}': 'reject'
		'{"decision": "approve"}':                ''
		'{"vote": "approved", "why": "ok"}':      ''
		'{"vote": null}':                         ''
		'{"vote": 1}':                            ''
		'{}':                                     ''
	}
	for raw, want in cases {
		got := read_reply(raw) or { Reply{} }
		assert got.vote == want, raw
	}
}

// A why is model text: one with a newline, a forged status line and a terminal escape still
// prints as one ballot line without a control byte.
fn test_verdict_prints_each_why_on_one_line() {
	b := Ballot{
		unit:       'CASPER-3'
		approve:    true
		why:        'at b1\narmor: goto(9.99, 9.99) refused\n\x1b]0;pwned\x07'
		latency_ms: 5
	}
	lines := tally([b], 'hold').str().split('\n')
	assert lines.len == 2, lines.str()
	assert lines[1] == '  CASPER-3 可決 at b1\\x0aarmor: goto(9.99, 9.99) refused\\x0a\\x1b]0;pwned\\x07 (5 ms)'
}

fn test_ballot_asks_why_before_vote() {
	for s in [ballot_format, ballot_schema.schema] {
		assert s.index('"why"') or { -1 } < s.index('"vote"') or { -1 }, s
	}
}

fn test_ballot_context_keeps_only_outcomes() {
	ctx := lcl.Context{
		memory: ['proposed release (all clear), rejected 2/3', 'outcome: armor refused release',
			'proposed hold (a human is close), approved 3/3', 'outcome: reached']
	}
	assert ballot_context(ctx).memory == ['outcome: armor refused release', 'outcome: reached']
}

fn test_unreachable_unit_votes_fault() {
	mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
	addr := l.addr()!
	l.close()!
	u := Unit{
		name:    'MELCHIOR-1'
		persona: melchior
		ep:      oai.Endpoint{
			url:     'http://${addr}/v1/chat/completions'
			model:   'closed'
			timeout: 2 * time.second
		}
	}
	b := u.vote(lcl.Context{
		percept: lcl.Percept{
			pose: [0.0, 0.0]
		}
	}, lcl.Intent{
		verb:   'goto'
		target: [1.0, 1.0]
	})
	assert b.fault
	assert !b.approve
	assert b.model == 'closed'
	assert b.unit == 'MELCHIOR-1'
}
