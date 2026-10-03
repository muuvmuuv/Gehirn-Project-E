// Entry plug: pilot input and the A10 feel sent back, the synchronization ratio and the flight
// recorder. A core is paired with one pilot, so input from anyone else is dropped at the plug.
// pilot.v holds the pilot's end of the same link, so the link has one door on both sides.
module plug

import crypto.hmac
import crypto.sha256
import encoding.hex
import x.json2
import math
import net
import os
import time
import lcl

// Sync is an exponential moving average of how well the seat and the core agree. main.v's field
// loop keeps one for the pilot and one for the dummy plug. It is the arbitration term of shared
// control: the better they agree, the more the core may steer.
pub struct Sync {
pub mut:
	ratio f64 = 0.5
	rate  f64 = 0.02
}

// update folds one tick in. Idle ticks carry no information and are skipped.
pub fn (mut s Sync) update(pilot []f64, own []f64) {
	np := lcl.norm(pilot)
	nc := lcl.norm(own)
	if np < 0.05 || nc < 0.05 {
		return
	}
	direction := (lcl.dot(pilot, own) / (np * nc) + 1.0) / 2.0
	magnitude := 1.0 - math.abs(np - nc) / math.max(np, nc)
	s.ratio += s.rate * (direction * magnitude - s.ratio)
}

// authority is the core's share of control. At or below the activation threshold the core
// only advises; above it the share grows with sync up to a ceiling, so a seated pilot always
// keeps part of the controls.
pub fn (s Sync) authority(threshold f64, ceiling f64) f64 {
	if s.ratio <= threshold {
		return 0.0
	}
	return ceiling * math.min(1.0, (s.ratio - threshold) / (1.0 - threshold))
}

// seat_ms is how long, in milliseconds, one pilot datagram keeps the seat in main.v's field loop,
// and how far a datagram's seq may lie from the plug's clock before listen drops it as stale.
pub const seat_ms = 500

// Datagram is one pilot datagram's signed JSON line. seal writes it for gehirn-gamepad and
// tools/pilot.py datagram() writes the same fields; plug_test.v test_read_datagram and test_seal
// and tools/test_pilot.py share one datagram.
struct Datagram {
	v     int
	seq   i64 // the pilot's wall clock in microseconds, strictly increasing
	pilot string
	u     []f64
	eject bool
}

// unseal is the line in raw, which ends in a newline and 64 lowercase hex digits of HMAC SHA256
// under key over prefix and that line, for read_datagram without a prefix and open_feel with
// feel_prefix. what names the message in its errors.
fn unseal(raw []u8, key []u8, prefix string, what string) !string {
	i := raw.bytestr().last_index('\n') or { return error('plug: unsigned ${what}') }
	sig := raw[i + 1..].bytestr()
	if sig.len != 64 || !sig.contains_only('0123456789abcdef') {
		return error('plug: unsigned ${what}')
	}
	line := raw[..i].bytestr()
	mac := hmac.new(key, (prefix + line).bytes(), sha256.sum, sha256.block_size)
	if !hmac.equal(hex.decode(sig)!, mac) {
		return error('plug: ${what} fails its mac')
	}
	return line
}

// read_datagram checks one datagram: a JSON line, a newline, and 64 hex digits of HMAC SHA256
// under key over that line. It reads the line only once the HMAC holds, then drops another pilot,
// another version, a seq at or below last, and a seq more than seat_ms from now_us, the plug's
// clock in microseconds, so a replay fails without the plug remembering anything across restarts.
fn read_datagram(raw []u8, key []u8, pilot_id string, last i64, now_us i64) !Datagram {
	if key.len == 0 {
		return error('plug: no PILOT_KEY to check datagrams with')
	}
	line := unseal(raw, key, '', 'datagram')!
	d := json2.decode[Datagram](line) or { return error('plug: unreadable datagram') }
	if d.v != 1 {
		return error('plug: datagram of another version than 1')
	}
	if d.pilot != pilot_id {
		return error('plug: datagram from another pilot')
	}
	if d.seq <= last {
		return error('plug: datagram repeats or precedes the last one accepted')
	}
	if d.seq < now_us - seat_ms * 1000 || d.seq > now_us + seat_ms * 1000 {
		return error('plug: datagram more than ${seat_ms} ms from the plug\'s clock')
	}
	return d
}

