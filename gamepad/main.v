// gehirn-gamepad: a game controller as the pilot's controls, and the A10 back channel as its
// rumble (ADR-0006). It runs on the pilot's machine, reads the controller through SDL2 at 50 Hz
// and sends the plug signed datagrams, as tools/pilot.py does, while LB is held; Back and Start
// held for a second eject. Each datagram draws a reply with what the pilot should feel, and the
// gamepad turns it into rumble. It holds no body and no key that approves or pulses.
module main

import encoding.hex
import os
import strconv
import time
import armor
import lcl
import plug

const tick = 20 * time.millisecond

// rumble_ms is how long one rumble request lasts, so rumble fades once replies stop (ADR-0006).
const rumble_ms = u32(100)

fn main() {
	args := os.args[1..]
	if args.len > 1 || (args.len == 1 && args[0] != '--probe') {
		eprintln('gehirn-gamepad: argument is ${lcl.quoted(args.join(' '))}, not a known value; accepted --probe, or none to fly')
		exit(2)
	}
	sdl_start() or {
		eprintln('gehirn-gamepad: ${err.msg()}')
		exit(1)
	}
	if args.len == 1 {
		names := controllers()
		println('gamepad: ${names.len} controllers')
		for i, name in names {
			println('gamepad: ${i} ${lcl.quoted(name)}')
		}
		sdl_quit()
		return
	}
	id := env('PILOT_ID', 'shinji')
	addr := plug_addr() or {
		eprintln('gehirn-gamepad: ${err.msg()}')
		exit(2)
	}
	key := pilot_key() or {
		eprintln('gehirn-gamepad: ${err.msg()}')
		exit(2)
	}
	mut pilot := plug.dial(addr, id, key) or {
		eprintln('gehirn-gamepad: cannot dial PLUG_ADDR; ${err.msg()}')
		exit(1)
	}
	println('gamepad: pilot ${lcl.quoted(id)} to ${lcl.quoted(addr)}; hold LB to keep the seat, hold Back and Start for a second to eject')
	fly(mut pilot, armor.Limits{}.v_max)
}

fn env(key string, fallback string) string {
	val := os.getenv(key)
	return if val == '' { fallback } else { val }
}

// plug_addr reads PLUG_ADDR as host:port. vlib would take a value without a colon as a Unix socket
// path and a port that is no number as 0 (Known issue 18), and every datagram would vanish.
fn plug_addr() !string {
	addr := env('PLUG_ADDR', '127.0.0.1:7777')
	port := addr.all_after_last(':')
	n := if addr.contains(':') && port.len <= 5 && port.contains_only('0123456789') {
		strconv.atoi(port) or { 0 }
	} else {
		0
	}
	if n < 1 || n > 65535 {
		return error('PLUG_ADDR is ${lcl.quoted(addr)}, not host:port with a port from 1 to 65535')
	}
	return addr
}

// pilot_key reads PILOT_KEY, 64 hex digits, as 32 bytes, checked as gehirn's wire.decode_key
// checks it, which the gamepad cannot import without linking zenoh-c. Its refusal never shows the
// value, which is a key.
fn pilot_key() ![]u8 {
	val := os.getenv('PILOT_KEY')
	if val.len != 64 || !val.contains_only('0123456789abcdefABCDEF') {
		return error("PILOT_KEY is unset or not 64 hex digits; use the field unit's")
	}
	return hex.decode(val)!
}

// fly is the gamepad's 50 Hz loop: read the controller, let the guard decide whether to send and
// whether to eject, send, and rumble with each reply. Full tilt asks for vmax, the armor's manned
// cap. It prints one status line a second and runs until the process ends.
fn fly(mut pilot plug.Pilot, vmax f64) {
	mut guard := plug.Guard{}
	mut pad := Pad{}
	mut feel := lcl.Feel{}
	mut lb := 'LB let go'
	mut u := [0.0, 0.0]
	mut sent := 0
	mut lost := 0
	mut replies := 0
	mut last_status := i64(0)
	mut deadline := time.sys_mono_now()
	for {
		now_ms := i64(time.sys_mono_now() / 1_000_000)
		pump()
		if pad.is_open() && !pad.attached() {
			println('gamepad: ${lcl.quoted(pad.name)} unplugged')
			pad.close()
			pad = Pad{}
		}
		if !pad.is_open() {
			pad = open_pad()
			if pad.is_open() {
				// Every controller shows Back and Start up before it can eject.
				guard = plug.Guard{}
				println('gamepad: ${lcl.quoted(pad.name)} plugged in')
			}
		}
		if pad.is_open() {
			send, eject := guard.step(now_ms, pad.pressed(.leftshoulder), pad.pressed(.back),
				pad.pressed(.start))
			u = if eject { [0.0, 0.0] } else { plug.stick(pad.axis(.leftx), pad.axis(.lefty), vmax) }
			lb = if eject {
				'ejecting'
			} else if send {
				'LB held'
			} else {
				'LB let go'
			}
			if send {
				sent++

				// A lost datagram costs one tick; the seat outlasts 25 of them.
				pilot.send(u, eject) or { lost++ }
			}
		}
		if f := pilot.feel() {
			feel = f
			replies++
			if pad.is_open() {
				low, high := plug.rumble(f, vmax)
				pad.rumble(low, high, rumble_ms)
			}
		}
		if now_ms - last_status >= 1000 && !pad.is_open() {
			last_status = now_ms
			println('gamepad: no controller; plug one in')
		} else if now_ms - last_status >= 1000 {
			last_status = now_ms
			sync_pct := feel.sync * 100.0
			felt := if replies == 0 {
				'no feel'
			} else {
				'contact ${feel.contact}, near ${feel.near:.2f}, sync ${sync_pct:.0f}%, strain ${feel.strain:.2f} m/s'
			}
			println('gamepad: ${lb}, u (${u[0]:.2f}, ${u[1]:.2f}), ${sent} sent, ${lost} lost, ${replies} replies; ${felt}')
			sent, lost, replies = 0, 0, 0
		}
		deadline += u64(tick)
		now := time.sys_mono_now()
		if deadline > now {
			time.sleep(time.Duration(deadline - now))
		} else {
			deadline = now
		}
	}
}
