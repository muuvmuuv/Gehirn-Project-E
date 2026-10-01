module oai

import net
import time
import x.json2

fn test_extract_json() {
	cases := [
		['<think>maybe {"vote": "reject"} or not</think>{"vote": "approve"}', '{"vote": "approve"}'],
		['```json\n{"verb": "hold"}\n```', '{"verb": "hold"}'],
		['Sure, here it is: {"a": {"b": 1}} Hope that helps!', '{"a": {"b": 1}}'],
		['stray } then {"a": 1}', '{"a": 1}'],
	]
	for c in cases {
		assert extract_json(c[0])! == c[1]
	}
	for bad in ['I would rather not.', '} before {', '', '<think>draft {"vote": "approve"} but',
		'<think>a</think>{"vote": "reject"}<think>maybe {"vote": "approve"}'] {
		if got := extract_json(bad) {
			assert false, 'expected an error for ${bad}, got ${got}'
		} else {
			assert err.msg().contains('no JSON object')
		}
	}
}

fn test_schema_is_sent_as_an_object() {
	body := json2.encode(Format{
		typ:         'json_schema'
		json_schema: JsonSchema{
			name:   'ballot'
			schema: Verbatim{
				text: '{"type":"object"}'
			}
		}
	})
	assert body == '{"type":"json_schema","json_schema":{"name":"ballot","schema":{"type":"object"}}}'
}

fn test_reasoning_effort_is_sent_only_when_set() {
	cases := {
		'':     '{"model":"m","messages":[],"temperature":0,"stream":false,"response_format":{"type":"","json_schema":{"name":"","schema":{}}},"provider":{"sort":"throughput"}}'
		'none': '{"model":"m","messages":[],"temperature":0,"stream":false,"response_format":{"type":"","json_schema":{"name":"","schema":{}}},"reasoning_effort":"none","provider":{"sort":"throughput"}}'
	}
	for effort, want in cases {
		assert json2.encode(Request{
			model:            'm'
			response_format:  Format{
				json_schema: JsonSchema{
					schema: Verbatim{'{}'}
				}
			}
			reasoning_effort: effort
		}) == want
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
		url:     'http://${addr}/v1/chat/completions'
		model:   'mute'
		timeout: 300 * time.millisecond
	}
	sw := time.new_stopwatch()
	if got := e.ask('system', 'user', 0.0, Schema{ name: 'ballot', schema: '{}' }) {
		assert false, 'expected a timeout, got ${got}'
	} else {
		assert err.msg() == 'mute: no reply within 300 ms'
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
		url:     'http://${addr}/v1/chat/completions'
		model:   'moved'
		timeout: 2 * time.second
	}
	if got := e.ask('system', 'user', 0.0, Schema{ name: 'ballot', schema: '{}' }) {
		assert false, 'expected a fault, got ${got}'
	} else {
		assert err.msg() == 'moved: HTTP 307'
	}
}
