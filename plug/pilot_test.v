module plug

import crypto.hmac
import crypto.sha256
import math
import net
import time
import lcl

const test_key = []u8{len: 32, init: u8(index)}

// signed_reply is line with its signature under test_key, as seal_feel signs a reply.
fn signed_reply(line string) []u8 {
	mac := hmac.new(test_key, (feel_prefix + line).bytes(), sha256.sum, sha256.block_size)
	return '${line}\n${mac.hex()}'.bytes()
}

struct FeelCase {
	name string
	raw  []u8
	key  []u8 = test_key
	last i64
	want string // the error, or empty when the reply passes
}

fn test_open_feel() {
	sent := lcl.Feel{
		t_ms:    1790000000000
		contact: true
		near:    0.25
		sync:    0.5
		strain:  0.125
	}
	reply := seal_feel(sent, test_key)
	line := reply.bytestr().all_before('\n')
	cases := [
		FeelCase{
			name: 'the reply listen sends'
			raw:  reply
		},
		FeelCase{
			name: 'a reply newer than the last one taken'
			raw:  reply
			last: sent.t_ms - 1
		},
		FeelCase{
			name: 'the same reply again'
			raw:  reply
			last: sent.t_ms
			want: 'plug: reply repeats or precedes the last one taken'
		},
		FeelCase{
			name: 'a reply older than the last one taken'
			raw:  reply
			last: sent.t_ms + 1
			want: 'plug: reply repeats or precedes the last one taken'
		},
		FeelCase{
			name: 'a reply under another key'
			raw:  reply
			key:  []u8{len: 32}
			want: 'plug: reply fails its mac'
		},
		FeelCase{
			name: 'a reply with its line changed'
			raw:  reply.bytestr().replace('0.25', '0.75').bytes()
			want: 'plug: reply fails its mac'
		},
		FeelCase{
			name: 'a datagram, signed without the prefix'
			raw:  seal('shinji', [0.4, 0.1], false, sent.t_ms * 1000, test_key)
			want: 'plug: reply fails its mac'
		},
		FeelCase{
			name: 'a reply without a signature'
			raw:  line.bytes()
			want: 'plug: unsigned reply'
		},
		FeelCase{
			name: 'a signature in capitals'
			raw:  reply.bytestr().to_upper().bytes()
			want: 'plug: unsigned reply'
		},
		FeelCase{
			name: 'a signed reply of version 2'
			raw:  signed_reply(line.replace('"v":1', '"v":2'))
			want: 'plug: reply of another version than 1'
		},
		FeelCase{
			name: 'a signed line that is no JSON object'
			raw:  signed_reply('[1]')
			want: 'plug: unreadable reply'
		},
		FeelCase{
			name: 'a signed reply cut right after a number inside an array'
			raw:  signed_reply('{"v":1,"feel":{"t_ms":1,"x":[0.5')
			want: 'plug: unreadable reply'
		},
		FeelCase{
			name: 'a signed reply without a feel'
			raw:  signed_reply('{"v":1}')
			want: 'plug: reply repeats or precedes the last one taken'
		},
	]
	for c in cases {
		f := open_feel(c.raw, c.key, c.last) or {
			assert err.msg() == c.want, c.name
			continue
		}
		assert c.want == '', c.name
		assert f == sent, c.name
	}
}

struct StickCase {
	name string
	x    f64
	y    f64
	vmax f64 = 1.0
	want []f64
}

fn test_stick() {
	cases := [
		StickCase{'centered', 0.0, 0.0, 1.0, [0.0, 0.0]},
		StickCase{'resting inside the deadzone', 0.1, 0.1, 1.0, [0.0, 0.0]},
		StickCase{'at the deadzone', 0.15, 0.0, 1.0, [0.0, 0.0]},
		StickCase{'half way from the deadzone to the edge', 0.575, 0.0, 1.0, [0.5, 0.0]},
		StickCase{'full right', 1.0, 0.0, 1.0, [1.0, 0.0]},
		StickCase{'full up, which SDL reads as -1', 0.0, -1.0, 1.0, [0.0, 1.0]},
		StickCase{'full down', 0.0, 1.0, 1.0, [0.0, -1.0]},
		StickCase{'SDL reads full left as a hair past -1', -32768.0 / 32767.0, 0.0, 1.0, [
			-1.0, 0.0]},
		StickCase{'a square corner caps at vmax', 1.0, 1.0, 1.0, [
			math.sqrt(0.5), -math.sqrt(0.5)]},
		StickCase{'vmax scales full tilt', 1.0, 0.0, 0.4, [0.4, 0.0]},
		StickCase{'a NaN axis', math.nan(), 0.0, 1.0, [0.0, 0.0]},
	]
	for c in cases {
		got := stick(c.x, c.y, c.vmax)
		assert got.len == 2 && lcl.dist(got, c.want) < 1e-12, '${c.name}: ${got}'
	}
}

// Press is one tick of the buttons and what Guard.step should answer.
struct Press {
	t     i64
	lb    bool
	back  bool
	start bool
	send  bool
	eject bool
}

struct GuardCase {
	name  string
	steps []Press
}

