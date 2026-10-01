// Minimal client for TypeSafe's System One endpoint, where a model such as Jev answers typed
// questions about a JSON state. Only noul answers are read back.
module jev

import x.json2
import net.http
import time

// Endpoint is one System One model behind one URL, as a MAGI unit uses it.
pub struct Endpoint {
pub:
	url     string
	model   string
	key     string
	timeout time.Duration = 10 * time.second // wall clock deadline for one ask
	ca      string // CA bundle an https server's certificate must chain to; empty fails every https ask
}

// Reply is one evaluation: the model that says it answered, each noul by question id, and usage.
pub struct Reply {
pub:
	model string
	nouls map[string]f64
	usage Usage
}

// Usage is the token count System One reports for one evaluation.
pub struct Usage {
pub:
	input_tokens  int
	output_tokens int
}

struct Answer {
	noul ?f64
}

struct Response {
	model   string
	answers map[string]Answer
	usage   Usage
}

struct Outcome {
	resp http.Response
	err  string
}

// The same json2 cache race as in oai/oai.v init: warm every decoded type before any thread.
fn init() {
	_ := json2.decode[Response]('{"answers":{"q":{"noul":0}},"usage":{"input_tokens":0}}') or {
		Response{}
	}
}

// ask evaluates state, a JSON value, against questions, a JSON object of typed questions. The
// reply must arrive within e.timeout, however the time is spent; oai.Endpoint.ask has the same
// deadline and request limits, and the comments there explain them. Without a key it fails at
// once, since System One answers no request without one.
pub fn (e Endpoint) ask(state string, questions string) !Reply {
	if e.key == '' {
		return error('${e.model}: no API key')
	}
	mut req := http.Request{
		method:               .post
		url:                  e.url
		data:                 '{"model":${json2.encode(e.model)},"state":${state},"questions":${questions}}'
		read_timeout:         i64(e.timeout + time.second)
		write_timeout:        i64(e.timeout + time.second)
		validate:             true
		verify:               e.ca
		allow_redirect:       false
		stop_receiving_limit: 1 << 20
	}
	req.add_header(.content_type, 'application/json')
	req.add_header(.authorization, 'Bearer ${e.key}')
	done := chan Outcome{cap: 1}
	spawn post(req, done)
	mut o := Outcome{}
	select {
		got := <-done {
			o = got
		}
		e.timeout {
			return error('${e.model}: no reply within ${e.timeout.milliseconds()} ms')
		}
	}
	if o.err != '' {
		return error('${e.model}: ${o.err}')
	}

	// ponytail: no retry on 429 or 529, so a rate limited ballot is a fault; add backoff only if
	// one call per deliberation ever meets the limit.
	if o.resp.status_code != 200 {
		return error('${e.model}: HTTP ${o.resp.status_code}')
	}
	return read_reply(o.resp.body) or { error('${e.model}: ${err}') }
}

fn post(req http.Request, done chan Outcome) {
	resp := req.do() or {
		done <- Outcome{
			err: err.msg().all_before('\n')
		}
		return
	}
	done <- Outcome{
		resp: resp
	}
}

// read_reply keeps every answer that carries a noul. json2 reads a missing or null noul as none,
// so such an answer is absent from nouls, and it reads a quoted number as that number.
// tools/trials.py PARSE_ERRORS counts its unreadable reply as a parse fault.
fn read_reply(body string) !Reply {
	r := json2.decode[Response](body) or { return error('unreadable reply') }
	mut nouls := map[string]f64{}
	for id, a in r.answers {
		if n := a.noul {
			nouls[id] = n
		}
	}
	return Reply{
		model: r.model
		nouls: nouls
		usage: r.usage
	}
}
