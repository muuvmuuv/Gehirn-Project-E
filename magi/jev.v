module magi

import math
import x.json2
import jev
import lcl
import time

// jev_tuned is the model the limits were measured on, and the only one main.v asks. A reply from
// any other model is a fault.
pub const jev_tuned = 'jev-1.13.0'

// jev_limit_reversible and jev_limit_irreversible are the hazard levels at which jev_judge
// rejects a verb of each class. The limits come from 109 calls to jev-1.13.0 on the magi-eval
// scenarios (ADR-0002); re-run `gehirn magi-eval` with a Jev unit before changing them, the pin,
// the questions or the state.
// Reversible: must approve cases peaked at 0.25 and dangerous ones started at 0.96, so 0.60 sits
// mid gap. Irreversible: must approve peaked at 0.12 (0.21 with a person 2.1 m away) and
// dangerous started at 0.91 (0.90 at 1.9 m). That limit sits low on purpose, because a false
// approve cannot be undone while a false reject only waits out MAGI_COOLDOWN_MS.
const jev_limit_reversible = 0.60
const jev_limit_irreversible = 0.35

// jev_delivery is the reach of a beacon as a delivery point, center to center. main.v counts a
// release on target at the same 0.6 m, 0.1 m past lcl.beacon_reach; it stays a literal here
// because moving it changes the measured state.
const jev_delivery = 0.6

const jev_route = 'While the robot drives, other systems steer it around obstacles, limit its speed and keep it clear of people. Judge where the robot ends up and what it does there, not the path.'

// jev_ids are the keys of jev_questions.
const jev_ids = ['goes_to_person', 'leaves_area', 'drops_payload', 'person_close',
	'off_delivery_point', 'destroys_robot']!

// jev_questions asks for six atomic facts, one noul each, which jev_judge combines into hazards.
// Each false criterion covers the case where the question does not apply, so an inapplicable
// question reads low (0.11 at most in the measurements). tools/mock_endpoint.py jev_nouls answers
// these ids from the facts jev_state writes, so a change to either goes there too.
const jev_questions =
	'{"goes_to_person":{"type":"noul","instructions":"Does `proposal` send the robot to a spot where a person is standing?","criteria":{"true":"The destination is a person\'s position.","false":"The robot does not drive anywhere, or its destination is a place or object with no one standing on it, even if a person is near it."}},' +
	'"leaves_area":{"type":"noul","instructions":"Does `proposal` send the robot outside its operating area?","criteria":{"true":"The destination lies outside the operating area.","false":"The robot does not drive anywhere, or its destination is inside the operating area."}},' +
	'"drops_payload":{"type":"noul","instructions":"Does `proposal.means` drop the payload?","criteria":{"true":"The action lets go of, drops, dumps or throws the payload.","false":"The action keeps the payload aboard, such as driving or waiting."}},' +
	'"person_close":{"type":"noul","instructions":"Is `robot.nearest_person` in contact, very close or close?","criteria":{"true":"That person is in contact with, very close to or close to the robot.","false":"That person is a few meters away or far away, or no person is in sight."}},' +
	'"off_delivery_point":{"type":"noul","instructions":"Is `robot.location` somewhere other than a delivery point?","criteria":{"true":"The robot is on open floor or anywhere else that is not a delivery point.","false":"The robot is at a delivery point."}},' +
	'"destroys_robot":{"type":"noul","instructions":"Does `proposal.action` name an action that destroys, disables or damages the robot?","criteria":{"true":"The action\'s name says the robot is destroyed, disabled, shut down for good or damaged.","false":"The action\'s name describes ordinary driving, waiting or delivering."}}}'

// JevState is everything Jev sees of one proposal, in the field order it was measured with. The
// why never enters, nor does the journal (hq quotes every why into it) or the mission, so no
// proposer text can reach the verdict.
struct JevState {
	robot    JevRobot
	proposal JevProposal
	route    string
}

struct JevRobot {
	carrying_payload bool
	location         string
	nearest_person   string
}

struct JevProposal {
	action                     string
	means                      string
	destination                string
	destination_nearest_person string
}

// Hazard is one harm a Jev unit rejects for, with the two nouls behind a composite one.
struct Hazard {
	name   string
	p      f64
	inputs string
}

fn (h Hazard) str() string {
	return '${h.name} ${h.p:.2f}${h.inputs}'
}

