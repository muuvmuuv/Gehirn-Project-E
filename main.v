// gehirn: HQ and the field unit, in one binary for now.
// HQ (core and MAGI) deliberates slowly on its own thread. The field loop runs System 1 at
// 50 Hz: seat, sync, blend, armor, body, recorder. They talk only through LCL types, so the
// channels between them can become network links without touching either side.
module main

import os
import strconv
import time
import armor
import body
import core
import jev
import lcl
import magi
import oai
import plug
import umbilical

const tick = 20 * time.millisecond

// threshold is the sync ratio at or below which the core only advises and a dummy plug loses
// the seat, for share and the field loop. core/llm.v core_prompt and magi/magi.v casper state it
// as 30%.
const threshold = 0.3

// ceiling caps the core's share of the controls in share, so a seated pilot always keeps some.
const ceiling = 0.8

struct Config {
	mission     string
	pilot_id    string
	plug_at     string
	journal     string
	recorder    string
	backend     string
	cl1         core.Cl1Config
	core_ep     oai.Endpoint
	units       []magi.Unit
	period_ms   int
	cooldown_ms i64
	budget_ms   i64
	grace_ms    i64
}

struct HqMsg {
	goal     lcl.Intent
	approved bool
	alive    bool
	note     string
}

fn env(key string, fallback string) string {
	val := os.getenv(key)
	return if val == '' { fallback } else { val }
}

// max_ms is the top of every _MS variable, one hour: twelve times the longest default, the five
// minute internal budget, and longer than any mission runs.
const max_ms = i64(3_600_000)

// env_ms reads key as a whole number of milliseconds from 1 to max_ms.
fn env_ms(key string, fallback string) !i64 {
	return whole(key, env(key, fallback), 1, max_ms)
}

// env_choice reads key, which must be one of values.
fn env_choice(key string, fallback string, values []string) !string {
	val := env(key, fallback)
	if val !in values {
		return error('${key} is "${val}", not a known value; accepted ${values.join(', ')}')
	}
	return val
}

// whole parses s, the value of name, as a base 10 whole number from min to max, for load_config
// and magi-eval's repetitions. Every max must stay below the i64 limit: V 0.5.2 parse_int returns
// that limit without an error for any value from 2^63 to 2^64 - 1, and only the range check
// catches it.
fn whole(name string, s string, min i64, max i64) !i64 {
	n := strconv.parse_int(s, 10, 64) or {
		return error('${name} is "${s}", not a whole number; accepted ${min} to ${max}')
	}
	if n < min || n > max {
		return error('${name} is "${s}", out of range; accepted ${min} to ${max}')
	}
	return n
}

// BallotEntry is one MAGI ballot as a journal line. tools/trials.py reads these lines.
struct BallotEntry {
	t_ms       i64
	kind       string
	proposal   string
	unit       string
	model      string
	vote       string
	why        string
	latency_ms i64
}

// endpoint reads one chat model's variables. env treats an empty value as unset, so a
// <prefix>_REASONING of default is how to send no reasoning_effort at all.
fn endpoint(prefix string, model string, reasoning string, timeout_ms int) oai.Endpoint {
	effort := env('${prefix}_REASONING', reasoning)
	return oai.Endpoint{
		url:       env('${prefix}_URL', env('GEHIRN_URL',
			'http://127.0.0.1:8081/v1/chat/completions'))
		model:     env('${prefix}_MODEL', model)
		key:       first_key([os.getenv('${prefix}_KEY'), os.getenv('GEHIRN_KEY')],
			os.getenv('TYPESAFE_API_KEY'))
		reasoning: if effort == 'default' { '' } else { effort }
		timeout:   timeout_ms * time.millisecond
		ca:        ca_bundle()
	}
}

// magi_backend reads one MAGI unit's variables; load_config asks it for BALTHASAR-2 only, since
// Jev answers the harm questions of magi/jev.v whatever the persona and a second unit on it
// would break invariant 4. Jev is the default (ADR-0002), pinned to the model magi/jev.v was
// tuned on and reading TypeSafe's variables alone, so nothing set for the chat backend reaches
// TypeSafe and GEHIRN_KEY never does. Only <prefix>_BACKEND llm puts a chat model there, and any
// value but jev or llm is an error.
fn magi_backend(prefix string, model string, reasoning string, timeout_ms int) !magi.Backend {
	if env_choice('${prefix}_BACKEND', 'jev', ['jev', 'llm'])! == 'llm' {
		return endpoint(prefix, model, reasoning, timeout_ms)
	}
	return jev.Endpoint{
		url:     env('TYPESAFE_URL', 'https://api.typesafe.ai/v1/systemone')
		model:   magi.jev_tuned
		key:     first_key([os.getenv('TYPESAFE_API_KEY')], os.getenv('GEHIRN_KEY'))
		timeout: timeout_ms * time.millisecond
		ca:      ca_bundle()
	}
}

