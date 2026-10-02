// Wire: LCL between machines, as ADR-0003 decides. It seals and opens the four streams between
// HQ and the field unit, declares their Zenoh ports, and pumps values between each tier's
// channels and those ports. In canon the umbilical cable carries power to the Eva; here it
// carries LCL.
module wire

import crypto.hmac
import crypto.sha256
import encoding.hex
import time
import x.json2
import lcl
import zenoh

// version is the schema version every message carries as its first field (ADR-0003).
pub const version = 1

// max_payload is the largest payload, in bytes, that an Opener reads (ADR-0003).
const max_payload = 65536

// poll is how long a pump sleeps once nothing waits on either side.
// ponytail: polling, since zenoh-c has no select over its handlers; 5 ms adds at most a quarter
// of a field tick to a message. Block on the handlers if a measurement asks for less.
const poll = 5 * time.millisecond

// Frame is one sealed message: its key expression, its payload, and the payload's HMAC, which
// travels as the Zenoh attachment. A Sealer makes it and a pump puts it.
pub struct Frame {
pub:
	key     string
	payload []u8
	mac     []u8
}

struct Header {
	v   int
	seq i64
}

struct ContextMsg {
	v       int
	seq     i64
	percept lcl.Percept
	goal    lcl.Intent
	seat    string
	sync    f64
}

struct OutcomeMsg {
	v       int
	seq     i64
	outcome lcl.Outcome
}

struct GoalMsg {
	v       int
	seq     i64
	goal    lcl.Intent
	echo_ms i64
}

struct PulseMsg {
	v       int
	seq     i64
	echo_ms i64
}

struct ViewMsg {
	v    int
	seq  i64
	view lcl.FieldView
}

struct EventMsg {
	v     int
	seq   i64
	event lcl.HqEvent
}

// init warms every type this module decodes before any thread exists, against the json2 cache
// race of oai/oai.v init: both pumps decode Header, and a test runs both in one process.
// ponytail: a message type added here must be warmed too; drop this once json2 guards its cache.
fn init() {
	_ := json2.decode[Header]('{}') or { Header{} }
	_ := json2.decode[ContextMsg]('{"percept":{"scene":[{}]}}') or { ContextMsg{} }
	_ := json2.decode[OutcomeMsg]('{"outcome":{}}') or { OutcomeMsg{} }
	_ := json2.decode[GoalMsg]('{"goal":{}}') or { GoalMsg{} }
	_ := json2.decode[PulseMsg]('{}') or { PulseMsg{} }
	_ := json2.decode[ViewMsg]('{"view":{"percept":{"scene":[{}]},"outcomes":[{}]}}') or {
		ViewMsg{}
	}
	_ := json2.decode[EventMsg]('{"event":{"proposal":{},"votes":[{}]}}') or { EventMsg{} }
}

// key is the key expression of one stream of unit, such as gehirn/eva01/goal.
pub fn key(unit string, stream string) string {
	return 'gehirn/${unit}/${stream}'
}

// mac is the HMAC SHA256 under link over a key expression, a newline and the payload, so a
// message is bound to the stream it was sealed for.
fn mac(link []u8, k string, payload []u8) []u8 {
	mut data := '${k}\n'.bytes()
	data << payload
	return hmac.new(link, data, sha256.sum, sha256.block_size)
}

// check_unit fails unless unit can name a unit in a key expression: 1 to 32 lowercase letters,
// digits and hyphens. Zenoh reads `*`, `$`, `?`, `#` and `/` as syntax, so a unit named `*` would
// hear every unit. main.v and the bridge check UNIT_ID with it.
pub fn check_unit(unit string) ! {
	if unit == '' || unit.len > 32 || !unit.contains_only('abcdefghijklmnopqrstuvwxyz0123456789-') {
		return error('not a unit name; accepted 1 to 32 lowercase letters, digits and hyphens')
	}
}