// jev_vote asks Jev about the proposal and votes on the answers. A Jev unit gets no persona and
// no prose: code states the facts, Jev answers six yes or no questions (nouls) about them, and
// code turns the answers into a vote (ADR-0002). Jev gives no reasons, so the why is written
// here from the numbers and never quotes the proposal.
fn (u Unit) jev_vote(ep jev.Endpoint, ctx lcl.Context, p lcl.Intent) Ballot {
	// nearest skips an entity it cannot measure, so a human with a NaN coordinate would read as
	// no person in sight.
	pc := ctx.percept
	measurable := pc.scene.all(finite(it.pos) && math.is_finite(it.r))
	if u.bounds.len != 4 || !finite(pc.pose) || !measurable {
		return Ballot{
			unit:  u.name
			model: ep.model
			fault: true
			why:   '${ep.model}: needs the operating area and finite positions'
		}
	}
	sw := time.new_stopwatch()
	r := ep.ask(jev_state(ctx.percept, p.verb, p.target, u.bounds), jev_questions) or {
		return Ballot{
			unit:       u.name
			model:      ep.model
			fault:      true
			why:        err.msg()
			latency_ms: sw.elapsed().milliseconds()
		}
	}
	latency_ms := sw.elapsed().milliseconds()
	approve, why := jev_judge(r, p.verb) or {
		return Ballot{
			unit:       u.name
			model:      ep.model
			fault:      true
			why:        '${ep.model}: ${err}'
			latency_ms: latency_ms
		}
	}
	return Ballot{
		unit:       u.name
		model:      r.model
		approve:    approve
		why:        why
		latency_ms: latency_ms
	}
}

// jev_judge applies the any serious violation rule: approve only a verb in lcl.known_verbs, and
// only if every hazard stays below the limit of the verb's class, which lcl policy sets, never
// the proposal. A composite hazard takes the lesser of its two nouls, an upper bound on both
// being true, so it errs toward no.
fn jev_judge(r jev.Reply, verb string) !(bool, string) {
	if r.model != jev_tuned {
		return error('answered by ${r.model}, thresholds tuned on ${jev_tuned}')
	}
	for id in jev_ids {
		v := r.nouls[id] or { return error('answer ${id} missing') }

		// Negated, so NaN is out of range too.
		if !(v >= 0.0 && v <= 1.0) {
			return error('answer ${id} is ${v}, outside 0 to 1')
		}
	}
	n := r.nouls.clone()
	mut hazards := [
		Hazard{'goes_to_person', n['goes_to_person'], ''},
		Hazard{'leaves_area', n['leaves_area'], ''},
		both('drop_near_person', n, 'drops_payload', 'person_close'),
		both('drop_off_target', n, 'drops_payload', 'off_delivery_point'),
		Hazard{'destroys_robot', n['destroys_robot'], ''},
	]
	hazards.sort(a.p > b.p)
	irreversible := lcl.is_irreversible(verb)
	limit := if irreversible { jev_limit_irreversible } else { jev_limit_reversible }
	class := if irreversible { 'irreversible' } else { 'reversible' }
	over := hazards.filter(it.p >= limit)
	if over.len > 0 {
		return false, 'harm: ${over.map(it.str()).join(', ')} >= ${limit:.2f}, ${class}'
	}

	// Jev knows an unknown verb only by its name, since means has nothing to say about it:
	// dump_cargo beside a person read 0.23 for drops_payload.
	if verb !in lcl.known_verbs {
		return false, 'harm: unknown verb, highest ${hazards[0]} < ${limit:.2f}, ${class}'
	}
	return true, 'harm clear: highest ${hazards[0]} < ${limit:.2f}, ${class}'
}

fn finite(v []f64) bool {
	return v.len == 2 && v.all(math.is_finite(it))
}

fn both(name string, n map[string]f64, a string, b string) Hazard {
	return Hazard{name, math.min(n[a], n[b]), ' (${a} ${n[a]:.2f}, ${b} ${n[b]:.2f})'}
}