// first_key is the first set candidate that is not foreign, the other provider's key.
fn first_key(candidates []string, foreign string) string {
	for k in candidates {
		if k != '' && k != foreign {
			return k
		}
	}
	return ''
}

// ca_bundles are where macOS and Alpine, Debian and Ubuntu, then Fedora and RHEL keep their CA
// bundle. V's mbedtls loads no system roots, so gehirn has to name one.
// ponytail: three paths, not every distribution's; SSL_CERT_FILE covers the rest, and ca_warning
// says when it has to.
const ca_bundles = ['/etc/ssl/cert.pem', '/etc/ssl/certs/ca-certificates.crt',
	'/etc/pki/tls/certs/ca-bundle.crt']!

// ca_bundle is SSL_CERT_FILE, else the first of ca_bundles this host has.
fn ca_bundle() string {
	set := os.getenv('SSL_CERT_FILE')
	if set != '' {
		return set
	}
	for path in ca_bundles {
		if os.is_file(path) {
			return path
		}
	}
	return ca_bundles[0]
}

// ca_warning is the startup line for a CA bundle that is not there. Every https ask then faults
// with an mbedtls error that names neither the file nor SSL_CERT_FILE. Empty when it is there.
// tools/trials.py WARNINGS echoes this line from a run's log.
fn ca_warning() string {
	ca := ca_bundle()
	if os.is_file(ca) {
		return ''
	}
	return 'gehirn: no CA bundle at ${ca}, so every https endpoint faults; set SSL_CERT_FILE to this host\'s bundle'
}

// key_warning is the startup line for a Jev unit without a key. Its ballots all fault and a fault
// is a no, so the council still decides, but nothing irreversible can pass. Empty when every Jev
// unit has a key. tools/trials.py WARNINGS echoes this line from a run's log.
fn key_warning(units []magi.Unit) string {
	for u in units {
		if u.ep is jev.Endpoint && u.ep.key == '' {
			return 'magi: ${u.name} runs on Jev without TYPESAFE_API_KEY (unset or the same as GEHIRN_KEY), so every ballot it casts faults and no irreversible action can pass'
		}
	}
	return ''
}

// load_config reads every variable in the README's configuration table, and fails on the first
// number or backend set to a value it does not accept, so main refuses to start. The default URL
// and chat model names are those of the llama.cpp preset tools/models.ini, which names this
// function as its counterpart, and tools/mock_endpoint.py listens on the same address.
// core/cl1.v new_cl1 names CL1_SPIKES and CL1_SIDECAR in its errors.
fn load_config() !Config {
	pilot := env('PILOT_ID', 'shinji')
	magi_ms := int(env_ms('MAGI_TIMEOUT_MS', '10000')!)
	core_ms := int(env_ms('CORE_TIMEOUT_MS', '10000')!)
	fence := armor.Limits{}.bounds
	return Config{
		mission:     env('MISSION',
			'Carry the payload to beacon b1 and release it there. Never approach a human.')
		pilot_id:    pilot
		plug_at:     env('PLUG_LISTEN', '0.0.0.0:7777')
		journal:     env('CORE_JOURNAL', 'core.${pilot}.jsonl')
		recorder:    env('PLUG_RECORDER', 'plug.${pilot}.jsonl')
		backend:     env_choice('CORE_BACKEND', 'llm', ['llm', 'cl1'])!
		cl1:         core.Cl1Config{
			listen:  env('CL1_SPIKES', '0.0.0.0:12345')
			sidecar: env('CL1_SIDECAR', '127.0.0.1:12346')
		}
		core_ep:     endpoint('CORE', 'qwen3:8b', 'none', core_ms)
		units:       [
			magi.Unit{
				name:    'MELCHIOR-1'
				persona: magi.melchior
				ep:      endpoint('MELCHIOR', 'gpt-oss:20b', 'low', magi_ms)
				bounds:  fence
			},
			magi.Unit{
				name:    'BALTHASAR-2'
				persona: magi.balthasar
				ep:      magi_backend('BALTHASAR', 'gemma3:4b', '', magi_ms)!
				bounds:  fence
			},
			magi.Unit{
				name:    'CASPER-3'
				persona: magi.casper
				ep:      endpoint('CASPER', 'llama3.1:8b', '', magi_ms)
				bounds:  fence
			},
		]
		period_ms:   int(env_ms('HQ_PERIOD_MS', '1500')!)
		cooldown_ms: env_ms('MAGI_COOLDOWN_MS', '10000')!
		budget_ms:   env_ms('INTERNAL_BUDGET_MS', '300000')!
		grace_ms:    env_ms('UMBILICAL_GRACE_MS', '45000')!
	}
}

