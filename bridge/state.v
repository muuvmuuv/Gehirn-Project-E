module main

import lcl

// keep is how many lines each of the bridge's lists holds, newest first.
const keep = 6

// silent_ms is how long a stream may stay quiet, in milliseconds, before the bridge says so. The
// field unit sends a view every 100 ms.
const silent_ms = 1000

// State is everything the bridge shows, folded from the watch streams on the bridge's own clock.
// frame draws it, and take_view and take_event change it.
struct State {
mut:
	view       lcl.FieldView
	view_at    i64 // when the newest view arrived; 0 before the first
	verdict    lcl.HqEvent
	verdict_at i64      // when the newest verdict arrived; 0 before the first
	proposals  []string // each proposal with its verdict, newest first
	fault      string   // the core's newest fault
	fault_at   i64
	refusals   []string // armor refusals, newest first
	outcomes   []string // every other outcome, newest first
	dropped    string   // why the newest dropped message was dropped
}

// take_view folds in a view from the field unit, which arrived at now.
fn (mut s State) take_view(v lcl.FieldView, now i64) {
	s.view = v
	s.view_at = now
	for o in v.outcomes {
		if o.kind.starts_with('armor refused') {
			s.refusals = front(s.refusals, o.kind)
		} else {
			s.outcomes = front(s.outcomes, o.kind)
		}
	}
}

// take_event folds in an event from HQ, which arrived at now: a verdict, or a core fault.
fn (mut s State) take_event(e lcl.HqEvent, now i64) {
	if e.fault != '' {
		s.fault = e.fault
		s.fault_at = now
		return
	}
	s.verdict = e
	s.verdict_at = now
	s.proposals = front(s.proposals,
		'${e.proposal.label()} ${seal(e.approved)} ${e.yes}/${e.votes.len}, need ${e.needed}')
}

// front is lines with line added in front, cut to keep.
fn front(lines []string, line string) []string {
	mut out := [line]
	out << lines
	return if out.len > keep { out[..keep] } else { out }
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

// clock renders ms as m:ss, rounded up, so a full five minutes reads 5:00 and the last moment of
// power 0:01.
fn clock(ms i64) string {
	secs := (ms + 999) / 1000
	return '${secs / 60}:${secs % 60:02}'
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