// decode_key reads a key of 64 hex digits, such as UMBILICAL_KEY or WATCH_KEY, as 32 bytes. Its
// error never shows the value, which is a key.
pub fn decode_key(digits string) ![]u8 {
	if digits.len != 64 || !digits.contains_only('0123456789abcdefABCDEF') {
		return error('not 64 hex digits; generate one with `openssl rand -hex 32`')
	}
	return hex.decode(digits)!
}

fn check_link(link []u8) ! {
	if link.len != 32 {
		return error('wire: a link key is 32 bytes, not ${link.len}')
	}
}

// Sealer seals what one side sends. It numbers every message, starting from its own start time
// in microseconds, so the numbers keep growing across restarts.
pub struct Sealer {
	link []u8
	unit string
mut:
	seq i64
}

// new_sealer is a Sealer for unit under link, the unit's 32 byte key.
pub fn new_sealer(link []u8, unit string) !Sealer {
	check_link(link)!
	return Sealer{
		link: link
		unit: unit
		seq:  time.now().unix_micro()
	}
}

fn (s Sealer) frame(stream string, payload string) Frame {
	k := key(s.unit, stream)
	p := payload.bytes()
	return Frame{
		key:     k
		payload: p
		mac:     mac(s.link, k, p)
	}
}

// context seals the field's snapshot for HQ, without the mission and the memory, which HQ owns.
pub fn (mut s Sealer) context(c lcl.Context) Frame {
	s.seq++
	return s.frame('context', json2.encode(ContextMsg{
		v:       version
		seq:     s.seq
		percept: c.percept
		goal:    c.goal
		seat:    c.seat
		sync:    c.sync
	}))
}

// outcome seals an outcome for HQ.
pub fn (mut s Sealer) outcome(o lcl.Outcome) Frame {
	s.seq++
	return s.frame('outcome', json2.encode(OutcomeMsg{
		v:       version
		seq:     s.seq
		outcome: o
	}))
}

// goal seals an approved goal for the field, with echo_ms, the t_ms of the newest percept HQ has
// received.
pub fn (mut s Sealer) goal(g lcl.Intent, echo_ms i64) Frame {
	s.seq++
	return s.frame('goal', json2.encode(GoalMsg{
		v:       version
		seq:     s.seq
		goal:    g
		echo_ms: echo_ms
	}))
}

// pulse seals HQ's sign of life for the field, with echo_ms as in goal.
pub fn (mut s Sealer) pulse(echo_ms i64) Frame {
	s.seq++
	return s.frame('pulse', json2.encode(PulseMsg{
		v:       version
		seq:     s.seq
		echo_ms: echo_ms
	}))
}

// view seals the field unit's view for the bridge, under WATCH_KEY (ADR-0005).
pub fn (mut s Sealer) view(v lcl.FieldView) Frame {
	s.seq++
	return s.frame('watch/field', json2.encode(ViewMsg{
		v:    version
		seq:  s.seq
		view: v
	}))
}

// event seals one of HQ's events for the bridge, under WATCH_KEY (ADR-0005).
pub fn (mut s Sealer) event(e lcl.HqEvent) Frame {
	s.seq++
	return s.frame('watch/hq', json2.encode(EventMsg{
		v:     version
		seq:   s.seq
		event: e
	}))
}

// Opener opens what one side receives. It checks a sample's size and HMAC before it parses
// anything, then its version and sequence number, and keeps the last number it accepted per
// stream. Every error is a dropped message, and its text names the stream and never a number,
// so a pump can say it once.
pub struct Opener {
	link []u8
	unit string
mut:
	last map[string]i64
}

// new_opener is an Opener for unit under link, the unit's 32 byte key.
pub fn new_opener(link []u8, unit string) !Opener {
	check_link(link)!
	return Opener{
		link: link
		unit: unit
	}
}

// check returns the payload of a sample on stream that passes every check but freshness, and its
// sequence number, which the caller records once the rest is read.
fn (o &Opener) check(stream string, s zenoh.Sample) !(string, i64) {
	if s.payload.len > max_payload {
		return error('wire: ${stream} over ${max_payload} bytes')
	}
	if !hmac.equal(s.attachment, mac(o.link, key(o.unit, stream), s.payload)) {
		return error('wire: ${stream} fails its mac')
	}
	raw := s.payload.bytestr()
	h := json2.decode[Header](raw) or { return error('wire: unreadable ${stream}') }
	if h.v != version {
		return error('wire: ${stream} of another version than ${version}')
	}
	if h.seq <= o.last[stream] or { 0 } {
		return error('wire: ${stream} repeats or precedes the last one accepted')
	}
	return raw, h.seq
}

