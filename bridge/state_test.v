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
	]
	for c in cases {
		mut s := State{}
		for i, e in c.events {
			s.take_event(e, 1000 * (i + 1))
		}
		assert s.deliberating == c.deliberating, c.name
		assert s.code == c.code, c.name
		mut units := s.ballots.keys()
		units.sort()
		assert units.map('${it}=${s.ballots[it].vote}').join(' ') == c.ballots, c.name
		assert units.map('${it}=${s.landed[it]}').join(' ') == c.landed, c.name
		assert s.verdict_at == c.verdict_at, c.name
	}
}

fn test_take_event_keeps_faults_and_verdicts_apart() {
	mut s := State{}
	s.take_event(verdict(release, 2, 3, 'MELCHIOR-1=approve', 'BALTHASAR-2=reject',
		'CASPER-3=approve'), 5000)
	assert s.proposals == ['release 否決 2/3, need 3']
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
