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

struct RetryCase {
	name    string
	replies []string // the status and headers of each reply in turn, or mute for none; the last one repeats
	content string   // the completion every reply carries
	want    string   // the answer, or the fault
	bodies  []string // the body of each request the server received
}

// Known issue 13: an HTTP 429 gets one more ask after its Retry-After, or a second without one,
// as long as the deadline leaves time for it. The first ask goes out byte for byte with the
// schema, and only the retry leaves it out, so OpenRouter may route it to any provider. A retry
// that meets a second 429, a reply without JSON or the deadline is still a fault, a no.
fn test_ask_retries_a_429_once_inside_the_deadline() {
	first := '{"model":"busy","messages":[{"role":"system","content":"system"},{"role":"user","content":"user"}],"temperature":0,"stream":false,"response_format":{"type":"json_schema","json_schema":{"name":"ballot","schema":{"type":"object"}}},"provider":{"sort":"throughput"}}'
	retry := '{"model":"busy","messages":[{"role":"system","content":"system"},{"role":"user","content":"user"}],"temperature":0,"stream":false,"provider":{"sort":"throughput"}}'
	once := [first]
	twice := [first, retry]
	ok := '{"vote": "approve"}'
	cases := [
		RetryCase{'429 then 200 answers', ['429 Too Many Requests\r\nRetry-After: 0', '200 OK'], ok, ok, twice},
		RetryCase{'no Retry-After waits a second', ['429 Too Many Requests', '200 OK'], ok, ok, twice},
		RetryCase{'a second 429 faults', ['429 Too Many Requests\r\nRetry-After: 0'], ok, 'busy: HTTP 429', twice},
		RetryCase{'a Retry-After past the deadline faults at once', [
			'429 Too Many Requests\r\nRetry-After: 30',
			'200 OK',
		], ok, 'busy: HTTP 429', once},
		RetryCase{'a 500 draws no retry', [
			'500 Internal Server Error',
			'200 OK',
		], ok, 'busy: HTTP 500', once},
		RetryCase{'a 200 is asked once', [
			'200 OK',
		], ok, ok, once},
		RetryCase{'a retry answered without JSON faults', [
			'429 Too Many Requests\r\nRetry-After: 0',
			'200 OK',
		], 'I will not.', 'busy: no JSON object in reply', twice},
		RetryCase{'a mute retry faults at the deadline', [
			'429 Too Many Requests\r\nRetry-After: 1',
			'mute',
		], ok, 'busy: no reply within 3000 ms', twice},
	]
	for c in cases {
		// ponytail: l stays open until the test binary exits. Its server thread waits in select
		// on l's descriptor, and a closed one's number goes to the next case's listener, whose
		// requests that thread would then answer with this case's replies. A server that ends
		// itself would let l close.
		mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
		addr := l.addr()!
		asks := chan string{cap: 8}
		replies := c.replies
		body := '{"choices":[{"message":{"content":${json2.encode(c.content)}}}]}'
		spawn fn [mut l, replies, body, asks] () {
			mut held := []&net.TcpConn{}
			for i := 0; true; i++ {
				mut conn := l.accept() or { return }
				mut buf := []u8{len: 65536}
				mut request := ''

				// The JSON body ends the request, so a read that splits it cannot cut the body short.
				for !request.ends_with('}') {
					n := conn.read(mut buf) or { break }
					request += buf[..n].bytestr()
				}
				_ = asks.try_push(request.all_after('\r\n\r\n'))
				head := replies[if i < replies.len { i } else { replies.len - 1 }]
				if head == 'mute' {
					held << conn
					continue
				}
				conn.write_string('HTTP/1.1 ${head}\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}') or {}
				conn.close() or {}
			}
		}()
		e := Endpoint{
			url:     'http://${addr}/v1/chat/completions'
			model:   'busy'
			timeout: 3 * time.second
		}
		sw := time.new_stopwatch()
		got := e.ask('system', 'user', 0.0, Schema{ name: 'ballot', schema: '{"type":"object"}' }) or {
			err.msg()
		}
		assert got == c.want, c.name
		assert sw.elapsed() < e.timeout + 500 * time.millisecond, c.name
		mut bodies := []string{}
		for asks.len > 0 {
			bodies << <-asks
		}
		assert bodies == c.bodies, c.name
	}
}

fn test_retry_after() {
	cases := {
		'0':                             time.Duration(0)
		' 2 ':                           2 * time.second
		'':                              time.second
		'-1':                            time.second
		'1.5':                           time.second
		'9999999':                       time.second
		'Wed, 21 Oct 2026 07:28:00 GMT': time.second
	}
	for s, want in cases {
		assert retry_after(s) == want, s
	}
}
