// Entry plug: pilot input, the synchronization ratio and the flight recorder.
// A core is paired with one pilot, so input from anyone else is dropped at the plug.
module plug

import x.json2
import math
import net
import os
import lcl

// Sync is an exponential moving average of how well the seat and the core agree. It is the
// arbitration term of shared control: the better they agree, the more the core may steer.
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

struct Wire {
	pilot string
	u     []f64
	eject bool
}

// listen takes pilot datagrams such as {"pilot": "shinji", "u": [0.4, 0.1], "eject": false}.
// Only the newest command matters, so the channel holds one and drops the stale one.
pub fn listen(addr string, pilot_id string, out chan lcl.PilotInput) {
	mut conn := net.listen_udp(addr) or {
		eprintln('plug: cannot listen on ${addr}: ${err}')
		return
	}
	conn.set_read_timeout(net.infinite_timeout)
	mut buf := []u8{len: 1024}
	for {
		n, _ := conn.read(mut buf) or { continue }
		w := json2.decode[Wire](buf[..n].bytestr()) or { continue }
		if w.pilot != pilot_id {
			continue
		}
		msg := lcl.PilotInput{
			t_ms:  lcl.now_ms()
			pilot: w.pilot
			u:     w.u
			eject: w.eject
		}
		for out.try_push(msg) != .success {
			mut stale := lcl.PilotInput{}
			_ = out.try_pop(mut stale)
		}
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

// Recorder writes every tick. This log is the dummy plug's training set, and later the
// dataset for a real policy, so it exists from the first minute of operation.
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
