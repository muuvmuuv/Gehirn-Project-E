module main

import math
import lcl

// keep is how many lines each of the bridge's lists holds, newest first.
const keep = 6

// silent_ms is how long a stream may stay quiet, in milliseconds, before the bridge says so. The
// field unit sends a view every 100 ms.
const silent_ms = 1000

// lost_ms is how long HQ may stay silent, in milliseconds, before the bridge warns that the
// umbilical has lost its signal. HQ pulses once per deliberation, about once a second, and a slow
// model stretches that to a few seconds; the cable counts as cut only after UMBILICAL_GRACE_MS.
const lost_ms = 5000

// emergency_ms is how long the EMERGENCY overlay stays up, in milliseconds, once the field unit
// reports internal power.
const emergency_ms = 3000

// history is how many views the harmonics graph and the scene's trail keep: 30 s at the field
// unit's 10 views a second.
const history = 300

// Sample is one view's sync ratio and the core's share of the controls, for the harmonics graph.
struct Sample {
	sync      f64
	authority f64
}

// Entry is one line of a log the bridge keeps: when it arrived, its text, and whether it went the
// way the stack wanted.
struct Entry {
	at   i64
	text string
	good bool
}

// State is everything the bridge shows, folded from the watch streams on the bridge's own clock.
// frame draws it, and take_view and take_event change it.
struct State {
mut:
	born         i64 // when the bridge started
	view         lcl.FieldView
	view_at      i64                 // when the newest view arrived; 0 before the first
	first_at     i64                 // when either stream first spoke, where the mission clock starts
	samples      []Sample            // one per view, oldest first, at most history
	trail        [][]f64             // the body's position per view, oldest first, at most history
	span         []f64               // xmin, ymin, xmax, ymax of everything the scene has shown
	cut_at       i64                 // when the view last turned to internal power; 0 before
	proposal     lcl.Intent          // the newest proposal put to MAGI
	code         int                 // how many proposals the bridge has seen go to the vote
	needed       int                 // the approvals the proposal needs, as HQ put it
	deliberating bool                // MAGI has the proposal and no verdict has arrived
	ballots      map[string]lcl.Vote // the proposal's ballots so far, by unit
	landed       map[string]i64      // when each of those ballots arrived
	verdict      lcl.HqEvent
	verdict_at   i64     // when the newest verdict arrived; 0 before, and once a vote ends without one
	verdicts     []Entry // each proposal with its verdict, newest first
	faults       []Entry // the core's faults, newest first
	refusals     []Entry // armor refusals, newest first
	outcomes     []Entry // every other outcome, newest first
	dropped      string  // why the newest dropped message was dropped
}

// take_view folds in a view from the field unit, which arrived at now.
fn (mut s State) take_view(v lcl.FieldView, now i64) {
	if s.first_at == 0 {
		s.first_at = now
	}
	if v.umbilical == 'internal' && s.view.umbilical != 'internal' {
		s.cut_at = now

		// UMBILICAL_GRACE_MS outlasts a whole deliberation, so a vote still open at the cut will
		// never see its verdict: HQ died during it, or the stream dropped the verdict.
		s.abandon()
	}
	s.view = v
	s.view_at = now
	s.samples = tail(s.samples, Sample{v.sync, v.authority})
	p := v.percept
	if p.pose.len >= 2 {
		s.trail = tail(s.trail, [p.pose[0], p.pose[1]])
		s.span = grow(s.span, p.pose[0], p.pose[1], 0)
	}
	for e in p.scene {
		if e.pos.len >= 2 {
			s.span = grow(s.span, e.pos[0], e.pos[1], e.r)
		}
	}
	if v.goal.target.len >= 2 {
		s.span = grow(s.span, v.goal.target[0], v.goal.target[1], 0)
	}
	for o in v.outcomes {
		if o.kind.starts_with('armor refused') {
			s.refusals = front(s.refusals, Entry{now, o.kind.all_after('armor refused '), false})
		} else {
			s.outcomes = front(s.outcomes, Entry{now, o.kind, o.good})
		}
	}
}

// take_event folds in an event from HQ, which arrived at now: a proposal going to the vote, a
// ballot landing, a verdict, or a core fault. A ballot or verdict for a proposal the bridge has
// not seen go to the vote opens it, since the watch stream may drop the opening.
fn (mut s State) take_event(e lcl.HqEvent, now i64) {
	if s.first_at == 0 {
		s.first_at = now
	}
	if e.fault != '' {
		s.faults = front(s.faults, Entry{now, e.fault, false})

		// main.v hq faults only before it puts a proposal to MAGI and pushes its events in order
		// from one thread, so a fault while a vote is open means the stream dropped its verdict.
		s.abandon()
		return
	}
	if e.stage == 'deliberating' || !s.deliberating || e.proposal != s.proposal {
		s.deliberating = true
		s.proposal = e.proposal
		s.needed = e.needed
		s.ballots = map[string]lcl.Vote{}
		s.landed = map[string]i64{}
		s.code++
	}
	for v in e.votes {
		if v.unit !in s.landed {
			s.landed[v.unit] = now
		}
		s.ballots[v.unit] = v
	}
	if e.stage in ['deliberating', 'ballot'] {
		return
	}
	s.deliberating = false
	s.verdict = e
	s.verdict_at = now
	s.verdicts =
		front(s.verdicts, Entry{now, '${e.proposal.label()} ${e.yes}/${e.votes.len}', e.approved})
}

// abandon closes a vote still open without a verdict, so 決議 shows none for it.
fn (mut s State) abandon() {
	if s.deliberating {
		s.deliberating = false
		s.verdict_at = 0
	}
}