// fresh fails unless echo_ms lies within grace_ms before now, on the field's own clock.
fn fresh(stream string, echo_ms i64, now i64, grace_ms i64) ! {
	if echo_ms > now || now - echo_ms > grace_ms {
		return error('wire: ${stream} echoes a percept outside the grace')
	}
}

// context opens a snapshot from the field. Its mission and memory are empty.
pub fn (mut o Opener) context(s zenoh.Sample) !lcl.Context {
	raw, seq := o.check('context', s)!
	m := json2.decode[ContextMsg](raw) or { return error('wire: unreadable context') }
	o.last['context'] = seq
	return lcl.Context{
		percept: m.percept
		goal:    m.goal
		seat:    m.seat
		sync:    m.sync
	}
}

// outcome opens an outcome from the field.
pub fn (mut o Opener) outcome(s zenoh.Sample) !lcl.Outcome {
	raw, seq := o.check('outcome', s)!
	m := json2.decode[OutcomeMsg](raw) or { return error('wire: unreadable outcome') }
	o.last['outcome'] = seq
	return m.outcome
}

// goal opens an approved goal from HQ, which must echo a percept from within grace_ms before now.
pub fn (mut o Opener) goal(s zenoh.Sample, now i64, grace_ms i64) !lcl.Intent {
	raw, seq := o.check('goal', s)!
	m := json2.decode[GoalMsg](raw) or { return error('wire: unreadable goal') }
	fresh('goal', m.echo_ms, now, grace_ms)!
	o.last['goal'] = seq
	return m.goal
}

// pulse opens HQ's sign of life, which must echo a percept from within grace_ms before now.
pub fn (mut o Opener) pulse(s zenoh.Sample, now i64, grace_ms i64) ! {
	raw, seq := o.check('pulse', s)!
	m := json2.decode[PulseMsg](raw) or { return error('wire: unreadable pulse') }
	fresh('pulse', m.echo_ms, now, grace_ms)!
	o.last['pulse'] = seq
}

// view opens the field unit's view, as the bridge receives it.
pub fn (mut o Opener) view(s zenoh.Sample) !lcl.FieldView {
	raw, seq := o.check('watch/field', s)!
	m := json2.decode[ViewMsg](raw) or { return error('wire: unreadable watch/field') }
	o.last['watch/field'] = seq
	return m.view
}

// event opens one of HQ's events, as the bridge receives it.
pub fn (mut o Opener) event(s zenoh.Sample) !lcl.HqEvent {
	raw, seq := o.check('watch/hq', s)!
	m := json2.decode[EventMsg](raw) or { return error('wire: unreadable watch/hq') }
	o.last['watch/hq'] = seq
	return m.event
}

// FieldPorts are the field unit's ends of the four streams, with ADR-0003's quality of service.
pub struct FieldPorts {
	context &zenoh.Publisher
	outcome &zenoh.Publisher
	goal    &zenoh.Subscriber
	pulse   &zenoh.Subscriber
}

// field_ports declares the field unit's ports for unit on s.
pub fn field_ports(s &zenoh.Session, unit string) !FieldPorts {
	return FieldPorts{
		context: s.publisher(key(unit, 'context'), zenoh.Qos{ congestion: .drop, priority: .data })!
		outcome: s.publisher(key(unit, 'outcome'), zenoh.Qos{
			congestion: .drop
			priority:   .data_high
		})!
		goal:    s.subscriber(key(unit, 'goal'), zenoh.Queue{ cap: 8 })!
		pulse:   s.subscriber(key(unit, 'pulse'), zenoh.Queue{ cap: 8 })!
	}
}

