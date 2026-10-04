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
import wire
import zenoh

const tick = 20 * time.millisecond

// threshold is the sync ratio at or below which the core only advises and a dummy plug loses
// the seat, for share and the field loop. core/llm.v core_prompt and magi/magi.v casper state it
// as 30%, and bridge/draw.v threshold draws it.
const threshold = 0.3

// ceiling caps the core's share of the controls in share, so a seated pilot always keeps some.
const ceiling = 0.8

struct Config {
	mission     string
	pilot_id    string
	plug_at     string
	journal     string
	recorder    string
	weights     string
	backend     string
	cl1         core.Cl1Config
	core_ep     oai.Endpoint
	units       []magi.Unit
	period_ms   int
	cooldown_ms i64
	budget_ms   i64
	grace_ms    i64
	unit        string
	link        []u8 // UMBILICAL_KEY's 32 bytes, empty when unset
	pilot_key   []u8 // PILOT_KEY's 32 bytes, empty when unset
	watch       []u8 // WATCH_KEY's 32 bytes, empty when unset
	bridge      string
	endpoint    string
	start       []f64 // x, y in meters, where body.new_sim puts the body
}

fn env(key string, fallback string) string {
	val := os.getenv(key)
	return if val == '' { fallback } else { val }
}

// Span is the whole numbers from min to max that one _MS variable accepts, for env_ms.
struct Span {
	min int
	max int
}

// deadline_span bounds MAGI_TIMEOUT_MS and CORE_TIMEOUT_MS. A hosted ask is a TLS handshake plus
// a completion, so below a second nearly every ballot and proposal would fault: the council could
// only vote no and the core would hardly ever pulse the cable. Above 15 s both deadlines and the
// HQ pause no longer fit inside the shortest grace, see grace_span.
const deadline_span = Span{1000, 15000}

// period_span bounds HQ_PERIOD_MS. It starts at five field ticks, so the field loop has applied
// HQ's last verdict and sent a snapshot that shows it before HQ deliberates again, even when load
// delays a tick or two; sooner, MAGI votes again on a goal already in force.
// It stops at 3 s, twice the default, below the shortest cooldown and inside the grace.
const period_span = Span{100, 3000}

// cooldown_span bounds MAGI_COOLDOWN_MS. It starts above the longest HQ pause, or it would never
// hold back the deliberation right after a vote. It stops at a minute: it only spaces out votes
// on one irreversible act, and a longer one stalls a delivery whose first release vote failed,
// say while a human walked past.
const cooldown_span = Span{5000, 60000}

// grace_span bounds UMBILICAL_GRACE_MS. A healthy HQ pulses once per deliberation, so its longest
// silence is both deadlines plus the pause, 33 s at their tops; the grace starts well above that,
// so a slow vote never counts as a cut cable. Past a minute it only delays noticing a dead HQ.
const grace_span = Span{40000, 60000}

// budget_span bounds INTERNAL_BUDGET_MS. 0 holds the moment the cable counts as cut, the most
// careful setting. The top is the five minutes of the Eva's battery that umbilical.plug_in
// states, the longest the unit may follow a goal without HQ.
const budget_span = Span{0, 300000}

// env_ms reads key as a whole number of milliseconds within span.
fn env_ms(key string, fallback string, span Span) !int {
	return whole(key, env(key, fallback), span.min, span.max)
}

// env_choice reads key, which must be one of values.
fn env_choice(key string, fallback string, values []string) !string {
	val := env(key, fallback)
	if val !in values {
		return error('${key} is ${lcl.quoted(val)}, not a known value; accepted ${values.join(', ')}')
	}
	return val
}

// whole parses s, the value of name, as a base 10 whole number from min to max, for load_config
// and magi-eval's repetitions. It takes an optional minus and ASCII digits only, so a plus, an
// underscore or a space is not a whole number, and a number past the range is out of range however
// large it is.
fn whole(name string, s string, min int, max int) !int {
	digits := s.trim_string_left('-')
	if digits == '' || !digits.contains_only('0123456789') {
		return error('${name} is ${lcl.quoted(s)}, not a whole number; accepted ${min} to ${max}')
	}

	// With the digits checked, atoi fails only past the int range.
	n := strconv.atoi(s) or { max + 1 }
	if n < min || n > max {
		return error('${name} is ${lcl.quoted(s)}, out of range; accepted ${min} to ${max}')
	}
	return n
}

