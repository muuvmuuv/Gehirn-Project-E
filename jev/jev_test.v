module jev

import net
import time

fn test_read_reply() {
	r :=
		read_reply('{"model":"jev-1.13.0","answers":{"a":{"type":"noul","noul":0.25},"b":{"type":"noul","noul":1},"c":{"type":"noul"},"d":{"type":"noul","noul":null}},"usage":{"input_tokens":820,"output_tokens":110}}')!
	assert r.model == 'jev-1.13.0'
	assert r.nouls == {
		'a': 0.25
		'b': 1.0
	}
	assert r.usage.input_tokens == 820
	for bad in ['', 'nope', '{"answers":[]}', '{"answers":{"a":{"noul":true}}}',
		'{"answers":{"a":{"noul":"high"}}}', '{"answers":{"a":{"noul":[0.5]}}}'] {
		if got := read_reply(bad) {
			assert false, 'expected an error for ${bad}, got ${got}'
		} else {
			assert err.msg() == 'unreadable reply', bad
		}
	}
}

fn test_ask_gives_up_at_the_deadline() {
	mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
	addr := l.addr()!
	spawn fn [mut l] () {
		mut held := []&net.TcpConn{}
		for {
			held << l.accept() or { return }
		}
	}()
	e := Endpoint{
		url:     'http://${addr}/v1/systemone'
		model:   'jev-1.13.0'
		key:     'test'
		timeout: 300 * time.millisecond
	}
	sw := time.new_stopwatch()
	if got := e.ask('{}', '{}') {
		assert false, 'expected a timeout, got ${got}'
	} else {
		assert err.msg() == 'jev-1.13.0: no reply within 300 ms'
	}
	assert sw.elapsed() < 2 * time.second
}

// A redirect would carry the key to wherever it points.
fn test_ask_follows_no_redirect() {
	mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
	addr := l.addr()!
	spawn fn [mut l, addr] () {
		for {
			mut c := l.accept() or { return }
			mut buf := []u8{len: 65536}
			c.read(mut buf) or {}
			c.write_string('HTTP/1.1 307 Temporary Redirect\r\nLocation: http://${addr}/elsewhere\r\nContent-Length: 0\r\n\r\n') or {}
			c.close() or {}
		}
	}()
	e := Endpoint{
		url:     'http://${addr}/v1/systemone'
		model:   'jev-1.13.0'
		key:     'test'
		timeout: 2 * time.second
	}
	if got := e.ask('{}', '{}') {
		assert false, 'expected a fault, got ${got}'
	} else {
		assert err.msg() == 'jev-1.13.0: HTTP 307'
	}
}

// Without a key nothing is sent, so a missing TYPESAFE_API_KEY faults at once.
fn test_ask_needs_a_key() {
	e := Endpoint{
		url:   'http://127.0.0.1:9/v1/systemone'
		model: 'jev-1.13.0'
	}
	if got := e.ask('{}', '{}') {
		assert false, 'expected a fault, got ${got}'
	} else {
		assert err.msg() == 'jev-1.13.0: no API key'
	}
}
