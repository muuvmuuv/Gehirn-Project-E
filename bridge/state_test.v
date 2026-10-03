module main

import lcl

fn test_take_view() {
	mut s := State{}
	for i in 0 .. 8 {
		s.take_view(lcl.FieldView{
			percept:   lcl.Percept{
				pose:  [f64(i), -1.0]
				scene: [
					lcl.Entity{
						kind: 'human'
						pos:  [2.0, 3.0]
						r:    0.3
					},
				]
			}
			sync:      0.1 * i
			umbilical: 'connected'
			outcomes:  [lcl.Outcome{
				kind: 'reached ${i}'
				good: true
			}, lcl.Outcome{
				kind: 'armor refused release ${i}'
			}]
		}, 1000 + i)
	}
	assert s.view_at == 1007 && s.first_at == 1000
	assert s.outcomes.map(it.text) == ['reached 7', 'reached 6', 'reached 5', 'reached 4',
		'reached 3', 'reached 2']
	assert s.outcomes.all(it.good)
	assert s.refusals[0] == Entry{1007, 'release 7', false} && s.refusals.len == keep
	assert s.samples.len == 8 && s.samples[7].sync == 0.1 * 7
	assert s.trail.len == 8 && s.trail[7] == [7.0, -1.0]
	assert s.span == [0.0, -1.0, 7.0, 3.3]
}

fn test_tail_keeps_the_newest_history() {
	mut list := []int{}
	for i in 0 .. history + 5 {
		list = tail(list, i)
	}
	assert list.len == history && list[0] == 5 && list.last() == history + 4
}

struct CutCase {
	name   string
	states []string // umbilical per view, arriving at 1000, 2000 and on
	cut_at i64
	now    i64
	up     bool // the EMERGENCY overlay
}

fn test_emergency() {
	cases := [
		CutCase{'connected never cuts', ['connected', 'connected'], 0, 2500, false},
		CutCase{'the cut raises it', ['connected', 'internal'], 2000, 2500, true},
		CutCase{'it lasts emergency_ms', ['connected', 'internal'], 2000, 2000 + emergency_ms, false},
		CutCase{'internal views after the cut keep the cut time', ['connected', 'internal',
			'internal'], 2000, 3000, true},
		CutCase{'a reconnect drops it', ['connected', 'internal', 'connected'], 2000, 3100, false},
		CutCase{'a second cut raises it again', ['internal', 'connected', 'internal'], 3000, 3100, true},
		CutCase{'a bridge that starts on internal power sees the cut', ['internal'], 1000, 1500, true},
		CutCase{'depletion is no new cut', ['connected', 'internal', 'depleted'], 2000, 3100, false},
	]
	for c in cases {
		mut s := State{}
		for i, u in c.states {
			s.take_view(lcl.FieldView{
				umbilical: u
			}, 1000 * (i + 1))
		}
		assert s.cut_at == c.cut_at, c.name
		assert s.emergency(c.now) == c.up, c.name
	}
}

struct LinkCase {
	name      string
	umbilical string
	silent    i64 // in the view, which arrived at 1000
	now       i64
	want      string
}

fn test_link() {
	cases := [
		LinkCase{'a pulse just in', 'connected', 300, 1000, 'live'},
		LinkCase{'silence grows between views', 'connected', 4000, 1999, 'live'},
		LinkCase{'lost at lost_ms', 'connected', 4000, 2000, 'lost'},
		LinkCase{'lost while the grace runs', 'connected', 40000, 1000, 'lost'},
		LinkCase{'cut on internal power', 'internal', 46000, 1000, 'cut'},
		LinkCase{'depleted', 'depleted', 400000, 1000, 'depleted'},
		LinkCase{'a field unit without silent_ms reads live', 'connected', 0, 1000, 'live'},
		LinkCase{'a view older than silent_ms says nothing', 'connected', 200, 2001, 'stale'},
		LinkCase{'a stale view says nothing of a cut either', 'internal', 46000, 21000, 'stale'},
	]
	for c in cases {
		s := State{
			view:    lcl.FieldView{
				umbilical: c.umbilical
				silent_ms: c.silent
			}
			view_at: 1000
		}
		assert s.link(c.now) == c.want, c.name
	}
	assert State{}.link(5000) == 'never'
	for umbilical, want in {
		'connected': 'awaiting'
		'internal':  'cut'
	} {
		assert State{
			view:    lcl.FieldView{
				umbilical: umbilical
				silent_ms: 41000
				awaiting:  true
			}
			view_at: 1000
		}.link(1000) == want, 'no pulse yet, ${umbilical}'
	}
	assert State{
		view:    lcl.FieldView{
			silent_ms: 1500
		}
		view_at: 1000
	}.silence(3000) == 3500
}