// start_pose reads START, where the simulated body starts, as x,y in meters inside fence, the
// armor's xmin, ymin, xmax, ymax. Each part is an optional minus and ASCII digits with an optional
// fraction, so a plus, a space, an exponent, inf or nan is not a position. tools/pilot.py START
// and the self of tools/scenarios.json copy the default.
fn start_pose(fence []f64) ![]f64 {
	val := env('START', '-3.5,-2.5')
	accepted := 'accepted x,y in meters, x from ${fence[0]} to ${fence[2]} and y from ${fence[1]} to ${fence[3]}'
	parts := val.split(',')
	if parts.len != 2 || !parts.all(is_decimal(it)) {
		return error('START is ${lcl.quoted(val)}, not a position; ${accepted}')
	}

	// With the text checked, atof64 cannot fail.
	x := strconv.atof64(parts[0]) or { fence[0] - 1.0 }
	y := strconv.atof64(parts[1]) or { fence[1] - 1.0 }
	if x < fence[0] || x > fence[2] || y < fence[1] || y > fence[3] {
		return error('START is ${lcl.quoted(val)}, outside the fence; ${accepted}')
	}
	return [x, y]
}

// is_decimal reports whether s is an optional minus, ASCII digits and an optional fraction of
// ASCII digits, for start_pose.
fn is_decimal(s string) bool {
	parts := s.trim_string_left('-').split('.')
	return parts.len <= 2 && parts.all(it != '' && it.contains_only('0123456789'))
}

// command is gehirn's first argument: empty flies a mission with HQ and the field unit in one
// process, hq and field run one of them alone, linked over Zenoh (ADR-0003), magi-eval runs
// magi_eval, and anything else is an error, so main refuses a mistyped command before it reads
// the configuration, opens the journal or spawns a thread. hq and field take no further argument.
fn command(args []string) !string {
	if args.len == 0 {
		return ''
	}
	if args[0] !in ['magi-eval', 'hq', 'field'] {
		return error('command is ${lcl.quoted(args[0])}, not a known value; accepted magi-eval, hq, field, or none to fly a mission')
	}
	if args[0] != 'magi-eval' && args.len > 1 {
		return error('${args[0]} takes no argument, not ${lcl.quoted(args[1])}')
	}
	return args[0]
}

// unit_id reads UNIT_ID, the unit's segment in every key expression of ADR-0003. Zenoh reads `*`,
// `$`, `?`, `#` and `/` as syntax, so a unit named `*` would hear every unit.
fn unit_id() !string {
	val := env('UNIT_ID', 'eva01') // bridge/main.v main repeats the default
	wire.check_unit(val) or { return error('UNIT_ID is ${lcl.quoted(val)}, ${err.msg()}') }
	return val
}

