// Minimal client for OpenAI compatible chat endpoints: Ollama, llama.cpp server, vLLM.
module oai

import x.json2
import net.http
import time

// Endpoint is one model behind one chat completions URL, as a core or a MAGI unit uses it.
pub struct Endpoint {
pub:
	url       string
	model     string
	key       string
	reasoning string // reasoning_effort sent with every ask; empty sends none
	timeout   time.Duration = 10 * time.second // wall clock deadline for one ask
	ca        string // CA bundle an https server's certificate must chain to; empty fails every https ask
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

// Provider is OpenRouter's provider routing; llama.cpp, Ollama and vLLM ignore the field.
// Unsorted, OpenRouter balances by price, and the cheapest gpt-oss-20b host, Darkbloom, answers
// many json_schema requests at low effort with null content, a fault on every such ballot.
// Sorted by throughput, as the :nitro model suffix does, the fastest hosts go first, which also
// suits a deadline.
// ponytail: one sort for every endpoint; add a per unit variable once a fast host misbehaves too.
struct Provider {
	sort string = 'throughput'
}

// Request is the body of one chat completions call from ask. OpenRouter, llama.cpp, Ollama and
// vLLM 0.22 or newer all read the top level reasoning_effort, and none means no thinking on each
// of them; a reasoning object or chat_template_kwargs is dropped by at least one of them.
struct Request {
	model            string
	messages         []Message
	temperature      f64
	stream           bool
	response_format  Format
	reasoning_effort string @[omitempty]
	provider         Provider
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

// init warms json2 before any thread asks. json2 in V 0.5.2 fills a per type field cache on
// first use without a lock, so threads that ask at once before any earlier ask can panic the
// whole process. Using every type once here, before any thread exists, fills those caches on
// one thread.
// ponytail: a type added to Request or Response must be warmed here too; drop this once json2
// guards its cache.
fn init() {
	_ := json2.encode(Request{
		messages: [Message{}]
	})
	_ := json2.decode[Response]('{"choices":[{"message":{}}]}') or { Response{} }
}

// ask runs one system plus user exchange and returns the JSON object in the reply. The reply
// must arrive within e.timeout, however the time is spent; jev.Endpoint.ask copies this deadline
// and the request limits below. tools/trials.py PARSE_ERRORS counts a ballot that faults with its
// unreadable completion or extract_json's no JSON object as a parse fault.
pub fn (e Endpoint) ask(system string, user string, temperature f64, schema Schema) !string {
	// ponytail: no retry with json_object after an HTTP 400, so an endpoint that rejects
	// json_schema outright faults every ballot; extract_json covers endpoints that ignore it.
	body := json2.encode(Request{
		model:            e.model
		messages:         [Message{
			role:    'system'
			content: system
		}, Message{
			role:    'user'
			content: user
		}]
		temperature:      temperature
		reasoning_effort: e.reasoning
		response_format:  Format{
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
	// V checks no certificate unless validate is set, and loads no system roots, so verify names
	// the bundle. It resends the key on every redirect, to any host, so none is followed.
	// ponytail: stop_receiving_limit ends an abandoned exchange that streams without end, but one
	// that drips under 1 MiB keeps its thread until the server stops; abort from on_progress once
	// the deadline has passed if that ever matters.
	mut req := http.Request{
		method:               .post
		url:                  e.url
		data:                 body
		read_timeout:         i64(e.timeout + time.second)
		write_timeout:        i64(e.timeout + time.second)
		validate:             true
		verify:               e.ca
		allow_redirect:       false
		stop_receiving_limit: 1 << 20
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
// A reply cut off inside a reasoning block has no answer, only drafts.
fn extract_json(s string) !string {
	if s.last_index('<think>') or { -1 } > s.last_index('</think>') or { -1 } {
		return error('no JSON object in reply')
	}
	text := s.all_after('</think>')
	start := text.index('{') or { return error('no JSON object in reply') }
	end := text.last_index('}') or { return error('no JSON object in reply') }
	if end < start {
		return error('no JSON object in reply')
	}
	return text[start..end + 1]
}