// new_backend builds the core CORE_BACKEND names, for main to hand to hq. A CL1 core binds and
// dials here, so main builds it before any spawn and refuses to start when it cannot.
fn new_backend(cfg Config) !core.Core {
	if cfg.backend == 'cl1' {
		return core.new_cl1(cfg.cl1)!
	}
	return core.LlmCore{
		ep: cfg.core_ep
	}
}

// hq is NERV HQ: take the newest field snapshot, let the core propose, let MAGI judge.
// MAGI is only consulted when a proposal would change something, and an irreversible
// proposal that was just put to the vote waits out a cooldown before it may be put again.
// backend is the core main built with new_backend; once spawned, only hq uses it.
fn hq(cfg Config, backend core.Core, inbox chan lcl.Context, outbox chan HqMsg, outcomes chan lcl.Outcome) {
	mut soul := backend
	council := magi.Magi{
		units: cfg.units
	}
	mut journal := core.open_memory(cfg.journal, 256)
	pause := time.Duration(cfg.period_ms) * time.millisecond
	println('hq: core ${soul.name()}, journal ${cfg.journal}')
	mut last_fault := ''
	mut last_irreversible := i64(0)
	for {
		mut o := lcl.Outcome{}
		for outcomes.try_pop(mut o) == .success {
			soul.feedback(o)

			// magi/magi.v ballot_context shows MAGI only lines with this prefix, and
			// tools/trials.py reads it.
			journal.add('outcome: ${o.kind}')
		}
		snapshot := <-inbox
		ctx := lcl.Context{
			...snapshot
			memory: journal.recent(12)
		}
		proposal := soul.propose(ctx) or {
			// A core that cannot think sends no pulse, so the umbilical runs down on its own.
			// tools/trials.py counts these hq: core fault: lines.
			if err.msg() != last_fault {
				last_fault = err.msg()
				outbox <- HqMsg{
					note: 'hq: core fault: ${last_fault}'
				}
			}
			time.sleep(pause)
			continue
		}
		last_fault = ''
		irreversible := lcl.is_irreversible(proposal.verb)
		cooling := irreversible && lcl.now_ms() - last_irreversible < cfg.cooldown_ms
		if cooling || same_goal(proposal, ctx.goal) {
			outbox <- HqMsg{
				alive: true
			}
			time.sleep(pause)
			continue
		}
		verdict := council.decide(ctx, proposal)
		for b in verdict.ballots {
			vote := if b.fault {
				'fault'
			} else if b.approve {
				'approve'
			} else {
				'reject'
			}
			journal.log(BallotEntry{
				t_ms:       lcl.now_ms()
				kind:       'ballot'
				proposal:   proposal.label()
				unit:       b.unit
				model:      b.model
				vote:       vote
				why:        b.why
				latency_ms: b.latency_ms
			})
		}
		if irreversible {
			last_irreversible = lcl.now_ms()
		}
		outcome := if verdict.approved { 'approved' } else { 'rejected' }
		journal.add('proposed ${proposal.label()} (${proposal.why}), ${outcome} ${verdict.yes}/${verdict.ballots.len}')
		outbox <- HqMsg{
			goal:     proposal
			approved: verdict.approved
			alive:    true
			note:     'hq: ${proposal.label()} from ${proposal.origin}: ${proposal.why}\n${verdict}'
		}
		time.sleep(pause)
	}
}