// hex_key reads name, a key of 64 hex digits such as UMBILICAL_KEY or PILOT_KEY, as 32 bytes, or
// none when unset. Its refusal never shows the value, which is a key.
fn hex_key(name string) ![]u8 {
	val := os.getenv(name)
	if val == '' {
		return []u8{}
	}
	return wire.decode_key(val) or { error('${name} is ${err.msg()}') }
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

// FaultEntry is one core fault as a journal line, written for every fault while HQ prints only a
// new one. It never enters the core's memory. tools/trials.py tally counts these lines.
struct FaultEntry {
	t_ms i64
	kind string
	why  string
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

// families refuses two MAGI units on chat models that name the same model at the same URL, for
// load_config: three personas on one model share every blind spot, which Invariant 4 forbids. Jev
// is a family of its own (ADR-0002), and one id at two URLs may be two models, as on two llama.cpp
// servers that each serve one.
// ponytail: identical ids only; two models of one family under different names still pass, so
// the lineup keeps the families apart. Add a family table once a lineup needs that check.
fn families(units []magi.Unit) ! {
	for i, a in units {
		for b in units[i + 1..] {
			if a.ep is oai.Endpoint && b.ep is oai.Endpoint && a.ep.model == b.ep.model
				&& a.ep.url == b.ep.url {
				return error('${a.name.all_before('-')}_MODEL and ${b.name.all_before('-')}_MODEL are both ${lcl.quoted(a.ep.model)} at one URL, and the MAGI units need three model families')
			}
		}
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
	return 'gehirn: no CA bundle at ${lcl.quoted(ca)}, so every https endpoint faults; set SSL_CERT_FILE to this host\'s bundle'
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
// number or backend set to a value it does not accept, on two MAGI units on one model, or on one
// key set as two of UMBILICAL_KEY, PILOT_KEY and WATCH_KEY, so main refuses to start. The default
// URL and chat model names are those of the llama.cpp preset tools/models.ini, which names this
// function as its counterpart, and tools/mock_endpoint.py listens on the same address.
// core/cl1.v new_cl1 names CL1_SPIKES and CL1_SIDECAR in its errors.
fn load_config() !Config {
	pilot := env('PILOT_ID', 'shinji') // gamepad/main.v main repeats the default
	magi_ms := env_ms('MAGI_TIMEOUT_MS', '10000', deadline_span)!
	core_ms := env_ms('CORE_TIMEOUT_MS', '10000', deadline_span)!
	fence := armor.Limits{}.bounds
	units := [
		magi.Unit{
			name:    'MELCHIOR-1' // bridge/draw.v units names the three for their panels
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
	families(units)!
	link := hex_key('UMBILICAL_KEY')!
	pilot_key := hex_key('PILOT_KEY')!
	watch := hex_key('WATCH_KEY')!

	// Each key stays on the machines of its role (ADR-0005): whoever holds the link key can seal a
	// goal or a pulse, whoever holds PILOT_KEY can steer and eject, and the bridge can do neither.
	if watch.len > 0 && watch == link {
		return error('WATCH_KEY is the same as UMBILICAL_KEY, and the bridge must never hold the key that approves or pulses; generate its own with `openssl rand -hex 32`')
	}
	if pilot_key.len > 0 && pilot_key == link {
		return error("PILOT_KEY is the same as UMBILICAL_KEY, and the pilot's device must never hold the key that approves or pulses; generate its own with `openssl rand -hex 32`")
	}
	if pilot_key.len > 0 && pilot_key == watch {
		return error('PILOT_KEY is the same as WATCH_KEY, and the bridge must never hold the key that steers or ejects; generate its own with `openssl rand -hex 32`')
	}
	return Config{
		mission:     env('MISSION',
			'Carry the payload to beacon b1 and release it there. Never approach a human.')
		pilot_id:    pilot
		plug_at:     env('PLUG_LISTEN', '0.0.0.0:7777') // gamepad/main.v plug_addr dials the port
		journal:     env('CORE_JOURNAL', 'core.${pilot}.jsonl')
		recorder:    env('PLUG_RECORDER', 'plug.${pilot}.jsonl')
		weights:     env('DUMMY_WEIGHTS', 'dummy.${pilot}.json')
		backend:     env_choice('CORE_BACKEND', 'llm', ['llm', 'cl1'])!
		cl1:         core.Cl1Config{
			listen:  env('CL1_SPIKES', '0.0.0.0:12345')
			sidecar: env('CL1_SIDECAR', '127.0.0.1:12346')
		}
		core_ep:     endpoint('CORE', 'qwen3:8b', 'none', core_ms)
		units:       units
		period_ms:   env_ms('HQ_PERIOD_MS', '1500', period_span)!
		cooldown_ms: i64(env_ms('MAGI_COOLDOWN_MS', '10000', cooldown_span)!)
		budget_ms:   i64(env_ms('INTERNAL_BUDGET_MS', '300000', budget_span)!)
		grace_ms:    i64(env_ms('UMBILICAL_GRACE_MS', '45000', grace_span)!)
		unit:        unit_id()!
		link:        link
		pilot_key:   pilot_key
		watch:       watch
		bridge:      env('BRIDGE_ENDPOINT', 'tcp/127.0.0.1:7448') // bridge/main.v main repeats the default
		endpoint:    env('UMBILICAL_ENDPOINT', 'tcp/127.0.0.1:7447')
		start:       start_pose(fence)!
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
fn hq(cfg Config, backend core.Core, inbox chan lcl.Context, outbox chan lcl.HqMsg, outcomes chan lcl.Outcome, events chan lcl.HqEvent) {
	mut soul := backend
	council := magi.Magi{
		units: cfg.units
	}
	mut journal := core.open_memory(cfg.journal, 256)
	pause := time.Duration(cfg.period_ms) * time.millisecond
	println('hq: core ${lcl.quoted(soul.name())}, journal ${lcl.quoted(cfg.journal)}')
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
			mission: cfg.mission
			memory:  journal.recent(12)
		}
		proposal := soul.propose(ctx) or {
			// A core that cannot think still lets HQ pulse, so the unit keeps its last approved
			// goal while HQ deliberates, and without a proposal MAGI approves nothing (ADR-0004).
			journal.log(FaultEntry{
				t_ms: lcl.now_ms()
				kind: 'core fault'
				why:  err.msg()
			})
			note := if err.msg() != last_fault {
				'hq: core fault: ${lcl.escaped(err.msg())}'
			} else {
				''
			}
			last_fault = err.msg()
			if note != '' {
				_ = events.try_push(lcl.HqEvent{
					t_ms:  lcl.now_ms()
					fault: last_fault
				})
			}
			outbox <- lcl.HqMsg{
				alive: true
				note:  note
			}
			time.sleep(pause)
			continue
		}
		last_fault = ''
		irreversible := lcl.is_irreversible(proposal.verb)
		cooling := irreversible && lcl.now_ms() - last_irreversible < cfg.cooldown_ms
		if cooling || same_goal(proposal, ctx.goal) {
			outbox <- lcl.HqMsg{
				alive: true
			}
			time.sleep(pause)
			continue
		}
		needed := magi.quorum(proposal.verb, council.units.len)
		_ = events.try_push(lcl.HqEvent{
			t_ms:     lcl.now_ms()
			stage:    'deliberating'
			proposal: proposal
			needed:   needed
		})
		verdict := council.decide(ctx, proposal, fn [events, proposal, needed] (b magi.Ballot) {
			_ = events.try_push(lcl.HqEvent{
				t_ms:     lcl.now_ms()
				stage:    'ballot'
				proposal: proposal
				needed:   needed
				votes:    [shown(b)]
			})
		})
		for b in verdict.ballots {
			journal.log(BallotEntry{
				t_ms:       lcl.now_ms()
				kind:       'ballot'
				proposal:   proposal.label()
				unit:       b.unit
				model:      b.model
				vote:       vote_of(b)
				why:        b.why
				latency_ms: b.latency_ms
			})
		}
		_ = events.try_push(lcl.HqEvent{
			t_ms:     lcl.now_ms()
			proposal: proposal
			approved: verdict.approved
			yes:      verdict.yes
			needed:   verdict.needed
			votes:    verdict.ballots.map(shown(it))
		})
		if irreversible {
			last_irreversible = lcl.now_ms()
		}
		outcome := if verdict.approved { 'approved' } else { 'rejected' }
		journal.add('proposed ${proposal.label()} (${proposal.why}), ${outcome} ${verdict.yes}/${verdict.ballots.len}')
		outbox <- lcl.HqMsg{
			goal:     proposal
			approved: verdict.approved
			alive:    true
			note:     'hq: ${lcl.escaped(proposal.label())} from ${lcl.quoted(proposal.origin)}: ${lcl.escaped(proposal.why)}\n${verdict}'
		}
		time.sleep(pause)
	}
}

// serve_hq runs HQ alone, linked to the field unit over Zenoh: the core and MAGI deliberate on
// hq's thread, the link's pump runs on another, and this thread prints HQ's notes, which the
// field loop prints when both share a process. It exits like main when it cannot start.
fn serve_hq(cfg Config) {
	soul := new_backend(cfg) or {
		// tools/trials.py WARNINGS echoes this line from a run's log.
		eprintln('gehirn: ${err.msg()}')
		exit(1)
	}
	mut link := link_hq(cfg) or {
		eprintln('gehirn: ${err.msg()}')
		exit(1)
	}
	inbox := chan lcl.Context{cap: 1}
	outbox := chan lcl.HqMsg{cap: 8}
	outcomes := chan lcl.Outcome{cap: 32}
	notes := chan string{cap: 64}
	events := chan lcl.HqEvent{cap: 16}

	// The Justfile's _fly recipe waits on `listening for the field` before it starts the field unit.
	println('hq: unit ${cfg.unit}, listening for the field at ${lcl.quoted(cfg.endpoint)}')
	if cfg.watch.len > 0 {
		mut w := wire.hq_watch(watch_session(cfg) or {
			eprintln('gehirn: ${err.msg()}')
			exit(1)
		}, cfg.unit, cfg.watch) or {
			eprintln('gehirn: ${err.msg()}')
			exit(1)
		}
		println('hq: showing the bridge at ${lcl.quoted(cfg.bridge)}')
		spawn w.run_hq(events)
	}
	spawn hq(cfg, soul, inbox, outbox, outcomes, events)
	spawn link.run(inbox, outcomes, outbox, notes)
	for {
		println(<-notes)
	}
}

// watch_session opens a tier's session to the bridge: it dials BRIDGE_ENDPOINT and holds only
// the watch publisher, so the bridge never links to the session that carries goals and pulses
// (ADR-0005). Zenoh keeps dialing an absent bridge.
fn watch_session(cfg Config) !&zenoh.Session {
	return zenoh.open(zenoh.Config{ connect: [cfg.bridge] }) or {
		return error('BRIDGE_ENDPOINT is ${lcl.quoted(cfg.bridge)}; ${err.msg()}')
	}
}

// link_hq opens HQ's end of the link: a session listening on UMBILICAL_ENDPOINT, and its pump.
fn link_hq(cfg Config) !&wire.Hq {
	s := zenoh.open(zenoh.Config{ listen: [cfg.endpoint] }) or {
		return error('UMBILICAL_ENDPOINT is ${lcl.quoted(cfg.endpoint)}; ${err.msg()}')
	}
	return wire.new_hq(wire.hq_ports(s, cfg.unit)!, cfg.link, cfg.unit)!
}

// link_field opens the field unit's end of the link: a session dialing UMBILICAL_ENDPOINT, and
// its pump. Zenoh keeps dialing until HQ answers and again after HQ restarts, so the field unit
// starts without HQ and the umbilical decides what the silence means.
fn link_field(cfg Config) !&wire.Field {
	s := zenoh.open(zenoh.Config{ connect: [cfg.endpoint] }) or {
		return error('UMBILICAL_ENDPOINT is ${lcl.quoted(cfg.endpoint)}; ${err.msg()}')
	}
	return wire.new_field(wire.field_ports(s, cfg.unit)!, cfg.link, cfg.unit, cfg.grace_ms)!
}

fn main() {
	cmd := command(os.args[1..]) or {
		eprintln('gehirn: ${err.msg()}')
		exit(2)
	}
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
	if cmd == 'magi-eval' {
		exit(magi_eval(cfg, os.args[2..]))
	}
	if cmd in ['hq', 'field'] && cfg.link.len == 0 {
		eprintln('gehirn: UMBILICAL_KEY is unset, and ${cmd} needs the unit\'s link key; generate one with `openssl rand -hex 32`')
		exit(2)
	}
	if cmd == 'hq' {
		serve_hq(cfg)
		return
	}
	mut ar := armor.restrain(body.new_sim(cfg.start), armor.Limits{})
	mut dummy := plug.load_dummy(cfg.recorder, cfg.weights) or {
		// tools/trials.py WARNINGS echoes this line from a run's log.
		eprintln('gehirn: DUMMY_WEIGHTS is ${lcl.quoted(cfg.weights)}; ${err.msg()}')
		exit(1)
	}
	mut rec := plug.open_recorder(cfg.recorder) or { panic(err) }
	mut cable := umbilical.plug_in(lcl.now_ms(), cfg.budget_ms, cfg.grace_ms)

	pilot_ch := chan lcl.PilotInput{cap: 1}
	to_hq := chan lcl.Context{cap: 1}
	from_hq := chan lcl.HqMsg{cap: 8}
	outcomes := chan lcl.Outcome{cap: 32}
	views := chan lcl.FieldView{cap: 1}
	feel := chan lcl.Feel{cap: 1}
	watching := cmd == 'field' && cfg.watch.len > 0

	// The other end of these channels: the link to HQ, or HQ on a thread of its own.
	if cmd == 'field' {
		mut link := link_field(cfg) or {
			eprintln('gehirn: ${err.msg()}')
			exit(1)
		}
		println('field: unit ${cfg.unit}, dialing HQ at ${lcl.quoted(cfg.endpoint)}')
		spawn link.run(to_hq, outcomes, from_hq)
		if watching {
			mut w := wire.field_watch(watch_session(cfg) or {
				eprintln('gehirn: ${err.msg()}')
				exit(1)
			}, cfg.unit, cfg.watch) or {
				eprintln('gehirn: ${err.msg()}')
				exit(1)
			}
			println('field: showing the bridge at ${lcl.quoted(cfg.bridge)}')
			spawn w.run_field(views)
		}
	} else {
		soul := new_backend(cfg) or {
			// tools/trials.py WARNINGS echoes this line from a run's log.
			eprintln('gehirn: ${err.msg()}')
			exit(1)
		}
		spawn hq(cfg, soul, to_hq, from_hq, outcomes, chan lcl.HqEvent{cap: 1})
	}
	if cfg.pilot_key.len == 0 {
		println('plug: PILOT_KEY is unset, so the plug drops every datagram and no pilot can steer or eject')
	}
	spawn plug.listen(cfg.plug_at, cfg.pilot_id, cfg.pilot_key, pilot_ch, feel)
	flies := if dummy.trained() {
		'flies the policy in ${lcl.quoted(cfg.weights)}'
	} else {
		'holds ${dummy.size()} samples'
	}
	println('field: plug for ${lcl.quoted(cfg.pilot_id)} on ${lcl.quoted(cfg.plug_at)}, dummy plug ${flies}')

	dt := f64(tick) / f64(time.second)
	mut goal := lcl.Intent{
		verb: 'hold'
		why:  'initial'
	}

	// Pilot and dummy plug each earn their own sync ratio. The dummy never inherits the pilot's.
	mut pilot_sync := plug.Sync{}
	mut dummy_sync := plug.Sync{}
	mut benched := false
	mut was_pilot := false // the pilot held the seat on the last tick
	mut dummy_drove := false // the dummy plug drove toward a goal on the last tick
	mut correcting := false
	mut seat_in := lcl.PilotInput{}
	mut link := umbilical.State.connected
	mut reached := false
	mut touching := false
	mut last_status := i64(0)
	mut ticks := u64(0)
	mut seen := []lcl.Outcome{} // outcomes since the last view for the bridge
	mut deadline := time.sys_mono_now()

	for {
		now := lcl.now_ms()
		p := ar.sense()

		// HQ traffic. An approved goal still has to pass the armor, and a refusal is an
		// outcome the core gets to feel.
		mut msg := lcl.HqMsg{}
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
				println('armor: ${lcl.escaped(msg.goal.label())} refused')

				// tools/trials.py tally counts this outcome from the journal.
				push_outcome(outcomes, mut seen, lcl.Outcome{
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
				// magi/jev.v jev_delivery and tools/eval_dummy.py REACH repeat the 0.6 m.
				on_target := near(p, 'beacon', lcl.beacon_reach + 0.1)

				// The Justfile's _fly recipe waits on `released on target` in the journal.
				push_outcome(outcomes, mut seen, lcl.Outcome{
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
			// The Justfile's _fly recipe waits on `connected to internal` and `internal to connected`.
			println('umbilical: ${link} to ${state}, ${cable.remaining_ms(now) / 1000} s internal left')
			link = state
		}
		if state == .depleted && goal.verb != 'hold' {
			goal = lcl.Intent{
				verb: 'hold'
				why:  'activity limit'
			}
		}

		// The seat: the live pilot, else the dummy plug while it stays in sync and nobody has
		// ejected, else nobody.
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
		if now - seat_in.t_ms < plug.seat_ms && seat_in.u.len == u_core.len {
			// A pilot who takes the seat from the dummy plug while it drives toward a goal, or
			// after it was benched, corrects it until leaving, and the recorder marks those
			// ticks for DAgger.
			if !was_pilot {
				correcting = dummy_drove || benched
			}
			seat = 'pilot'
			u_seat = seat_in.u.clone()
			if benched {
				benched = false
				dummy_sync = plug.Sync{}
			}
		} else if dummy.ready() && !benched && !ar.is_ejected() {
			seat = 'dummy'
			u_seat = dummy.act(p, goal.target)
		}

		mut authority := 1.0
		if seat == 'pilot' {
			authority = share(mut pilot_sync, u_seat, u_core)
		} else if seat == 'dummy' {
			authority = share(mut dummy_sync, u_seat, u_core)
			if dummy_sync.ratio <= threshold {
				// tools/eval_dummy.py BENCHED counts these lines.
				pct := dummy_sync.ratio * 100.0
				println('plug: dummy plug out of sync at ${pct:.0f}%, benched until the pilot is back')
				benched = true
				seat = 'empty'
				u_seat = []f64{len: u_core.len}
				authority = 1.0
			}
		}
		ratio := if seat == 'dummy' { dummy_sync.ratio } else { pilot_sync.ratio }
		u_cmd := lcl.blend(u_seat, u_core, authority)
		u_out := ar.drive(u_cmd, p, dt, seat != 'empty')

		// The A10 back channel: what the pilot's gamepad turns into rumble (ADR-0006).
		push_newest(feel, lcl.Feel{
			t_ms:    now
			contact: p.contact
			near:    ar.closeness(p)
			sync:    ratio
			strain:  if u_cmd.len == u_out.len { lcl.dist(u_cmd, u_out) } else { 0.0 }
		})

		rec.write(plug.Record{
			t_ms:       now
			seat:       seat
			pose:       p.pose
			target:     goal.target
			u_seat:     u_seat
			u_core:     u_core
			u_out:      u_out
			sync:       ratio
			scene:      p.scene
			correction: seat == 'pilot' && correcting
		})
		was_pilot = seat == 'pilot'
		dummy_drove = seat == 'dummy' && goal.target.len > 0
		if seat == 'pilot' {
			dummy.learn(p.pose, goal.target, u_seat)
		}

		// Outcomes the soul should feel.
		if goal.verb == 'goto' && !reached && goal.target.len == p.pose.len
			&& lcl.dist(p.pose, goal.target) < lcl.arrive {
			reached = true
			push_outcome(outcomes, mut seen, lcl.Outcome{ t_ms: now, kind: 'reached', good: true })
		}
		if p.contact && !touching {
			push_outcome(outcomes, mut seen, lcl.Outcome{ t_ms: now, kind: 'contact' })
		}
		touching = p.contact

		push_newest(to_hq, lcl.Context{
			percept: p
			goal:    goal
			seat:    seat
			sync:    ratio
		})

		// The bridge's view, every fifth tick.
		ticks++
		if ticks % 5 == 0 {
			if watching {
				push_newest(views, lcl.FieldView{
					percept:     p
					goal:        goal
					seat:        seat
					benched:     benched
					sync:        ratio
					authority:   authority
					umbilical:   link.str()
					internal_ms: cable.remaining_ms(now)
					silent_ms:   cable.silent_ms(now)
					awaiting:    cable.awaiting()
					grace_ms:    cable.grace_ms
					outcomes:    seen
				})
			}
			seen = []lcl.Outcome{}
		}

		if now - last_status >= 1000 {
			last_status = now
			pct := ratio * 100.0

			// The Justfile's _fly recipe waits on `seat pilot` and `seat dummy` in this line.
			println('field: ${goal.label()} pose (${p.pose[0]:.2f}, ${p.pose[1]:.2f}) seat ${seat} sync ${pct:.0f}% authority ${authority:.2f} umbilical ${link}')
		}
		next, nap := pace(deadline, time.sys_mono_now())
		deadline = next
		if nap > 0 {
			time.sleep(time.Duration(nap))
		}
	}
}

// pace is the field loop's schedule: from the deadline the last tick aimed for and the monotonic
// time now, both in nanoseconds, it returns the next deadline and how long to sleep until then.
// Deadlines are absolute, so the loop keeps its 50 Hz under load; one more than a tick behind
// starts again from now instead of running ticks back to back to catch up.
fn pace(last u64, now u64) (u64, u64) {
	next := last + u64(tick)
	if next >= now {
		return next, next - now
	}
	if now - next > u64(tick) {
		return now, 0
	}
	return next, 0
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

// push_newest keeps only the newest value in ch, the snapshot for HQ, the view for the bridge or
// the feel for the pilot, and drops a stale one to make room.
fn push_newest[T](ch chan T, v T) {
	for ch.try_push(v) != .success {
		mut stale := T{}
		_ = ch.try_pop(mut stale)
	}
}

// push_outcome never blocks the field loop. If HQ is too far behind, the outcome is lost. seen
// keeps it for the bridge's next view.
fn push_outcome(ch chan lcl.Outcome, mut seen []lcl.Outcome, o lcl.Outcome) {
	_ = ch.try_push(o)
	seen << o
}

// vote_of is a ballot's vote as the journal and the bridge name it: approve, reject or fault.
fn vote_of(b magi.Ballot) string {
	return if b.fault {
		'fault'
	} else if b.approve {
		'approve'
	} else {
		'reject'
	}
}

// shown is a ballot as hq shows it to the bridge.
fn shown(b magi.Ballot) lcl.Vote {
	return lcl.Vote{
		unit:       b.unit
		model:      b.model
		vote:       vote_of(b)
		why:        b.why
		latency_ms: b.latency_ms
	}
}