// Reply is one A10 reply's JSON line (ADR-0006): the version, then the newest feel.
struct Reply {
	v    int
	feel lcl.Feel
}

// feel_prefix starts the bytes a reply's HMAC covers, so no datagram passes open_feel, though both
// are signed under the same PILOT_KEY. A reply with the prefix moved into its line verifies as a
// datagram, so what keeps a reply out of read_datagram is that its line is no Datagram.
const feel_prefix = 'feel\n'

// seal_feel is the reply listen sends the pilot: a JSON line, a newline, and 64 hex digits of
// HMAC SHA256 under key over feel_prefix and that line. open_feel reads it on the pilot's side.
fn seal_feel(f lcl.Feel, key []u8) []u8 {
	line := json2.encode(Reply{ v: 1, feel: f })
	mac := hmac.new(key, (feel_prefix + line).bytes(), sha256.sum, sha256.block_size)
	return '${line}\n${mac.hex()}'.bytes()
}

// listen takes signed pilot datagrams from the paired pilot, as read_datagram checks them, and
// drops every other datagram without a word. Only the newest command matters, so the channel
// holds one and drops the stale one. It answers every datagram it takes with the newest value
// from feel, sealed by seal_feel and sent back to the datagram's source; main.v's field loop
// drops the stale feel to make room for a new one, so feel holds one.
pub fn listen(addr string, pilot_id string, key []u8, out chan lcl.PilotInput, feel chan lcl.Feel) {
	mut conn := net.listen_udp(addr) or {
		eprintln('plug: cannot listen on ${lcl.quoted(addr)}: ${err}')
		return
	}
	conn.set_read_timeout(net.infinite_timeout)
	mut buf := []u8{len: 1024}
	mut last := i64(0)
	mut newest := lcl.Feel{}
	for {
		n, from := conn.read(mut buf) or { continue }
		d := read_datagram(buf[..n], key, pilot_id, last, time.now().unix_micro()) or { continue }
		last = d.seq
		msg := lcl.PilotInput{
			t_ms:  lcl.now_ms()
			pilot: d.pilot
			u:     d.u
			eject: d.eject
		}
		for out.try_push(msg) != .success {
			mut stale := lcl.PilotInput{}
			_ = out.try_pop(mut stale)
		}
		for feel.try_pop(mut newest) == .success {}

		// Rumble plays no part in safety, so a reply that cannot go out is dropped.
		conn.write_to(from, seal_feel(newest, key)) or {}
	}
}

// Record is one tick of the flight recorder. tools/pilot.py tails the recorder for pose.
pub struct Record {
pub:
	t_ms   i64
	seat   string
	pose   []f64
	target []f64
	u_seat []f64
	u_core []f64
	u_out  []f64
	sync   f64
}

// Recorder writes every tick main.v's field loop hands it. This log is the dummy plug's training
// set, and later the dataset for a real policy, so it exists from the first minute of operation.
pub struct Recorder {
mut:
	f       os.File
	pending int
}

// open_recorder appends to the log at path and creates it if needed.
pub fn open_recorder(path string) !Recorder {
	return Recorder{
		f: os.open_append(path)!
	}
}

// write logs one tick and flushes every 50 ticks, about once a second.
pub fn (mut r Recorder) write(rec Record) {
	r.f.writeln(json2.encode(rec)) or { return }
	r.pending++
	if r.pending >= 50 {
		r.f.flush()
		r.pending = 0
	}
}
