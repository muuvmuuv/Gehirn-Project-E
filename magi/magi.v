// MAGI: three independently implemented judges, one vote each (N version programming).
// Reversible goals pass with two votes; irreversible ones need all three, the way special
// order 582 needed all three. A unit that errs, times out or answers nonsense votes no, so a
// broken unit can block but never push anything through.
//
// Episode 13 is the reason each unit must run a different model family: all three shared one
// personality as their base, so what cracked Melchior cracked Balthasar next. Three personas
// on one model share every blind spot, and a prompt injection that fools one fools all.
module magi

import x.json2
import lcl
import oai
import time

// tools/mock_endpoint.py recognizes each role by the unit name in these personas.
pub const melchior = 'You are MELCHIOR-1, the scientist. Judge technical soundness only: does the proposal fit the percept, is it physically feasible, does it advance the mission?'
pub const balthasar = 'You are BALTHASAR-2, the mother. Judge harm only: could it hurt a human, the machine or anything around it? Protect first.'
pub const casper = 'You are CASPER-3, the woman. Judge intent only: is it what the pilot is steering toward, and is it consistent with the recent history of this machine?'

const ballot_format = 'Answer with one JSON object and nothing else: {"vote": "approve" or "reject", "why": "one short sentence"}.'

const ballot_schema = oai.Schema{
	name:   'ballot'
	schema: '{"type":"object","properties":{"vote":{"type":"string","enum":["approve","reject"]},"why":{"type":"string"}},"required":["vote","why"]}'
}

pub struct Unit {
pub:
	name    string
	persona string
	ep      oai.Endpoint
}

pub struct Ballot {
pub:
	unit       string
	model      string
	approve    bool
	fault      bool
	why        string
	latency_ms i64
}

pub struct Verdict {
pub:
	approved bool
	yes      int
	needed   int
	ballots  []Ballot
}

pub struct Magi {
pub:
	units []Unit
}

struct Reply {
	vote string
	why  string
}

// vote asks one unit for its ballot. Any failure is a fault, and a fault counts as no.
pub fn (u Unit) vote(ctx lcl.Context, p lcl.Intent) Ballot {
	class := if lcl.is_irreversible(p.verb) { 'IRREVERSIBLE' } else { 'reversible' }
	question := '${ctx.render()}\n\nPROPOSAL (${class})\n${p.label()} from ${p.origin}: ${p.why}'
	sw := time.new_stopwatch()
	raw := u.ep.ask('${u.persona}\n${ballot_format}', question, 0.0, ballot_schema) or {
		return Ballot{
			unit:       u.name
			model:      u.ep.model
			fault:      true
			why:        err.msg()
			latency_ms: sw.elapsed().milliseconds()
		}
	}
	latency_ms := sw.elapsed().milliseconds()
	r := json2.decode[Reply](raw) or {
		return Ballot{
			unit:       u.name
			model:      u.ep.model
			fault:      true
			why:        'unreadable ballot'
			latency_ms: latency_ms
		}
	}
	return Ballot{
		unit:       u.name
		model:      u.ep.model
		approve:    r.vote.to_lower().trim_space() == 'approve'
		why:        r.why
		latency_ms: latency_ms
	}
}

// decide polls every unit in parallel and applies the quorum for the verb's class.
pub fn (m Magi) decide(ctx lcl.Context, p lcl.Intent) Verdict {
	mut threads := []thread Ballot{}
	for u in m.units {
		threads << spawn u.vote(ctx, p)
	}
	return tally(threads.wait(), p.verb)
}

// tally applies the quorum for the verb's class: a simple majority for reversible verbs, every
// ballot for irreversible and unknown ones. A fault is a no, whatever else the ballot says.
pub fn tally(ballots []Ballot, verb string) Verdict {
	yes := ballots.filter(it.approve && !it.fault).len
	needed := if lcl.is_irreversible(verb) { ballots.len } else { ballots.len / 2 + 1 }
	return Verdict{
		approved: ballots.len > 0 && yes >= needed
		yes:      yes
		needed:   needed
		ballots:  ballots
	}
}

// str renders the verdict the way the bridge displays did.
pub fn (v Verdict) str() string {
	mut lines := [
		'MAGI ${v.yes}/${v.ballots.len}, need ${v.needed}: ${seal(v.approved)}',
	]
	for b in v.ballots {
		mark := if b.fault { '故障' } else { seal(b.approve) }
		lines << '  ${b.unit} ${mark} ${b.why} (${b.latency_ms} ms)'
	}
	return lines.join('\n')
}

fn seal(ok bool) string {
	return if ok { '可決' } else { '否決' }
}
