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