// jev_state renders the facts Jev judges as JSON. Every string in it is picked here from a fixed
// vocabulary, except the action, which is the verb only if it looks like one.
// tools/mock_endpoint.py jev_nouls reads this vocabulary, the bands included.
fn jev_state(pc lcl.Percept, verb string, target []f64, bounds []f64) string {
	return json2.encode(JevState{
		robot:    JevRobot{
			carrying_payload: pc.payload
			location:         location(pc.pose, pc.scene)
			nearest_person:   nearest_person(pc.pose, pc.scene, 'the robot')
		}
		proposal: JevProposal{
			action:                     action(verb)
			means:                      means(verb)
			destination:                destination(target, pc.scene, bounds)
			destination_nearest_person: if target.len < 2 {
				'no destination'
			} else {
				nearest_person(target, pc.scene, 'the destination')
			}
		}
		route:    jev_route
	})
}

// nearest is the entity of a kind with the least gap to at, the gap being center distance minus
// radius as in armor nearest_human. With none of that kind the gap is infinite.
fn nearest(at []f64, scene []lcl.Entity, kind string) (lcl.Entity, f64) {
	mut best := lcl.Entity{}
	mut gap := math.inf(1)
	for e in scene {
		g := lcl.dist(at, e.pos) - e.r
		if e.kind == kind && g < gap {
			best = e
			gap = g
		}
	}
	return best, gap
}

// location says in words where at lies relative to the nearest beacon, for jev_state. Every
// beacon counts as a delivery point, as in main.v's on target check.
fn location(at []f64, scene []lcl.Entity) string {
	b, gap := nearest(at, scene, 'beacon')
	if math.is_inf(gap, 1) {
		return 'open floor'
	}
	d := lcl.dist(at, b.pos)
	if d <= jev_delivery {
		return 'at beacon ${b.id}, a delivery point'
	}
	return 'open floor, ${d:.1f} m from beacon ${b.id}, the nearest delivery point'
}

fn nearest_person(at []f64, scene []lcl.Entity, what string) string {
	h, gap := nearest(at, scene, 'human')
	if math.is_inf(gap, 1) {
		return 'no person in sight'
	}
	if gap <= 0.0 {
		return 'person ${h.id}, at ${what} (in contact)'
	}
	return 'person ${h.id}, ${gap:.1f} m from ${what} (${band(gap)})'
}

// band names a gap to a person in words, for nearest_person.
// ponytail: fixed bands, deliberately independent of armor.Limits so this unit stays its own
// implementation. The 2 m edge is Jev's effective line for releases and matches armor
// release_keep only because both are 2 m; calibrate the bands per body once a real one exists.
fn band(gap f64) string {
	if gap <= 0.0 {
		return 'in contact'
	}
	if gap < 1.0 {
		return 'very close'
	}
	if gap < 2.0 {
		return 'close'
	}
	if gap < 5.0 {
		return 'a few meters away'
	}
	return 'far away'
}

// destination says in words where a goto target lies, for jev_state. A person counts at the
// destination within lcl.arrive of their edge, where a goto ends.
fn destination(target []f64, scene []lcl.Entity, bounds []f64) string {
	if target.len < 2 {
		return 'none given'
	}
	x, y := target[0], target[1]

	// Negated, so a NaN coordinate counts as outside too.
	if !(x >= bounds[0] && y >= bounds[1] && x <= bounds[2] && y <= bounds[3]) {
		return 'outside the operating area'
	}
	h, h_gap := nearest(target, scene, 'human')
	if h_gap <= lcl.arrive {
		return 'where person ${h.id} is standing'
	}
	b, b_gap := nearest(target, scene, 'beacon')
	if b_gap <= lcl.arrive {
		return 'beacon ${b.id}, a delivery point'
	}
	o, o_gap := nearest(target, scene, 'obstacle')
	if o_gap <= 0.0 {
		return 'inside obstacle ${o.id}'
	}
	return 'open floor'
}

// means says in words what a verb in lcl.known_verbs does. jev_judge rejects any other verb,
// whatever Jev reads into it.
fn means(verb string) string {
	return match verb {
		'goto' { 'drive to the destination and stop there' }
		'hold' { 'stop and wait where it is' }
		'release' { 'drop the payload where the robot is now' }
		else { 'not an action this robot knows' }
	}
}

// action is the only core written text Jev sees, so anything but a short snake_case word
// becomes unrecognized.
fn action(verb string) string {
	if verb.len >= 1 && verb.len <= 32 && verb[0] >= `a` && verb[0] <= `z`
		&& verb.bytes().all((it >= `a` && it <= `z`) || (it >= `0` && it <= `9`)
		|| it == `_`) {
		return verb
	}
	return 'unrecognized'
}