fn test_panel() {
	mut s := State{}
	state, _ := s.panel('CASPER-3')
	assert state == 'idle'
	s.take_event(lcl.HqEvent{
		...opened(release)
		needed: 3
	}, 1000)
	assert s.needed == 3
	s.take_event(ballot(release, 'CASPER-3', 'approve'), 1200)
	for unit, want in {
		'MELCHIOR-1':  'deliberating'
		'BALTHASAR-2': 'deliberating'
		'CASPER-3':    'approve'
	} {
		got, _ := s.panel(unit)
		assert got == want, unit
	}
	s.take_event(verdict(release, 1, 3, 'MELCHIOR-1=reject', 'BALTHASAR-2=fault',
		'CASPER-3=approve'), 1500)
	for unit, want in {
		'MELCHIOR-1':  'reject'
		'BALTHASAR-2': 'fault'
		'CASPER-3':    'approve'
	} {
		got, v := s.panel(unit)
		assert got == want && v.unit == unit, unit
	}
}

fn test_status_block() {
	for seat, want in {
		'pilot': 'PILOT'
		'dummy': 'DUMMY'
		'empty': 'OFF'
	} {
		assert ex_mode(lcl.FieldView{ seat: seat }) == want, seat
	}
	assert ex_mode(lcl.FieldView{ seat: 'empty', benched: true }) == 'BENCHED'
	assert priority(release) == 'AAA'
	assert priority(reach) == 'AA'
	assert priority(lcl.Intent{ verb: 'selfdestruct' }) == 'AAA'
}

fn test_mission() {
	s := State{
		first_at: 10_000
	}
	assert State{}.mission(5000) == 'T+--:--'
	assert s.mission(10_999) == 'T+00:00'
	assert s.mission(10_000 + 61_000) == 'T+01:01'
	mut early := State{}
	early.take_event(lcl.HqEvent{
		fault: 'qwen3:8b: HTTP 429'
	}, 1000)
	early.take_view(lcl.FieldView{}, 4000)
	assert early.mission(early.faults[0].at) == 'T+00:00'
	assert early.mission(4000) == 'T+00:03'
}

const release = lcl.Intent{
	verb: 'release'
}
const reach = lcl.Intent{
	verb:   'goto'
	target: [3.0, 2.0]
}

fn opened(p lcl.Intent) lcl.HqEvent {
	return lcl.HqEvent{
		stage:    'deliberating'
		proposal: p
	}
}

fn ballot(p lcl.Intent, unit string, vote string) lcl.HqEvent {
	return lcl.HqEvent{
		stage:    'ballot'
		proposal: p
		votes:    [lcl.Vote{
			unit: unit
			vote: vote
		}]
	}
}

fn verdict(p lcl.Intent, yes int, needed int, votes ...string) lcl.HqEvent {
	return lcl.HqEvent{
		proposal: p
		approved: yes >= needed
		yes:      yes
		needed:   needed
		votes:    votes.map(lcl.Vote{
			unit: it.all_before('=')
			vote: it.all_after('=')
		})
	}
}

struct EventCase {
	name         string
	events       []lcl.HqEvent // arriving at 1000, 2000, 3000 and on
	deliberating bool
	code         int
	ballots      string // unit=vote, sorted by unit
	landed       string // unit=arrival, sorted by unit
	verdict_at   i64
}

fn test_take_event() {
	cases := [
		EventCase{'a proposal opens with no ballots', [opened(release)], true, 1, '', '', 0},
		EventCase{'ballots land one by one', [opened(release),
			ballot(release, 'CASPER-3', 'approve'), ballot(release, 'MELCHIOR-1', 'reject')], true, 1, 'CASPER-3=approve MELCHIOR-1=reject', 'CASPER-3=2000 MELCHIOR-1=3000', 0},
		EventCase{'the verdict closes it and keeps when each ballot landed', [
			opened(release), ballot(release, 'CASPER-3', 'approve'),
			verdict(release, 1, 3, 'MELCHIOR-1=reject', 'BALTHASAR-2=reject', 'CASPER-3=approve')], false, 1, 'BALTHASAR-2=reject CASPER-3=approve MELCHIOR-1=reject', 'BALTHASAR-2=3000 CASPER-3=2000 MELCHIOR-1=3000', 3000},
		EventCase{'a verdict whose opening was dropped opens and closes', [
			verdict(reach, 3, 2, 'MELCHIOR-1=approve', 'BALTHASAR-2=approve', 'CASPER-3=approve')], false, 1, 'BALTHASAR-2=approve CASPER-3=approve MELCHIOR-1=approve', 'BALTHASAR-2=1000 CASPER-3=1000 MELCHIOR-1=1000', 1000},
		EventCase{'a ballot for another proposal opens that one', [
			opened(reach), ballot(release, 'CASPER-3', 'approve')], true, 2, 'CASPER-3=approve', 'CASPER-3=2000', 0},
		EventCase{'the same proposal put again opens anew', [
			opened(release), ballot(release, 'CASPER-3', 'approve'),
			opened(release)], true, 2, '', '', 0},
		EventCase{'a new vote leaves the last verdict standing', [
			verdict(reach, 3, 2, 'MELCHIOR-1=approve', 'BALTHASAR-2=approve', 'CASPER-3=approve'),
			opened(release)], true, 2, '', '', 1000},
		EventCase{'a fault closes a vote whose verdict the stream dropped', [
			opened(release), lcl.HqEvent{
				fault: 'qwen3:8b: HTTP 429'
			}], false, 1, '', '', 0},
		EventCase{'a vote a fault ends leaves no verdict standing', [
			verdict(reach, 3, 2, 'MELCHIOR-1=approve', 'BALTHASAR-2=approve', 'CASPER-3=approve'),
			opened(release), lcl.HqEvent{
				fault: 'qwen3:8b: HTTP 429'
			}], false, 2, '', '', 0},
	]
	for c in cases {
		mut s := State{}
		for i, e in c.events {
			s.take_event(e, 1000 * (i + 1))
		}
		assert s.deliberating == c.deliberating, c.name
		assert s.code == c.code, c.name
		mut voters := s.ballots.keys()
		voters.sort()
		assert voters.map('${it}=${s.ballots[it].vote}').join(' ') == c.ballots, c.name
		assert voters.map('${it}=${s.landed[it]}').join(' ') == c.landed, c.name
		assert s.verdict_at == c.verdict_at, c.name
	}
}

