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
	for bad in ['I would rather not.', '} before {', ''] {
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
