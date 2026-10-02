module zenoh

import rand
import time

// patience bounds how long a test waits for a sample, since a subscription reaches a peer a
// moment after it is declared.
const patience = 3 * time.second

// wait polls sub for a sample until patience runs out.
fn wait(sub &Subscriber) ?Sample {
	deadline := time.now().add(patience)
	for time.now() < deadline {
		if s := sub.try_recv() {
			return s
		}
		time.sleep(5 * time.millisecond)
	}
	return none
}

struct PutCase {
	name       string
	payload    []u8
	attachment []u8
}

fn test_put() {
	mut s := open(Config{})!
	mut sub := s.subscriber('gehirn/test/put', Queue{ cap: 8 })!
	mut publ := s.publisher('gehirn/test/put', Qos{})!
	cases := [
		PutCase{'json with a mac', '{"v":1}'.bytes(), []u8{len: 32, init: u8(index)}},
		PutCase{'no attachment', '{"v":1}'.bytes(), []u8{}},
		PutCase{'empty payload', []u8{}, [u8(1)]},
		PutCase{'binary payload with zero bytes', [u8(0), 255, 0, 10], [u8(0)]},
		PutCase{'payload of 64 KiB', []u8{len: 65536, init: u8(index % 251)}, []u8{len: 32}},
	]
	for c in cases {
		publ.put(c.payload, c.attachment)!
		got := wait(sub) or { panic('${c.name}: no sample') }
		assert got.key == 'gehirn/test/put', c.name
		assert got.payload == c.payload, c.name
		assert got.attachment == c.attachment, c.name
	}
	publ.close()
	sub.close()
	s.close()
}

fn test_a_ring_of_one_keeps_the_newest_sample() {
	mut s := open(Config{})!
	mut sub := s.subscriber('gehirn/test/ring', Queue{ ring: true, cap: 1 })!
	mut publ := s.publisher('gehirn/test/ring', Qos{})!
	for p in ['a', 'b', 'c'] {
		publ.put(p.bytes(), []u8{})!
	}
	got := wait(sub) or { panic('no sample') }
	assert got.payload.bytestr() == 'c'
	assert sub.try_recv() == none
	publ.close()
	sub.close()
	s.close()
}

fn test_two_sessions_link_over_loopback() {
	at := 'tcp/127.0.0.1:${rand.int_in_range(20000, 60000)!}'
	mut hq := open(Config{ listen: [at] })!
	mut field := open(Config{ connect: [at] })!
	mut sub := hq.subscriber('gehirn/test/link', Queue{ cap: 8 })!
	mut publ := field.publisher('gehirn/test/link', Qos{
		congestion: .block
		priority:   .interactive_high
		express:    true
	})!

	// Puts before the subscription reaches the field's session go nowhere, so keep putting.
	deadline := time.now().add(patience)
	mut got := ?Sample(none)
	for time.now() < deadline && got == none {
		publ.put('{"v":1}'.bytes(), [u8(7)])!
		time.sleep(20 * time.millisecond)
		got = sub.try_recv()
	}
	sample := got or { panic('no sample crossed the link') }
	assert sample.payload.bytestr() == '{"v":1}'
	assert sample.attachment == [u8(7)]
	publ.close()
	sub.close()
	field.close()
	hq.close()
}

fn test_publisher() {
	mut s := open(Config{})!
	for key, ok in {
		'gehirn/eva01/goal': true
		'':                  false
		'gehirn//goal':      false
		'gehirn/eva01/':     false
		'/gehirn':           false
	} {
		if mut p := s.publisher(key, Qos{}) {
			assert ok, '${key} accepted'
			p.close()
		} else {
			assert !ok, '${key} refused: ${err}'
		}
	}
	s.close()
}

struct OpenCase {
	name   string
	config Config
	want   string
}

fn test_open() {
	cases := [
		OpenCase{'a listen endpoint that is no locator', Config{
			listen: ['nonsense']
		}, 'zenoh: config rejects listen/endpoints'},
		OpenCase{'a connect endpoint that is no locator', Config{
			connect: ['nonsense']
		}, 'zenoh: config rejects connect/endpoints'},
	]
	for c in cases {
		mut s := open(c.config) or {
			assert err.msg() == c.want, c.name
			continue
		}
		s.close()
		assert false, '${c.name}: opened'
	}
}
