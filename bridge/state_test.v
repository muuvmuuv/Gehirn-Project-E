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
				kind: 'armor refused release ${i}: a human was within 2.0 m at that moment'
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

	// The scene's span holds ground too, which lies outside the percept's scene.
	s.take_view(lcl.FieldView{
		percept: lcl.Percept{
			pose:   [0.0, 0.0]
			ground: [
				lcl.Entity{
					kind:   'ground'
					pos:    [9.0, 0.0]
					r:      1.0
					factor: 0.5
				},
			]
		}
	}, 1008)
	assert s.span == [0.0, -1.0, 10.0, 3.3]
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

struct ContactCase {
	name   string
	events []lcl.HqEvent // arriving at 1000, 2000, 3000 and on
	unit   string
	now    i64
	want   string
	faded  f64
}

fn test_contact() {
	rejected := verdict(release, 2, 3, 'MELCHIOR-1=reject', 'BALTHASAR-2=approve',
		'CASPER-3=approve')
	cases := [
		ContactCase{'idle before the first vote', [], 'CASPER-3', 5000, 'idle', 0},
		ContactCase{'deliberating once the proposal goes to MAGI', [
			opened(release),
		], 'MELCHIOR-1', 1100, 'deliberating', 0},
		ContactCase{'a ballot shows as it lands', [
			opened(release),
			ballot(release, 'CASPER-3', 'fault'),
		], 'CASPER-3', 2100, 'fault', 0},
		ContactCase{'the ballot holds after the verdict', [
			rejected,
		], 'MELCHIOR-1', 1000 + hold_ms, 'reject', 0},
		ContactCase{'then fades', [
			rejected,
		], 'MELCHIOR-1', 1000 + hold_ms + fade_ms / 2, 'reject', 0.5},
		ContactCase{'and is idle once faded', [
			rejected,
		], 'MELCHIOR-1', 1000 + hold_ms + fade_ms, 'idle', 0},
		ContactCase{'a new vote turns it blue', [
			rejected,
			opened(reach),
		], 'MELCHIOR-1', 2100, 'deliberating', 0},
		ContactCase{'a vote that ends without a verdict leaves it idle', [
			opened(release),
			ballot(release, 'CASPER-3', 'approve'),
			lcl.HqEvent{
				fault: 'qwen3:8b: HTTP 429'
			},
		], 'CASPER-3', 3100, 'idle', 0},
	]
	for c in cases {
		mut s := State{}
		for i, e in c.events {
			s.take_event(e, 1000 * (i + 1))
		}
		state, faded := s.contact(c.unit, c.now)
		assert state == c.want, c.name
		assert faded == c.faded, c.name
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
	assert s.verdicts.map(it.at) == [i64(5000)] && s.verdicts[0].code == 1
	assert s.verdicts[0].event.yes == 2 && !s.verdicts[0].event.approved
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

// scene is a state whose radar holds one entity of each kind around the body at the origin,
// with h1 inside rock's landing zone.
fn scene() State {
	mut s := State{}
	s.take_view(lcl.FieldView{
		percept: lcl.Percept{
			pose:   [0.0, 0.0]
			scene:  [
				lcl.Entity{
					id:   'h1'
					kind: 'human'
					pos:  [2.0, 0.0]
					r:    0.3
					vel:  [0.8, 0.0]
				},
				lcl.Entity{
					id:       'rock'
					kind:     'impact'
					pos:      [2.0, 1.0]
					r:        1.5
					lands_in: 12.34
				},
				lcl.Entity{
					id:   'o1'
					kind: 'obstacle'
					pos:  [0.0, -3.0]
					r:    0.5
				},
				lcl.Entity{
					id:   'b1'
					kind: 'beacon'
					pos:  [-3.0, 0.0]
					r:    0.3
				},
			]
			ground: [
				lcl.Entity{
					id:     'lake'
					kind:   'ground'
					pos:    [-3.0, 3.0]
					r:      1.0
					factor: 0.5
				},
			]
		}
	}, 1000)
	return s
}

struct HoverCase {
	name string
	at   []f64 // meters on the radar, offset by px pixels to the right
	px   f32
	want []string
}

fn test_hover() {
	s := scene()
	m, _ := s.radar()
	cases := [
		HoverCase{'a walking human, over the zone it stands in', [2.0, 0.0], 0, ['HUMAN H1',
			'DISTANCE 2.00 M', 'VELOCITY 0.80 M/S (0.80, 0.00)']},
		HoverCase{'a small mark answers 8 px from its center', [2.0, 0.0], 7.5, ['HUMAN H1',
			'DISTANCE 2.00 M', 'VELOCITY 0.80 M/S (0.80, 0.00)']},
		HoverCase{'a falling object', [2.0, 1.0], 0, ['IMPACT ROCK', 'DISTANCE 2.24 M',
			'LANDS IN 12.3 S']},
		HoverCase{'a standing obstacle', [0.0, -3.0], 0, ['OBSTACLE O1', 'DISTANCE 3.00 M',
			'STANDING']},
		HoverCase{'a beacon', [-3.0, 0.0], 0, ['BEACON B1', 'DISTANCE 3.00 M']},
		HoverCase{'ground', [-3.0, 3.0], 0, ['GROUND LAKE', 'DISTANCE 4.24 M',
			'FACTOR 0.50, 50% OF ITS SPEED']},
		HoverCase{'open floor', [-1.0, -1.5], 0, []string{}},
	]
	for c in cases {
		assert s.hover(m.px(c.at[0]) + c.px, m.py(c.at[1])) == c.want, c.name
	}
	assert State{}.hover(m.px(2.0), m.py(0.0)) == []string{}, 'no view, no radar'
}

// test_ballot_lines checks what a readout shows below the vote, model and latency.
fn test_ballot_lines() {
	fact := 'falling object rock lands where the target lies in 6.2 s: the target counts as a no-go zone'
	for why, want in {
		'within the fence':                                                       [
			'within the fence',
		]
		'course veto: ${fact}; the model voted approve: forced approve (--vote)': [
			'COURSE VETO',
			'falling object rock lands where the target lies in 6.2',
			's: the target counts as a no-go zone',
			'THE MODEL VOTED 可決',
			'forced approve (--vote)',
		]
		'course veto: without what the model voted':                              [
			'course veto: without what the model voted',
		]
	} {
		got := ballot_lines(2, lcl.Vote{
			unit:       'CASPER-3'
			model:      'mock-casper'
			vote:       'reject'
			why:        why
			latency_ms: 512
		})
		assert got[..3] == ['CASPER • 3 否決', 'MODEL MOCK-CASPER', 'LATENCY 512 MS'], why
		assert got[3..] == want, why
	}
}

fn test_hover_reads_the_unit_under_the_cursor() {
	mut s := State{}
	s.take_event(opened(release), 1000)
	center := fn (i int) []f32 {
		b := unit_box(i)
		return [b.x + b.w / 2, b.y + b.h / 2]
	}
	c := center(2)
	assert s.hover(c[0], c[1]) == []string{}, 'a unit still deliberating'
	s.take_event(lcl.HqEvent{
		...ballot(release, 'CASPER-3', 'approve')
		votes: [
			lcl.Vote{
				unit:  'CASPER-3'
				model: 'mock-casper'
				vote:  'approve'
				why:   'ok'
			},
		]
	}, 1200)
	assert s.hover(c[0], c[1])[0] == 'CASPER • 3 可決'
	m := center(0)
	assert s.hover(m[0], m[1]) == []string{}, 'MELCHIOR-1 has no ballot yet'
	assert s.hover(c[0], magi_box.y + 2) == []string{}, 'above the units'
}

struct ClickCase {
	name   string
	clicks [][]f32 // x, y in window pixels
	pinned i64
}

fn test_click() {
	block, row0, row1, away := [f32(100), 120], [f32(600), 255], [f32(600), 272], [
		f32(900),
		300,
	]
	cases := [
		ClickCase{'outside MAGI nothing pins', [away], 0},
		ClickCase{'the block pins the newest', [block], 4000},
		ClickCase{'a second click unpins', [block, block], 0},
		ClickCase{'the first line pins the verdict before the newest', [row0], 3000},
		ClickCase{'the first line pages back from a pinned one', [row0, row0], 2000},
		ClickCase{'the second line skips one', [row0, row1], 1000},
		ClickCase{'a line past the oldest is the block', [row0, row0, row0, row0], 0},
	]
	for c in cases {
		mut s := State{}
		for i in 1 .. 5 {
			s.take_event(verdict(if i % 2 == 0 { release } else { reach }, i % 2 + 1, 2,
				'CASPER-3=approve'), 1000 * i)
		}
		for xy in c.clicks {
			s.click(xy[0], xy[1])
		}
		assert s.pinned == c.pinned, c.name
	}
}

fn test_shown() {
	mut s := State{}
	s.take_event(opened(reach), 500)
	s.take_event(verdict(reach, 3, 2, 'MELCHIOR-1=approve', 'BALTHASAR-2=approve',
		'CASPER-3=approve'), 1000)
	s.take_event(opened(release), 2000)
	s.take_event(ballot(release, 'CASPER-3', 'reject'), 2500)
	assert s.shown().deliberating, 'nothing pinned shows the vote under way'
	s.pinned = 1000
	shown := s.shown()
	assert !shown.deliberating && shown.code == 1 && shown.proposal == reach
	assert shown.verdict_at == 1000 && shown.verdict.approved && shown.landed.len == 0
	assert shown.view_at == 0, 'the seat at a pinned vote is unknown'
	got, _ := shown.panel('CASPER-3')
	assert got == 'approve'
	assert s.showing() == 0 && s.code == 2
	for i in 0 .. keep {
		s.take_event(verdict(release, 0, 3, 'CASPER-3=reject'), 3000 + i)
	}
	assert s.pin() == -1 && s.shown().verdict_at == 3000 + keep - 1, 'a pin past the list lets go'
}

fn test_mouse_script() {
	steps := mouse_script('900,420@9000 click@9500 out@12000') or { panic(err) }
	assert steps.map(it.at) == [i64(9000), 9500, 12000]
	assert steps[1].e.typ == .mouse_down && steps[1].e.mouse_x == 900 && steps[1].e.mouse_y == 420
	assert steps[2].e.typ == .mouse_leave
	assert (mouse_script('') or { panic(err) }).len == 0
	for bad in ['900,420', 'click@soon', '1,2,3@5', 'x,1@5', 'wiggle@5'] {
		if _ := mouse_script(bad) {
			assert false, bad
		}
	}
}

struct StagedCase {
	name     string
	proposal string // the proposal's why
	ballot   string // CASPER-3's why
	staged   bool
}

fn test_staged() {
	veto := 'course veto: human h1 reaches the target in 0.9 s; the model voted reject: '
	cases := [
		StagedCase{'the script', 'Head for beacon b1.', 'Nothing to object to.', false},
		StagedCase{'a forced ballot', 'Head for beacon b1.', 'forced approve (--vote)', true},
		StagedCase{'a forced ballot behind a course veto', 'Head for beacon b1.', veto +
			'forced reject (--vote)', true},
		StagedCase{'a staged goto', 'Staged by --goto.', 'Nothing to object to.', true},
		StagedCase{'a staged proposal', 'Staged by --propose.', '', true},
		StagedCase{'a why that only names the flag', 'Do not use --goto.', '(--vote) is no reason', false},
	]
	for c in cases {
		mut s := State{}
		s.take_event(lcl.HqEvent{
			stage:    'ballot'
			proposal: lcl.Intent{
				...reach
				why: c.proposal
			}
			votes:    [
				lcl.Vote{
					unit: 'CASPER-3'
					vote: 'approve'
					why:  c.ballot
				},
			]
		}, 1000)
		assert s.staged() == c.staged, c.name
	}
}

fn test_a_pinned_staged_vote_stays_staged() {
	mut s := State{}
	s.take_event(lcl.HqEvent{
		proposal: lcl.Intent{
			...reach
			why: 'Staged by --goto.'
		}
		needed:   2
		votes:    [lcl.Vote{
			unit: 'CASPER-3'
			vote: 'approve'
		}]
	}, 1000)
	s.take_event(verdict(release, 3, 3, 'CASPER-3=approve'), 2000)
	assert !s.shown().staged(), 'the newest vote was the script'
	s.pinned = 1000
	assert s.shown().staged()
}
