module plug

import crypto.hmac
import crypto.sha256
import math
import lcl

struct UpdateCase {
	name  string
	pilot []f64
	own   []f64
	ratio f64
	rate  f64 = 0.02
	want  f64
}

fn test_update() {
	cases := [
		UpdateCase{
			name:  'idle pilot is skipped'
			pilot: [0.0, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			want:  0.5
		},
		UpdateCase{
			name:  'pilot just under the idle line is skipped'
			pilot: [0.049, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			want:  0.5
		},
		UpdateCase{
			name:  'pilot at the idle line counts'
			pilot: [0.05, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			want:  0.491
		},
		UpdateCase{
			name:  'idle core is skipped'
			pilot: [1.0, 0.0]
			own:   [0.04, 0.0]
			ratio: 0.5
			want:  0.5
		},
		UpdateCase{
			name:  'core at the idle line counts'
			pilot: [1.0, 0.0]
			own:   [0.05, 0.0]
			ratio: 0.5
			want:  0.491
		},
		UpdateCase{
			name:  'agreement moves up at the rate'
			pilot: [1.0, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			want:  0.51
		},
		UpdateCase{
			name:  'a faster rate moves further'
			pilot: [1.0, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			rate:  0.5
			want:  0.75
		},
		UpdateCase{
			name:  'opposite directions move down'
			pilot: [1.0, 0.0]
			own:   [-1.0, 0.0]
			ratio: 0.5
			want:  0.49
		},
		UpdateCase{
			name:  'a right angle scores half'
			pilot: [0.0, 1.0]
			own:   [1.0, 0.0]
			ratio: 0.3
			want:  0.304
		},
		UpdateCase{
			name:  'half the core speed scores half'
			pilot: [0.5, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.9
			want:  0.892
		},
		UpdateCase{
			name:  'twice the core speed scores half'
			pilot: [1.0, 0.0]
			own:   [0.5, 0.0]
			ratio: 0.9
			want:  0.892
		},
		UpdateCase{
			name:  'direction and magnitude multiply'
			pilot: [0.0, 0.5]
			own:   [1.0, 0.0]
			ratio: 0.0
			rate:  1.0
			want:  0.25
		},
	]
	for c in cases {
		mut s := Sync{
			ratio: c.ratio
			rate:  c.rate
		}
		s.update(c.pilot, c.own)
		assert math.abs(s.ratio - c.want) < 1e-12, '${c.name}: ${s.ratio}'
	}
}

fn test_authority() {
	// ratio, threshold, ceiling, authority
	cases := [
		[0.2, 0.3, 0.8, 0.0],
		[0.3, 0.3, 0.8, 0.0],
		[0.65, 0.3, 0.8, 0.4],
		[1.0, 0.3, 0.8, 0.8],
		[1.5, 0.3, 0.8, 0.8],
		[0.5, 0.0, 1.0, 0.5],
		[1.0, 1.0, 0.8, 0.0], // 1 - threshold is 0, so only <= keeps this finite
	]
	for c in cases {
		s := Sync{
			ratio: c[0]
		}
		got := s.authority(c[1], c[2])
		assert math.abs(got - c[3]) < 1e-12, '${c}: ${got}'
	}
}

// shared_datagram is the datagram tools/test_pilot.py makes from the same fields and key, so the plug and
// tools/pilot.py datagram() cannot drift apart.
const shared_datagram = '{"v":1,"seq":1790000000000000,"pilot":"shinji","u":[0.4,0.1],"eject":false}\nfa38345f9bbb948b76b3bf0dd41a3c4e237e7a623a545f68d9a767d164f59133'
const pilot_key = []u8{len: 32, init: u8(index)}
const sent_us = i64(1790000000000000)

// signed is line with its signature under pilot_key, as tools/pilot.py datagram() signs it.
fn signed(line string) []u8 {
	return '${line}\n${hmac.new(pilot_key, line.bytes(), sha256.sum, sha256.block_size).hex()}'.bytes()
}

struct DatagramCase {
	name string
	raw  []u8
	key  []u8 = pilot_key
	last i64
	now  i64 = sent_us
	want string // the error, or empty when the datagram passes
}

fn test_read_datagram() {
	line := '{"v":1,"seq":${sent_us},"pilot":"shinji","u":[0.4,0.1],"eject":false}'
	cases := [
		DatagramCase{
			name: 'the datagram tools/pilot.py makes'
			raw:  shared_datagram.bytes()
		},
		DatagramCase{
			name: 'a datagram as old as the seat lasts'
			raw:  shared_datagram.bytes()
			now:  sent_us + seat_ms * 1000
		},
		DatagramCase{
			name: 'a datagram as far ahead as the seat lasts'
			raw:  shared_datagram.bytes()
			now:  sent_us - seat_ms * 1000
		},
		DatagramCase{
			name: 'the same datagram again'
			raw:  shared_datagram.bytes()
			last: sent_us
			want: 'plug: datagram repeats or precedes the last one accepted'
		},
		DatagramCase{
			name: 'a datagram older than the last one accepted'
			raw:  shared_datagram.bytes()
			last: sent_us + 1
			want: 'plug: datagram repeats or precedes the last one accepted'
		},
		DatagramCase{
			name: 'a datagram older than the seat lasts'
			raw:  shared_datagram.bytes()
			now:  sent_us + seat_ms * 1000 + 1
			want: "plug: datagram more than 500 ms from the plug's clock"
		},
		DatagramCase{
			name: 'a datagram from further ahead than the seat lasts'
			raw:  shared_datagram.bytes()
			now:  sent_us - seat_ms * 1000 - 1
			want: "plug: datagram more than 500 ms from the plug's clock"
		},
		DatagramCase{
			name: 'a datagram under another key'
			raw:  shared_datagram.bytes()
			key:  []u8{len: 32}
			want: 'plug: datagram fails its mac'
		},
		DatagramCase{
			name: 'a plug without a key'
			raw:  shared_datagram.bytes()
			key:  []u8{}
			want: 'plug: no PILOT_KEY to check datagrams with'
		},
		DatagramCase{
			name: 'a datagram with its line changed'
			raw:  shared_datagram.replace('0.4', '0.9').bytes()
			want: 'plug: datagram fails its mac'
		},
		DatagramCase{
			name: 'the unsigned datagram of before'
			raw:  '{"pilot": "shinji", "u": [0.4, 0.1], "eject": false}'.bytes()
			want: 'plug: unsigned datagram'
		},
		DatagramCase{
			name: 'a signature one digit short'
			raw:  shared_datagram[..shared_datagram.len - 1].bytes()
			want: 'plug: unsigned datagram'
		},
		DatagramCase{
			name: 'a signature in capitals'
			raw:  shared_datagram.to_upper().bytes()
			want: 'plug: unsigned datagram'
		},
		DatagramCase{
			name: 'a signed datagram from another pilot'
			raw:  signed(line.replace('shinji', 'rei'))
			want: 'plug: datagram from another pilot'
		},
		DatagramCase{
			name: 'a signed datagram of version 2'
			raw:  signed(line.replace('"v":1', '"v":2'))
			want: 'plug: datagram of another version than 1'
		},
		DatagramCase{
			name: 'a signed datagram cut right after a number'
			raw:  signed(line.all_before(',0.1]'))
			want: 'plug: unreadable datagram'
		},
		DatagramCase{
			name: 'a signed line that is no JSON object'
			raw:  signed('[1]')
			want: 'plug: unreadable datagram'
		},
	]
	for c in cases {
		d := read_datagram(c.raw, c.key, 'shinji', c.last, c.now) or {
			assert err.msg() == c.want, c.name
			continue
		}
		assert c.want == '', c.name
		assert d.u == [0.4, 0.1], c.name
		assert d.seq == sent_us && !d.eject, c.name
	}
}

// The datagram tools/pilot.py makes is the one seal makes for gehirn-gamepad, so the two pilots
// cannot drift apart.
fn test_seal() {
	assert seal('shinji', [0.4, 0.1], false, sent_us, pilot_key) == shared_datagram.bytes()
}

// A reply and a datagram are signed under the same PILOT_KEY. A captured reply fails a datagram's
// mac, and with feel_prefix moved into its line it verifies but reads as no Datagram.
fn test_a_reply_never_reads_as_a_datagram() {
	f := lcl.Feel{
		t_ms:    1790000000000
		contact: true
		near:    0.5
	}
	reply := seal_feel(f, pilot_key).bytestr()
	assert reply.starts_with('{"v":1,"feel":{"t_ms":1790000000000,"contact":true,')
	for c in [[reply, 'plug: datagram fails its mac'],
		[feel_prefix + reply, 'plug: unreadable datagram']] {
		read_datagram(c[0].bytes(), pilot_key, 'shinji', 0, sent_us) or {
			assert err.msg() == c[1]
			continue
		}
		assert false, 'a reply passed as a datagram: ${c[0]}'
	}
}