// HqPorts are HQ's ends of the four streams, with ADR-0003's quality of service.
pub struct HqPorts {
	context &zenoh.Subscriber
	outcome &zenoh.Subscriber
	goal    &zenoh.Publisher
	pulse   &zenoh.Publisher
}

// hq_ports declares HQ's ports for unit on s.
pub fn hq_ports(s &zenoh.Session, unit string) !HqPorts {
	return HqPorts{
		context: s.subscriber(key(unit, 'context'), zenoh.Queue{ ring: true, cap: 1 })!
		outcome: s.subscriber(key(unit, 'outcome'), zenoh.Queue{ cap: 32 })!
		goal:    s.publisher(key(unit, 'goal'), zenoh.Qos{
			congestion: .block
			priority:   .interactive_high
			express:    true
		})!
		pulse:   s.publisher(key(unit, 'pulse'), zenoh.Qos{
			congestion: .drop
			priority:   .interactive_high
		})!
	}
}

// put sends f on p, or returns why it could not.
fn put(p &zenoh.Publisher, f Frame) ! {
	p.put(f.payload, f.mac) or { return error('wire: cannot put ${f.key.all_after_last('/')}') }
}

// Field is the field unit's end of the link, run on its own thread by Field.run.
@[heap]
pub struct Field {
	ports    FieldPorts
	grace_ms i64
mut:
	sealer    Sealer
	opener    Opener
	last_note string
}

// new_field is the field unit's end of the link for unit under link, dropping any goal or pulse
// that echoes a percept older than grace_ms, the umbilical's grace.
pub fn new_field(ports FieldPorts, link []u8, unit string, grace_ms i64) !&Field {
	return &Field{
		ports:    ports
		grace_ms: grace_ms
		sealer:   new_sealer(link, unit)!
		opener:   new_opener(link, unit)!
	}
}

// run pumps until the process ends: the newest snapshot and every outcome to HQ, and each goal
// and pulse from HQ to the field loop as an HqMsg, approved or alive. A dropped message becomes a
// note in from_hq, once until the next different one. It only try_pushes into from_hq, dropping
// the newest when full, so it never blocks the field loop.
pub fn (mut f Field) run(to_hq chan lcl.Context, outcomes chan lcl.Outcome, from_hq chan lcl.HqMsg) {
	for {
		mut c := lcl.Context{}
		if to_hq.try_pop(mut c) == .success {
			put(f.ports.context, f.sealer.context(c)) or { f.note(err.msg(), from_hq) }
		}
		mut o := lcl.Outcome{}
		for outcomes.try_pop(mut o) == .success {
			put(f.ports.outcome, f.sealer.outcome(o)) or { f.note(err.msg(), from_hq) }
		}
		for {
			s := f.ports.goal.try_recv() or { break }
			g := f.opener.goal(s, lcl.now_ms(), f.grace_ms) or {
				f.note(err.msg(), from_hq)
				continue
			}
			_ = from_hq.try_push(lcl.HqMsg{
				goal:     g
				approved: true
			})
		}
		for {
			s := f.ports.pulse.try_recv() or { break }
			f.opener.pulse(s, lcl.now_ms(), f.grace_ms) or {
				f.note(err.msg(), from_hq)
				continue
			}
			_ = from_hq.try_push(lcl.HqMsg{
				alive: true
			})
		}
		time.sleep(poll)
	}
}

fn (mut f Field) note(msg string, from_hq chan lcl.HqMsg) {
	if msg != f.last_note {
		f.last_note = msg
		_ = from_hq.try_push(lcl.HqMsg{
			note: msg
		})
	}
}

// Hq is HQ's end of the link, run on its own thread by Hq.run.
@[heap]
pub struct Hq {
	ports HqPorts
mut:
	sealer    Sealer
	opener    Opener
	echo_ms   i64
	last_note string
}

// new_hq is HQ's end of the link for unit under link.
pub fn new_hq(ports HqPorts, link []u8, unit string) !&Hq {
	return &Hq{
		ports:  ports
		sealer: new_sealer(link, unit)!
		opener: new_opener(link, unit)!
	}
}

