module core

import x.json2
import lcl
import oai

const core_prompt = 'You are the core of a mobile machine. You do not steer; you choose the next goal.
Verbs: goto (target [x, y] in meters), hold (no target), release (drop the payload where you stand; irreversible).
Answer with one JSON object and nothing else: {"verb": "...", "target": [x, y], "why": "one short sentence"}.
Keep well clear of humans. If the pilot is steering somewhere sensible, prefer a goal that agrees with them.'

const proposal_schema = oai.Schema{
	name:   'proposal'
	schema: '{"type":"object","properties":{"verb":{"type":"string","enum":${json2.encode(lcl.known_verbs)}},"target":{"type":"array","items":{"type":"number"}},"why":{"type":"string"}},"required":["verb","why"]}'
}

pub struct LlmCore {
pub:
	ep oai.Endpoint
}

struct Proposal {
	verb   string
	target []f64
	why    string
}

// name identifies the backend in logs and in the journal.
pub fn (c LlmCore) name() string {
	return 'llm:${c.ep.model}'
}

// propose asks the model for the next goal.
pub fn (mut c LlmCore) propose(ctx lcl.Context) !lcl.Intent {
	raw := c.ep.ask(core_prompt, ctx.render(), 0.2, proposal_schema)!
	p := json2.decode[Proposal](raw) or { return error('${c.ep.model}: unreadable proposal') }
	return lcl.Intent{
		verb:   p.verb.to_lower().trim_space()
		target: p.target
		why:    p.why
		origin: c.name()
	}
}

// feedback does nothing: a language core learns from the journal it is shown, not from a signal.
pub fn (mut c LlmCore) feedback(o lcl.Outcome) {}
