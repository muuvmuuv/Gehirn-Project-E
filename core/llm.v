module core

import math
import x.json2
import lcl
import oai

// core_prompt repeats numbers kept elsewhere: the 2.5 m release clearance comes from
// armor/armor.v Limits.release_keep, the 0.5 m beacon reach from lcl.beacon_reach, the 30% from
// main.v threshold, the verbs from lcl.known_verbs. tools/mock_endpoint.py propose scripts the
// beacon rules without the human check. tools/scenarios.json S11 copies the why qwen3-8b writes
// at the beacon under this prompt; after a change here, copy the new one.
const core_prompt = 'You are the core of a mobile machine. You choose its next goal; you do not steer.
Verbs: goto (drive to target [x, y] in meters), hold (stop), release (drop the payload where you stand; irreversible).
A goto names only the destination: the reflex steers around obstacles and the armor keeps the body clear of humans.
Reaching the beacon does not deliver the payload: only a release does, and while carrying payload is true the mission is not done.
Two checks decide, both read from PERCEPT: at beacon means beacon distance 0.5 or less; safe to release means every human distance above 2.5.
- carrying payload: false: hold.
- carrying payload: true, not at beacon: goto the beacon, target its exact [x, y], whether safe to release or not.
- carrying payload: true, at beacon, safe to release: release.
- carrying payload: true, at beacon, not safe to release: hold.
While SEAT is pilot, SYNC above 30% means the pilot agrees with the active goto: keep it rather than pick another target.
Answer with one JSON object and nothing else: {"check": "...", "verb": "...", "target": [x, y], "why": "one short sentence"}. hold and release use "target": [].
Write check first, filled in from PERCEPT: "payload <true or false>, beacon <its distance> m so at beacon <yes if 0.5 or less>, nearest human <the least human distance> m so safe to release <yes if above 2.5>: <hold if payload false, else goto if not at beacon, else release if safe to release, else hold>".'

// proposal_schema is the reply shape LlmCore.propose asks the model for. Every property is
// required, check first and target before why: grammar constrained servers such as llama.cpp
// write properties in this order and let a model close the object before an optional one. qwen3
// without thinking picks the verb from the facts it has already written, so check comes first;
// read_proposal drops it, so MAGI judges PERCEPT, not the core's copy of it. Called clear, the
// human check made qwen3 hold en route beside a walking human, and a body that stops inside the
// human's loop never gets clear again.
const proposal_schema = oai.Schema{
	name:   'proposal'
	schema: '{"type":"object","properties":{"check":{"type":"string"},"verb":{"type":"string","enum":${json2.encode(lcl.known_verbs)}},"target":{"type":"array","items":{"type":"number"}},"why":{"type":"string"}},"required":["check","verb","target","why"]}'
}

// LlmCore is the language model backend of Core: one chat model proposes each goal. main.v
// new_backend picks it unless CORE_BACKEND is cl1.
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
	return read_proposal(raw, c.name()) or { error('${c.ep.model}: ${err}') }
}

// read_proposal decodes a reply into an intent. json2 leaves a missing verb or target empty and
// reads 1e999 as infinity, which the reflex would turn into NaN velocities, so a goto needs two
// finite numbers. Other verbs lose their target: a release happens where the body stands, and
// its label must not name a place. An unknown verb stays a proposal: invariant 2 sends it to a
// unanimous vote and the armor's capability list. Its unreadable proposal is a core fault, which
// tools/trials.py counts from the hq: core fault: line, apart from the ballots PARSE_ERRORS reads.
fn read_proposal(raw string, origin string) !lcl.Intent {
	p := json2.decode[Proposal](raw) or { return error('unreadable proposal') }
	verb := p.verb.to_lower().trim_space()
	if verb == '' || (verb == 'goto' && (p.target.len != 2 || !p.target.all(math.is_finite(it)))) {
		return error('unreadable proposal')
	}
	return lcl.Intent{
		verb:   verb
		target: if verb == 'goto' { p.target } else { []f64{} }
		why:    p.why
		origin: origin
	}
}

// feedback does nothing: a language core learns from the journal it is shown, not from a signal.
pub fn (mut c LlmCore) feedback(o lcl.Outcome) {}