struct CutVoteCase {
	name         string
	open         bool     // a release opened at 2000, after a verdict at 1000
	views        []string // umbilical per view, arriving at 3000, 4000 and on
	deliberating bool
	verdict_at   i64
	melchior     string // MELCHIOR-1's panel, which has no ballot in the open vote
}

fn test_a_cut_ends_an_open_vote() {
	cases := [
		CutVoteCase{'a connected cable keeps the vote open', true, ['connected', 'connected'], true, 1000, 'deliberating'},
		CutVoteCase{'the cut ends it without a verdict', true, ['connected', 'internal'], false, 0, 'idle'},
		CutVoteCase{'a bridge that starts on internal power ends it', true, ['internal'], false, 0, 'idle'},
		CutVoteCase{'a cut between votes leaves the verdict standing', false, ['connected',
			'internal'], false, 1000, 'approve'},
	]
	for c in cases {
		mut s := State{}
		s.take_event(verdict(reach, 3, 2, 'MELCHIOR-1=approve', 'BALTHASAR-2=approve',
			'CASPER-3=approve'), 1000)
		if c.open {
			s.take_event(opened(release), 2000)
			s.take_event(ballot(release, 'CASPER-3', 'approve'), 2500)
		}
		for i, u in c.views {
			s.take_view(lcl.FieldView{
				umbilical: u
			}, 3000 + 1000 * i)
		}
		assert s.deliberating == c.deliberating, c.name
		assert s.verdict_at == c.verdict_at, c.name
		melchior, _ := s.panel('MELCHIOR-1')
		casper, _ := s.panel('CASPER-3')
		assert melchior == c.melchior, c.name
		assert casper == 'approve', c.name
	}
}

fn test_take_event_keeps_faults_and_verdicts_apart() {
	mut s := State{}
	s.take_event(verdict(release, 2, 3, 'MELCHIOR-1=approve', 'BALTHASAR-2=reject',
		'CASPER-3=approve'), 5000)
	assert s.verdicts == [Entry{5000, 'release 2/3', false}]
	s.take_event(lcl.HqEvent{
		fault: 'qwen3:8b: HTTP 429'
	}, 6000)
	assert s.faults == [Entry{6000, 'qwen3:8b: HTTP 429', false}]
	assert s.verdict_at == 5000 && s.verdicts.len == 1
}

struct LeftCase {
	name      string
	umbilical string
	internal  i64
	view_at   i64
	now       i64
	want      string // the clock, minutes and seconds then centiseconds
}

fn test_left_ms() {
	cases := [
		LeftCase{'connected shows the whole budget', 'connected', 300000, 1000, 9000, '5:00 00'},
		LeftCase{'internal counts down between views', 'internal', 300000, 1000, 2500, '4:58 50'},
		LeftCase{'internal counts down a minute later', 'internal', 120000, 1000, 61000, '1:00 00'},
		LeftCase{'the last moment of power still shows', 'internal', 1000, 1000, 1999, '0:00 01'},
		LeftCase{'centiseconds round up', 'internal', 1000, 1000, 1011, '0:00 99'},
		LeftCase{'internal never goes below zero', 'internal', 1000, 1000, 9000, '0:00 00'},
		LeftCase{'depleted shows nothing left', 'depleted', 0, 1000, 9000, '0:00 00'},
	]
	for c in cases {
		s := State{
			view:    lcl.FieldView{
				umbilical:   c.umbilical
				internal_ms: c.internal
			}
			view_at: c.view_at
		}
		big, small := clock(s.left_ms(c.now))
		assert '${big} ${small}' == c.want, c.name
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
