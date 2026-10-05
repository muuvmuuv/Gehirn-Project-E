module plug

import crypto.hmac
import crypto.sha256
import math
import net
import time
import x.json2
import lcl

// deadzone is how far a stick may rest off center, as a share of full tilt, and still read zero,
// for stick.
// ponytail: one deadzone for every controller; make it a flag of gehirn-gamepad once a worn stick
// drifts past it.
const deadzone = 0.15

// seal is one datagram as read_datagram checks it: the JSON line of a Datagram, a newline, and
// 64 hex digits of HMAC SHA256 under key over that line. tools/pilot.py datagram() makes the same
// bytes, and test_seal holds seal to the datagram the two share.
fn seal(pilot string, u []f64, eject bool, seq i64, key []u8) []u8 {
	line := json2.encode(Datagram{ v: 1, seq: seq, pilot: pilot, u: u, eject: eject })
	return '${line}\n${hmac.new(key, line.bytes(), sha256.sum, sha256.block_size).hex()}'.bytes()
}

// open_feel checks one reply as seal_feel makes it and returns its feel, unless its t_ms is at or
// below last, the newest the pilot took, so a replayed or reordered reply never rumbles.
fn open_feel(raw []u8, key []u8, last i64) !lcl.Feel {
	line := unseal(raw, key, feel_prefix, 'reply')!
	if !lcl.complete(line) {
		return error('plug: unreadable reply')
	}
	r := json2.decode[Reply](line) or { return error('plug: unreadable reply') }
	if r.v != 1 {
		return error('plug: reply of another version than 1')
	}
	if r.feel.t_ms <= last {
		return error('plug: reply repeats or precedes the last one taken')
	}
	return r.feel
}

// stick is the velocity in m/s that gehirn-gamepad sends for a stick at x and y, each -1 to 1 as
// SDL reads them, with y pointing down. Inside deadzone it is zero; beyond it the speed rises to
// vmax at full tilt, in the stick's direction with y flipped, so pushing up drives toward +y.
pub fn stick(x f64, y f64, vmax f64) []f64 {
	tilt := math.hypot(x, y)
	if tilt <= deadzone || math.is_nan(tilt) {
		return [0.0, 0.0]
	}
	k := vmax * (math.min(tilt, 1.0) - deadzone) / (1.0 - deadzone) / tilt
	return [x * k, -y * k]
}

// Guard is gehirn-gamepad's hold on the seat and on the eject (ADR-0006). LB is a dead man's
// switch: the gamepad sends only while it is held, so letting go empties the seat seat_ms later
// and the dummy plug or the core takes over. Back and Start held down together for eject_ms
// eject, counted only once both have been seen up, so neither a stray press nor a button stuck
// down from the start ejects; an eject latches until gehirn restarts (Known issue 5).
pub struct Guard {
pub:
	eject_ms i64 = 1000 // how long Back and Start stay down together before an eject
mut:
	armed bool // Back and Start have both been up at once
	since i64 = -1 // when Back and Start went down together, -1 while they are not
}

// step reads the buttons at now_ms, milliseconds on a steady clock, and says whether this tick
// sends a datagram and whether that datagram ejects. gehirn-gamepad calls it once per tick.
pub fn (mut g Guard) step(now_ms i64, lb bool, back bool, start bool) (bool, bool) {
	if !back && !start {
		g.armed = true
	}
	if !g.armed || !back || !start {
		g.since = -1
		return lb, false
	}
	if g.since < 0 {
		g.since = now_ms
	}
	eject := now_ms - g.since >= g.eject_ms
	return lb || eject, eject
}

// rumble is the strength, 0 to 1, of gehirn-gamepad's low and high frequency motors for one feel:
// contact runs both at full, a human's closeness the high one up to three quarters, and strain, as
// a share of vmax, the low one up to half.
pub fn rumble(f lcl.Feel, vmax f64) (f64, f64) {
	if f.contact {
		return 1.0, 1.0
	}
	return 0.5 * share_of(f.strain / vmax), 0.75 * share_of(f.near)
}

// share_of is x within 0 to 1, and 0 for NaN.
fn share_of(x f64) f64 {
	return if x > 0.0 { math.min(x, 1.0) } else { 0.0 }
}

// Pilot is the pilot's end of the plug, for gehirn-gamepad: it seals datagrams for the field
// unit's PLUG_LISTEN and opens the replies listen sends back. It holds the gamepad's socket, so
// net stays inside plug (CONTRIBUTING, Modules 3).
pub struct Pilot {
	id  string
	key []u8
mut:
	conn &net.UdpConn
	buf  []u8 = []u8{len: 1024}
	seq  i64
	last i64 // t_ms of the newest reply taken
}

// dial opens a pilot's socket toward addr, the field unit's PLUG_LISTEN, for the pilot id and key,
// PILOT_KEY's 32 bytes.
pub fn dial(addr string, id string, key []u8) !Pilot {
	if key.len != 32 {
		return error('plug: a pilot key is 32 bytes, not ${key.len}')
	}
	mut conn := net.dial_udp(addr) or {
		return error('plug: cannot dial ${lcl.quoted(addr)}: ${err.msg()}')
	}

	// feel stops at the first read that waits this long, so it holds up gehirn-gamepad's 20 ms
	// tick by about a millisecond.
	conn.set_read_timeout(time.millisecond)
	return Pilot{
		id:   id
		key:  key
		conn: conn
	}
}

// send seals and sends one datagram. Its seq is the wall clock in microseconds, as read_datagram
// expects, and grows by at least one per datagram.
pub fn (mut p Pilot) send(u []f64, eject bool) ! {
	p.seq = math.max(time.now().unix_micro(), p.seq + 1)
	p.conn.write(seal(p.id, u, eject, p.seq, p.key))!
}

// feel is the newest reply waiting on the socket, or none. A reply open_feel refuses is dropped.
// It reads four datagrams at most: the socket takes datagrams from anyone, and junk that arrives
// as fast as feel reads would otherwise hold up gehirn-gamepad's tick for as long as it lasts.
// Each datagram sent draws one reply, so four leave room for a late one beside this tick's.
pub fn (mut p Pilot) feel() ?lcl.Feel {
	mut newest := ?lcl.Feel(none)
	for _ in 0 .. 4 {
		n, _ := p.conn.read(mut p.buf) or { break }
		f := open_feel(p.buf[..n], p.key, p.last) or { continue }
		p.last = f.t_ms
		newest = f
	}
	return newest
}