// panel is what unit's MAGI panel shows: its ballot once that has landed, deliberating while MAGI
// has the proposal, and idle before the first vote.
fn (s State) panel(unit string) (string, lcl.Vote) {
	v := s.ballots[unit] or {
		return if s.deliberating { 'deliberating' } else { 'idle' }, lcl.Vote{
			unit: unit
		}
	}
	return v.vote, v
}

// front is list with x added in front, cut to keep.
fn front[T](list []T, x T) []T {
	mut out := [x]
	out << list
	return if out.len > keep { out[..keep] } else { out }
}

// tail is list with x added at the end, cut to the newest history.
fn tail[T](list []T, x T) []T {
	mut out := list.clone()
	out << x
	return if out.len > history { out[out.len - history..] } else { out }
}

// grow is span widened to hold a circle of radius r at x, y; an empty span becomes that circle's
// box.
fn grow(span []f64, x f64, y f64, r f64) []f64 {
	if span.len < 4 {
		return [x - r, y - r, x + r, y + r]
	}
	return [math.min(span[0], x - r), math.min(span[1], y - r),
		math.max(span[2], x + r), math.max(span[3], y + r)]
}

// left_ms is the internal power left at now: the newest view's figure, counted down on the
// bridge's clock while the unit runs on internal power, never below zero.
fn (s State) left_ms(now i64) i64 {
	if s.view.umbilical != 'internal' {
		return s.view.internal_ms
	}
	left := s.view.internal_ms - (now - s.view_at)
	return if left > 0 { left } else { 0 }
}

// silence is how long HQ has been silent at now, as the field unit last saw it and counted on
// since on the bridge's clock; link trusts it only while the views keep arriving.
fn (s State) silence(now i64) i64 {
	return if s.view_at == 0 { 0 } else { s.view.silent_ms + now - s.view_at }
}

// link is where the umbilical stands at now, as the bridge shows it: never before the first view,
// stale once the newest view is older than silent_ms, since only the views tell of the cable and
// of HQ's silence, live, lost once HQ has been silent for lost_ms while the cable still counts as
// connected, cut on internal power, and depleted.
fn (s State) link(now i64) string {
	if s.view_at == 0 {
		return 'never'
	}
	if heard(s.view_at, now) != 'live' {
		return 'stale'
	}
	return match s.view.umbilical {
		'internal' {
			'cut'
		}
		'depleted' {
			'depleted'
		}
		else {
			if s.silence(now) >= lost_ms {
				'lost'
			} else {
				'live'
			}
		}
	}
}

// emergency says whether the EMERGENCY overlay is up at now: for emergency_ms after the field unit
// first reported internal power, while it still does.
fn (s State) emergency(now i64) bool {
	return s.cut_at > 0 && s.view.umbilical == 'internal' && now - s.cut_at < emergency_ms
}

// clock renders ms as minutes and seconds, m:ss, and the centiseconds apart, rounded up, so a full
// five minutes reads 5:00 00 and the last moment of power 0:00 01.
fn clock(ms i64) (string, string) {
	cs := (ms + 9) / 10
	secs := cs / 100
	return '${secs / 60}:${secs % 60:02}', '${cs % 100:02}'
}

// mission is the mission clock at now, T+mm:ss from the first message of either stream, or
// T+--:-- before it.
fn (s State) mission(now i64) string {
	if s.first_at == 0 {
		return 'T+--:--'
	}
	secs := (now - s.first_at) / 1000
	return 'T+${secs / 60:02}:${secs % 60:02}'
}

// ex_mode is the seat as MAGI's status block names it: PILOT, DUMMY, BENCHED when the dummy plug
// fell out of sync, else OFF.
fn ex_mode(v lcl.FieldView) string {
	return match v.seat {
		'pilot' {
			'PILOT'
		}
		'dummy' {
			'DUMMY'
		}
		else {
			if v.benched {
				'BENCHED'
			} else {
				'OFF'
			}
		}
	}
}

// priority grades a proposal by the votes it needs: AAA when every unit must approve
// (lcl.is_irreversible), AA for a majority.
fn priority(p lcl.Intent) string {
	return if lcl.is_irreversible(p.verb) { 'AAA' } else { 'AA' }
}

// heard says how long ago a stream last spoke, or that it is silent past silent_ms or has never
// spoken.
fn heard(at i64, now i64) string {
	if at == 0 {
		return 'never heard'
	}
	if now - at > silent_ms {
		return 'silent ${(now - at) / 1000} s'
	}
	return 'live'
}

// seal marks a verdict as MAGI's display does; magi/magi.v Verdict.str marks it the same way.
fn seal(ok bool) string {
	return if ok { '可決' } else { '否決' }
}

// mark is one vote's mark: 可決, 否決 or 故障; magi/magi.v Verdict.str marks ballots the same way.
fn mark(vote string) string {
	return match vote {
		'approve' { '可決' }
		'reject' { '否決' }
		else { '故障' }
	}
}

// wrap breaks text into lines of at most width characters, at spaces where it can.
fn wrap(text string, width int) []string {
	mut lines := []string{}
	mut line := ''
	for word in text.split(' ') {
		mut w := word
		for w.runes().len > width {
			if line != '' {
				lines << line
				line = ''
			}
			lines << w.runes()[..width].string()
			w = w.runes()[width..].string()
		}
		if line == '' {
			line = w
		} else if line.runes().len + 1 + w.runes().len <= width {
			line += ' ' + w
		} else {
			lines << line
			line = w
		}
	}
	if line != '' {
		lines << line
	}
	return lines
}