// run pumps until the process ends: the newest snapshot from the field into inbox, replacing a
// stale one, and every outcome into outcomes; and from outbox each approved goal to the goal
// stream and each sign of life to the pulse stream, both echoing the newest percept received.
// The notes in outbox and one for each dropped message, once until the next different one, go
// to notes for HQ to print. Notes and outcomes only try_push and drop the newest when full.
pub fn (mut h Hq) run(inbox chan lcl.Context, outcomes chan lcl.Outcome, outbox chan lcl.HqMsg, notes chan string) {
	for {
		for {
			s := h.ports.context.try_recv() or { break }
			c := h.opener.context(s) or {
				h.note(err.msg(), notes)
				continue
			}
			h.echo_ms = c.percept.t_ms
			for inbox.try_push(c) != .success {
				mut stale := lcl.Context{}
				_ = inbox.try_pop(mut stale)
			}
		}
		for {
			s := h.ports.outcome.try_recv() or { break }
			o := h.opener.outcome(s) or {
				h.note(err.msg(), notes)
				continue
			}
			_ = outcomes.try_push(o)
		}
		mut m := lcl.HqMsg{}
		for outbox.try_pop(mut m) == .success {
			if m.note != '' {
				_ = notes.try_push(m.note)
			}
			if m.approved {
				put(h.ports.goal, h.sealer.goal(m.goal, h.echo_ms)) or { h.note(err.msg(), notes) }
			}
			if m.alive {
				put(h.ports.pulse, h.sealer.pulse(h.echo_ms)) or { h.note(err.msg(), notes) }
			}
		}
		time.sleep(poll)
	}
}

fn (mut h Hq) note(msg string, notes chan string) {
	if msg != h.last_note {
		h.last_note = msg
		_ = notes.try_push(msg)
	}
}

// Watch is one tier's watch stream to the bridge (ADR-0005), sealed under WATCH_KEY and put at
// background priority, dropped when the queue is full, so a slow or absent bridge never holds up
// a tier. Its pump runs on a thread of its own and drops a value it cannot put without a word,
// since nothing acts on what the bridge shows.
@[heap]
pub struct Watch {
	publ &zenoh.Publisher
mut:
	sealer Sealer
}

fn new_watch(s &zenoh.Session, unit string, stream string, watch_key []u8) !&Watch {
	return &Watch{
		publ:   s.publisher(key(unit, stream), zenoh.Qos{
			congestion: .drop
			priority:   .background
		})!
		sealer: new_sealer(watch_key, unit)!
	}
}

// field_watch is the field unit's watch stream for unit on s, a session of its own that dials
// the bridge.
pub fn field_watch(s &zenoh.Session, unit string, watch_key []u8) !&Watch {
	return new_watch(s, unit, 'watch/field', watch_key)!
}

// hq_watch is HQ's watch stream for unit on s, a session of its own that dials the bridge.
pub fn hq_watch(s &zenoh.Session, unit string, watch_key []u8) !&Watch {
	return new_watch(s, unit, 'watch/hq', watch_key)!
}

// run_field puts every view from views until the channel closes.
pub fn (mut w Watch) run_field(views chan lcl.FieldView) {
	for {
		v := <-views or { return }
		put(w.publ, w.sealer.view(v)) or {}
	}
}

// run_hq puts every event from events until the channel closes.
pub fn (mut w Watch) run_hq(events chan lcl.HqEvent) {
	for {
		e := <-events or { return }
		put(w.publ, w.sealer.event(e)) or {}
	}
}

// BridgePorts are the bridge's ends of the two watch streams. The bridge declares no publisher.
pub struct BridgePorts {
pub:
	field &zenoh.Subscriber
	hq    &zenoh.Subscriber
}

// bridge_ports subscribes to unit's watch streams on s.
pub fn bridge_ports(s &zenoh.Session, unit string) !BridgePorts {
	return BridgePorts{
		field: s.subscriber(key(unit, 'watch/field'), zenoh.Queue{ cap: 16 })!
		hq:    s.subscriber(key(unit, 'watch/hq'), zenoh.Queue{ cap: 32 })!
	}
}