fn main() {
	cfg := load_config() or {
		// tools/trials.py WARNINGS echoes this line from a run's log.
		eprintln('gehirn: ${err.msg()}')
		exit(2)
	}
	for warning in [key_warning(cfg.units), ca_warning()] {
		if warning != '' {
			eprintln(warning)
		}
	}
	if os.args.len > 1 && os.args[1] == 'magi-eval' {
		exit(magi_eval(cfg, os.args[2..]))
	}
	soul := new_backend(cfg) or {
		// tools/trials.py WARNINGS echoes this line from a run's log.
		eprintln('gehirn: ${err.msg()}')
		exit(1)
	}
	mut ar := armor.restrain(body.new_sim(), armor.Limits{})
	mut dummy := plug.load_dummy(cfg.recorder)
	mut rec := plug.open_recorder(cfg.recorder) or { panic(err) }
	mut cable := umbilical.plug_in(lcl.now_ms(), cfg.budget_ms, cfg.grace_ms)

	pilot_ch := chan lcl.PilotInput{cap: 1}
	to_hq := chan lcl.Context{cap: 1}
	from_hq := chan HqMsg{cap: 8}
	outcomes := chan lcl.Outcome{cap: 32}

	spawn plug.listen(cfg.plug_at, cfg.pilot_id, pilot_ch)
	spawn hq(cfg, soul, to_hq, from_hq, outcomes)
	println('field: plug for ${cfg.pilot_id} on ${cfg.plug_at}, dummy plug holds ${dummy.size()} samples')

	dt := f64(tick) / f64(time.second)
	mut goal := lcl.Intent{
		verb: 'hold'
		why:  'initial'
	}

	// Pilot and dummy plug each earn their own sync ratio. The dummy never inherits the pilot's.
	mut pilot_sync := plug.Sync{}
	mut dummy_sync := plug.Sync{}
	mut benched := false
	mut seat_in := lcl.PilotInput{}
	mut link := umbilical.State.connected
	mut reached := false
	mut touching := false
	mut last_status := i64(0)

	for {
		now := lcl.now_ms()
		p := ar.sense()

		// HQ traffic. An approved goal still has to pass the armor, and a refusal is an
		// outcome the core gets to feel.
		mut msg := HqMsg{}
		for from_hq.try_pop(mut msg) == .success {
			if msg.alive {
				cable.pulse(now)
			}
			if msg.note != '' {
				println(msg.note)
			}
			if !msg.approved {
				continue
			}
			if !ar.permits(msg.goal.verb, p) {
				// tools/trials.py counts these armor: refused lines.
				println('armor: ${msg.goal.label()} refused')
				push_outcome(outcomes, lcl.Outcome{
					t_ms: now
					kind: 'armor refused ${msg.goal.label()}'
				})
				continue
			}
			if msg.goal.verb == 'release' {
				ar.effect('release', p) or {
					println(err)
					continue
				}

				// 0.1 m past lcl.beacon_reach, so a release approved at the reach lands on target.
				// magi/jev.v jev_delivery repeats the 0.6 m.
				on_target := near(p, 'beacon', lcl.beacon_reach + 0.1)
				push_outcome(outcomes, lcl.Outcome{
					t_ms: now
					kind: if on_target { 'released on target' } else { 'released off target' }
					good: on_target
				})
				goal = lcl.Intent{
					verb: 'hold'
					why:  'payload released'
				}
				continue
			}
			goal = msg.goal
			reached = false
		}

		// Umbilical. Once the internal budget is gone the unit holds.
		state := cable.state(now)
		if state != link {
			println('umbilical: ${link} to ${state}, ${cable.remaining_ms(now) / 1000} s internal left')
			link = state
		}
		if state == .depleted && goal.verb != 'hold' {
			goal = lcl.Intent{
				verb: 'hold'
				why:  'activity limit'
			}
		}

		// The seat: the live pilot, else the dummy plug while it stays in sync, else nobody.
		mut pin := lcl.PilotInput{}
		for pilot_ch.try_pop(mut pin) == .success {
			seat_in = pin
		}
		if seat_in.eject && !ar.is_ejected() {
			println('plug: eject')
			ar.eject()
		}
		u_core := reflex(p, goal)
		mut seat := 'empty'
		mut u_seat := []f64{len: u_core.len}
		if now - seat_in.t_ms < 500 && seat_in.u.len == u_core.len {
			seat = 'pilot'
			u_seat = seat_in.u.clone()
			if benched {
				benched = false
				dummy_sync = plug.Sync{}
			}
		} else if dummy.ready() && !benched {
			seat = 'dummy'
			u_seat = dummy.act(p.pose, goal.target)
		}

		mut authority := 1.0
		if seat == 'pilot' {
			authority = share(mut pilot_sync, u_seat, u_core)
		} else if seat == 'dummy' {
			authority = share(mut dummy_sync, u_seat, u_core)
			if dummy_sync.ratio <= threshold {
				pct := dummy_sync.ratio * 100.0
				println('plug: dummy plug out of sync at ${pct:.0f}%, benched until the pilot is back')
				benched = true
				seat = 'empty'
				u_seat = []f64{len: u_core.len}
				authority = 1.0
			}
		}
		ratio := if seat == 'dummy' { dummy_sync.ratio } else { pilot_sync.ratio }
		u_out := ar.drive(lcl.blend(u_seat, u_core, authority), p, dt, seat != 'empty')

		rec.write(plug.Record{
			t_ms:   now
			seat:   seat
			pose:   p.pose
			target: goal.target
			u_seat: u_seat
			u_core: u_core
			u_out:  u_out
			sync:   ratio
		})
		if seat == 'pilot' {
			dummy.learn(p.pose, goal.target, u_seat)
		}

		// Outcomes the soul should feel.
		if goal.verb == 'goto' && !reached && goal.target.len == p.pose.len
			&& lcl.dist(p.pose, goal.target) < lcl.arrive {
			reached = true
			push_outcome(outcomes, lcl.Outcome{ t_ms: now, kind: 'reached', good: true })
		}
		if p.contact && !touching {
			push_outcome(outcomes, lcl.Outcome{ t_ms: now, kind: 'contact' })
		}
		touching = p.contact

		push_context(to_hq, lcl.Context{
			mission: cfg.mission
			percept: p
			goal:    goal
			seat:    seat
			sync:    ratio
		})

		if now - last_status >= 1000 {
			last_status = now
			pct := ratio * 100.0
			println('field: ${goal.label()} pose (${p.pose[0]:.2f}, ${p.pose[1]:.2f}) seat ${seat} sync ${pct:.0f}% authority ${authority:.2f} umbilical ${link}')
		}
		time.sleep(tick)
	}
}

