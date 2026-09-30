// Minimal client for OpenAI compatible chat endpoints: Ollama, llama.cpp server, vLLM.
module oai

import x.json2
import net.http
import time

pub struct Endpoint {
pub:
	url     string
	model   string
	key     string
	timeout time.Duration = 10 * time.second // wall clock deadline for one ask
}

// Schema constrains a reply to a JSON Schema, for endpoints that support structured output.
pub struct Schema {
pub:
	name   string
	schema string // a JSON Schema object as JSON text
}

struct Message {
	role    string
	content string
}

struct Format {
	typ         string @[json: 'type']
	json_schema JsonSchema
}

struct JsonSchema {
	name   string
	schema Verbatim
}

// Verbatim is JSON text that json2 embeds as is, so the schema goes out as an object.
struct Verbatim {
	text string
}

// to_json lets json2 write the text unquoted.
pub fn (v Verbatim) to_json() string {
	return v.text
}

struct Request {
	model           string
	messages        []Message
	temperature     f64
	stream          bool
	response_format Format
}

struct Choice {
	message Message
}

struct Response {
	choices []Choice
}

struct Answer {
	resp http.Response
	err  string
}

// ask runs one system plus user exchange and returns the JSON object in the reply. The reply
// must arrive within e.timeout, however the time is spent.
pub fn (e Endpoint) ask(system string, user string, temperature f64, schema Schema) !string {
	// ponytail: no retry with json_object after an HTTP 400, so an endpoint that rejects
	// json_schema outright faults every ballot; extract_json covers endpoints that ignore it.
	body := json2.encode(Request{
		model:           e.model
		messages:        [Message{
			role:    'system'
			content: system
		}, Message{
			role:    'user'
			content: user
		}]
		temperature:     temperature
		response_format: Format{
			typ:         'json_schema'
			json_schema: JsonSchema{
				name:   schema.name
				schema: Verbatim{
					text: schema.schema
				}
			}
		}
	})
	// The sockets outlast the deadline by a second: at equal values a silent endpoint races the
	// deadline and often reports a socket timeout instead, yet an abandoned exchange still ends.
	mut req := http.Request{
		method:        .post
		url:           e.url
		data:          body
		read_timeout:  i64(e.timeout + time.second)
		write_timeout: i64(e.timeout + time.second)
	}
	req.add_header(.content_type, 'application/json')
	if e.key != '' {
		req.add_header(.authorization, 'Bearer ${e.key}')
	}
	// Capacity 1, so a reply that lands after the deadline never blocks the abandoned thread.
	done := chan Answer{cap: 1}
	spawn post(req, done)
	mut a := Answer{}
	select {
		got := <-done {
			a = got
		}
		e.timeout {
			return error('${e.model}: no reply within ${e.timeout.milliseconds()} ms')
		}
	}
	if a.err != '' {
		return error('${e.model}: ${a.err}')
	}
	resp := a.resp
	if resp.status_code != 200 {
		return error('${e.model}: HTTP ${resp.status_code}')
	}
	r := json2.decode[Response](resp.body) or { return error('${e.model}: unreadable completion') }
	if r.choices.len == 0 {
		return error('${e.model}: empty completion')
	}
	return extract_json(r.choices[0].message.content) or { return error('${e.model}: ${err}') }
}

fn post(req http.Request, done chan Answer) {
	resp := req.do() or {
		done <- Answer{
			err: err.msg().all_before('\n')
		}
		return
	}
	done <- Answer{
		resp: resp
	}
}

// extract_json drops reasoning blocks and code fences that some models wrap around their answer.
fn extract_json(s string) !string {
	text := s.all_after('</think>')
	start := text.index('{') or { return error('no JSON object in reply') }
	end := text.last_index('}') or { return error('no JSON object in reply') }
	if end < start {
		return error('no JSON object in reply')
	}
	return text[start..end + 1]
}