fn test_step() {
	up := Press{}
	cases := [
		GuardCase{'LB held sends', [Press{
			lb:   true
			send: true
		}]},
		GuardCase{'LB let go sends nothing', [up]},
		GuardCase{'Back and Start held a second eject, LB or not', [up, Press{
			t:     10
			back:  true
			start: true
		}, Press{
			t:     1009
			back:  true
			start: true
		}, Press{
			t:     1010
			back:  true
			start: true
			send:  true
			eject: true
		}]},
		GuardCase{'LB keeps steering until the eject', [up, Press{
			t:     10
			lb:    true
			back:  true
			start: true
			send:  true
		}, Press{
			t:     1010
			lb:    true
			back:  true
			start: true
			send:  true
			eject: true
		}]},
		GuardCase{'letting go of Start starts the count over', [up, Press{
			t:     10
			back:  true
			start: true
		}, Press{
			t:    900
			back: true
		}, Press{
			t:     902
			back:  true
			start: true
		}, Press{
			t:     1901
			back:  true
			start: true
		}, Press{
			t:     1902
			back:  true
			start: true
			send:  true
			eject: true
		}]},
		GuardCase{'Back and Start down from the start never eject', [
			Press{
				back:  true
				start: true
			}, Press{
				t:     5000
				back:  true
				start: true
			}]},
		GuardCase{'a stuck Back arms nothing until it comes up', [
			Press{
				back: true
			}, Press{
				t:     10
				back:  true
				start: true
			}, Press{
				t:     2000
				back:  true
				start: true
			}, Press{
				t: 2001
			}, Press{
				t:     2002
				back:  true
				start: true
			}, Press{
				t:     3002
				back:  true
				start: true
				send:  true
				eject: true
			}]},
		GuardCase{'Back alone never ejects', [up, Press{
			t:    10
			back: true
		}, Press{
			t:    5000
			back: true
		}]},
	]
	for c in cases {
		mut g := Guard{}
		for i, s in c.steps {
			send, eject := g.step(s.t, s.lb, s.back, s.start)
			assert send == s.send && eject == s.eject, '${c.name}, step ${i}: send ${send} eject ${eject}'
		}
	}
}

struct RumbleCase {
	name string
	f    lcl.Feel
	vmax f64 = 1.0
	low  f64
	high f64
}

fn test_rumble() {
	cases := [
		RumbleCase{
			name: 'nothing to feel'
		},
		RumbleCase{
			name: 'contact runs both motors at full'
			f:    lcl.Feel{
				contact: true
			}
			low:  1.0
			high: 1.0
		},
		RumbleCase{
			name: 'contact outweighs everything else'
			f:    lcl.Feel{
				contact: true
				near:    1.0
				strain:  3.0
			}
			low:  1.0
			high: 1.0
		},
		RumbleCase{
			name: 'a human halfway in'
			f:    lcl.Feel{
				near: 0.5
			}
			high: 0.375
		},
		RumbleCase{
			name: 'a human at human_stop'
			f:    lcl.Feel{
				near: 1.0
			}
			high: 0.75
		},
		RumbleCase{
			name: 'strain of half vmax'
			f:    lcl.Feel{
				strain: 0.5
			}
			low:  0.25
		},
		RumbleCase{
			name: 'strain past vmax'
			f:    lcl.Feel{
				strain: 2.0
			}
			low:  0.5
		},
		RumbleCase{
			name: 'strain counts against vmax'
			f:    lcl.Feel{
				strain: 0.2
			}
			vmax: 0.4
			low:  0.25
		},
		RumbleCase{
			name: 'a NaN feels like nothing'
			f:    lcl.Feel{
				near:   math.nan()
				strain: math.nan()
			}
		},
	]
	for c in cases {
		low, high := rumble(c.f, c.vmax)
		assert math.abs(low - c.low) < 1e-12 && math.abs(high - c.high) < 1e-12, '${c.name}: ${low} ${high}'
	}
}

fn test_dial_refuses_a_short_key() {
	dial('127.0.0.1:7777', 'shinji', []u8{len: 16}) or {
		assert err.msg() == 'plug: a pilot key is 32 bytes, not 16'
		return
	}
	assert false, 'dialed with a 16 byte key'
}

// A datagram from the pilot's end draws a reply from listen with the newest feel, after listen
// has handed the input on, and the pilot's end opens it.
fn test_listen_answers_the_pilot_with_the_newest_feel() {
	mut taken := net.listen_udp('127.0.0.1:0')!
	addr := net.addr_from_socket_handle(taken.sock.handle).str()
	taken.close()!
	out := chan lcl.PilotInput{cap: 1}
	feel := chan lcl.Feel{cap: 1}
	feel <- lcl.Feel{
		t_ms: 1
		near: 0.25
	}
	spawn listen(addr, 'shinji', test_key, out, feel)
	mut p := dial(addr, 'shinji', test_key)!

	// listen may not be bound yet when the first datagram goes out.
	for _ in 0 .. 100 {
		p.send([0.4, 0.1], false)!
		f := p.feel() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		assert f == lcl.Feel{
			t_ms: 1
			near: 0.25
		}
		mut got := lcl.PilotInput{}
		assert out.try_pop(mut got) == .success
		assert got.pilot == 'shinji' && got.u == [0.4, 0.1] && !got.eject
		return
	}
	assert false, 'no reply within a second'
}

// flood sends junk to addr until until, as anyone who can reach the gamepad's port can.
fn flood(addr string, until time.Time) {
	mut c := net.dial_udp(addr) or { return }
	junk := []u8{len: 40, init: `x`}
	for time.now() < until {
		c.write(junk) or {}
	}
	c.close() or {}
}

// Junk that arrives faster than feel reads it still lets feel return within milliseconds, so a
// flood cannot stall gehirn-gamepad's tick.
fn test_feel_returns_under_a_flood() {
	mut p := dial('127.0.0.1:7777', 'shinji', test_key)!
	port := net.addr_from_socket_handle(p.conn.sock.handle).port()!
	t := spawn flood('127.0.0.1:${port}', time.now().add(500 * time.millisecond))
	time.sleep(50 * time.millisecond)
	sw := time.new_stopwatch()
	if f := p.feel() {
		assert false, 'junk passed as a feel: ${f}'
	}
	took := sw.elapsed()
	t.wait()
	assert took < 50 * time.millisecond, 'feel took ${took}'
}