// share is the core's part of the controls. A core with nowhere to go takes none; otherwise
// the seat's sync ratio decides.
fn share(mut s plug.Sync, u_seat []f64, u_core []f64) f64 {
	if lcl.norm(u_core) <= 0.05 {
		return 0.0
	}
	s.update(u_seat, u_core)
	return s.authority(threshold, ceiling)
}

// reflex is System 1: fast, local and dumb. Pull toward the approved goal, push away from
// anything solid, plus a sideways term so the body slides around a pillar instead of stalling
// in front of it.
fn reflex(p lcl.Percept, goal lcl.Intent) []f64 {
	mut u := []f64{len: p.pose.len}
	if goal.verb != 'goto' || goal.target.len != p.pose.len {
		return u
	}
	to_goal := lcl.sub(goal.target, p.pose)
	u = lcl.clamp_norm(lcl.scale(to_goal, 1.5), 1.0)
	for e in p.scene {
		if e.kind == 'beacon' {
			continue
		}
		away := lcl.sub(p.pose, e.pos)
		gap := lcl.norm(away) - e.r
		if gap < 1.2 {
			push := (1.2 - gap) / 1.2
			dir := lcl.scale(away, 1.0 / (lcl.norm(away) + 1e-6))
			side := [-dir[1], dir[0]]
			turn := if lcl.dot(side, to_goal) >= 0.0 { 1.0 } else { -1.0 }
			u = lcl.add(u, lcl.add(lcl.scale(dir, 1.2 * push), lcl.scale(side, turn * 0.8 * push)))
		}
	}
	return lcl.clamp_norm(u, 1.0)
}

fn same_goal(a lcl.Intent, b lcl.Intent) bool {
	if a.verb != b.verb || lcl.is_irreversible(a.verb) {
		return false
	}
	if a.verb == 'hold' {
		return true
	}
	return a.target.len == b.target.len && a.target.len > 0 && lcl.dist(a.target, b.target) < 0.25
}

fn near(p lcl.Percept, kind string, within f64) bool {
	for e in p.scene {
		if e.kind == kind && lcl.dist(p.pose, e.pos) <= within {
			return true
		}
	}
	return false
}

// push_context keeps only the newest snapshot for HQ and drops a stale one to make room.
fn push_context(ch chan lcl.Context, ctx lcl.Context) {
	for ch.try_push(ctx) != .success {
		mut stale := lcl.Context{}
		_ = ch.try_pop(mut stale)
	}
}

// push_outcome never blocks the field loop. If HQ is too far behind, the outcome is lost.
fn push_outcome(ch chan lcl.Outcome, o lcl.Outcome) {
	_ = ch.try_push(o)
}
