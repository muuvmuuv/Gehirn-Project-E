module main

import os
import net
import time
import core
import jev
import lcl
import magi
import oai

struct KeyCase {
	backend      string
	unit_key     string
	typesafe_key string
	want         string
}

// Each provider's key reaches only that provider, whatever a unit's own variables say.
fn test_keys_never_cross_providers() {
	os.setenv('GEHIRN_URL', 'https://openrouter.example/v1/chat/completions', true)
	os.setenv('GEHIRN_KEY', 'openrouter', true)
	os.setenv('BALTHASAR_URL', 'https://openrouter.example/v1/chat/completions', true)
	os.setenv('BALTHASAR_MODEL', 'google/gemma-3-12b-it', true)
	os.unsetenv('TYPESAFE_URL')
	os.unsetenv('SSL_CERT_FILE')
	cases := [
		KeyCase{'jev', '', '', ''},
		KeyCase{'jev', '', 'typesafe', 'typesafe'},
		KeyCase{'jev', 'unit', 'typesafe', 'typesafe'},
		KeyCase{'jev', 'unit', '', ''},
		KeyCase{'jev', 'openrouter', 'typesafe', 'typesafe'},
		KeyCase{'jev', '', 'openrouter', ''},
		KeyCase{'llm', '', 'typesafe', 'openrouter'},
		KeyCase{'llm', 'unit', 'typesafe', 'unit'},
		KeyCase{'llm', 'typesafe', 'typesafe', 'openrouter'},
		KeyCase{'llm', '', 'openrouter', ''},
	]
	for c in cases {
		os.setenv('BALTHASAR_BACKEND', c.backend, true)
		os.setenv('BALTHASAR_KEY', c.unit_key, true)
		os.setenv('TYPESAFE_API_KEY', c.typesafe_key, true)
		b := magi_backend('BALTHASAR', 'gemma3:4b', '', 1000)!
		match b {
			jev.Endpoint {
				assert c.backend == 'jev', '${c}'
				assert b.key == c.want, '${c}'
				assert b.url == 'https://api.typesafe.ai/v1/systemone'
				assert b.model == magi.jev_tuned
				assert b.ca == ca_bundle()
			}
			oai.Endpoint {
				assert c.backend == 'llm', '${c}'
				assert b.key == c.want, '${c}'
				assert b.url == 'https://openrouter.example/v1/chat/completions'
				assert b.ca == ca_bundle()
			}
		}
	}
	os.setenv('BALTHASAR_BACKEND', 'jev', true)
	os.setenv('TYPESAFE_URL', 'http://127.0.0.1:18080/v1/systemone', true)
	os.setenv('SSL_CERT_FILE', '/tmp/ca.pem', true)
	b := magi_backend('BALTHASAR', 'gemma3:4b', '', 1000)!
	assert b.url == 'http://127.0.0.1:18080/v1/systemone'
	if b is jev.Endpoint {
		assert b.ca == '/tmp/ca.pem'
	}
}

// SSL_CERT_FILE names the CA bundle, else the first one this host has, and a bundle that is not
// there gets a startup line rather than only an mbedtls error on every https ask.
fn test_ca_bundle() {
	os.setenv('SSL_CERT_FILE', @FILE, true)
	assert ca_bundle() == @FILE
	assert ca_warning() == ''
	missing := os.join_path(os.temp_dir(), 'gehirn-no-such-ca.pem')
	os.setenv('SSL_CERT_FILE', missing, true)
	assert ca_warning() == 'gehirn: no CA bundle at ${missing}, so every https endpoint faults; set SSL_CERT_FILE to this host\'s bundle'
	os.unsetenv('SSL_CERT_FILE')
	assert ca_bundle() in ca_bundles
	assert os.is_file(ca_bundle()) || !ca_bundles.any(os.is_file(it))
}

// Only BALTHASAR-2 may run on Jev, so two units never share its model family.
fn test_only_balthasar_runs_on_jev() {
	for unit in ['MELCHIOR', 'BALTHASAR', 'CASPER'] {
		os.setenv('${unit}_BACKEND', 'jev', true)
	}
	units := load_config()!.units
	assert units.map(it.ep.type_name()) == ['oai.Endpoint', 'jev.Endpoint', 'oai.Endpoint']
}

// BALTHASAR-2 asks Jev unless told otherwise, and without TYPESAFE_API_KEY it says so at startup
// and faults every ballot, which blocks every irreversible proposal. No other backend steps in.
fn test_jev_without_key_fails_safe() {
	os.unsetenv('BALTHASAR_BACKEND')
	os.unsetenv('TYPESAFE_API_KEY')
	os.setenv('TYPESAFE_URL', 'http://127.0.0.1:9/v1/systemone', true)
	units := load_config()!.units
	assert units[1].ep is jev.Endpoint
	assert key_warning(units) == 'magi: BALTHASAR-2 runs on Jev without TYPESAFE_API_KEY (unset or the same as GEHIRN_KEY), so every ballot it casts faults and no irreversible action can pass'
	ctx := lcl.Context{
		percept: lcl.Percept{
			pose: [3.0, 2.0]
		}
	}
	b := units[1].vote(ctx, lcl.Intent{ verb: 'release' })
	assert b.fault && !b.approve, b.why
	assert b.why == 'jev-1.13.0: no API key'
	aye := magi.Ballot{
		approve: true
	}
	assert !magi.tally([aye, b, aye], 'release').approved
	assert magi.tally([aye, b, aye], 'goto').approved
	os.setenv('TYPESAFE_API_KEY', 'typesafe', true)
	assert key_warning(load_config()!.units) == ''
	os.setenv('BALTHASAR_BACKEND', 'llm', true)
	assert key_warning(load_config()!.units) == ''
}

struct ConfigCase {
	key  string
	val  string // empty leaves the variable unset
	want string // what load_config makes of the variable, or the line it refuses it with
}

// config_value is what cfg holds for key, as text.
fn config_value(cfg Config, key string) string {
	return match key {
		'MAGI_TIMEOUT_MS' { cfg.units[0].ep.timeout.milliseconds().str() }
		'CORE_TIMEOUT_MS' { cfg.core_ep.timeout.milliseconds().str() }
		'HQ_PERIOD_MS' { cfg.period_ms.str() }
		'MAGI_COOLDOWN_MS' { cfg.cooldown_ms.str() }
		'INTERNAL_BUDGET_MS' { cfg.budget_ms.str() }
		'UMBILICAL_GRACE_MS' { cfg.grace_ms.str() }
		'CORE_BACKEND' { cfg.backend }
		'BALTHASAR_BACKEND' { cfg.units[1].ep.type_name() }
		'UNIT_ID' { cfg.unit }
		'UMBILICAL_KEY' { cfg.link.hex() }
		'PILOT_KEY' { cfg.pilot_key.hex() }
		'UMBILICAL_ENDPOINT' { cfg.endpoint }
		else { 'no such variable' }
	}
}

fn test_load_config() {
	cases := [
		ConfigCase{'MAGI_TIMEOUT_MS', '', '10000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '2500', '2500'},
		ConfigCase{'MAGI_TIMEOUT_MS', '1000', '1000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '15000', '15000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '0', 'MAGI_TIMEOUT_MS is "0", out of range; accepted 1000 to 15000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '999', 'MAGI_TIMEOUT_MS is "999", out of range; accepted 1000 to 15000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '-10000', 'MAGI_TIMEOUT_MS is "-10000", out of range; accepted 1000 to 15000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '10s', 'MAGI_TIMEOUT_MS is "10s", not a whole number; accepted 1000 to 15000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '15001', 'MAGI_TIMEOUT_MS is "15001", out of range; accepted 1000 to 15000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '3600000', 'MAGI_TIMEOUT_MS is "3600000", out of range; accepted 1000 to 15000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '9223372036854775808', 'MAGI_TIMEOUT_MS is "9223372036854775808", out of range; accepted 1000 to 15000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '18446744073709551616', 'MAGI_TIMEOUT_MS is "18446744073709551616", out of range; accepted 1000 to 15000'},
		ConfigCase{'CORE_TIMEOUT_MS', '', '10000'},
		ConfigCase{'CORE_TIMEOUT_MS', '1000', '1000'},
		ConfigCase{'CORE_TIMEOUT_MS', '15000', '15000'},
		ConfigCase{'CORE_TIMEOUT_MS', '0', 'CORE_TIMEOUT_MS is "0", out of range; accepted 1000 to 15000'},
		ConfigCase{'CORE_TIMEOUT_MS', '-1', 'CORE_TIMEOUT_MS is "-1", out of range; accepted 1000 to 15000'},
		ConfigCase{'CORE_TIMEOUT_MS', 'abc', 'CORE_TIMEOUT_MS is "abc", not a whole number; accepted 1000 to 15000'},
		ConfigCase{'CORE_TIMEOUT_MS', '+5000', 'CORE_TIMEOUT_MS is "+5000", not a whole number; accepted 1000 to 15000'},
		ConfigCase{'CORE_TIMEOUT_MS', '10_000', 'CORE_TIMEOUT_MS is "10_000", not a whole number; accepted 1000 to 15000'},
		ConfigCase{'CORE_TIMEOUT_MS', '20000', 'CORE_TIMEOUT_MS is "20000", out of range; accepted 1000 to 15000'},
		ConfigCase{'CORE_TIMEOUT_MS', '99999999999', 'CORE_TIMEOUT_MS is "99999999999", out of range; accepted 1000 to 15000'},
		ConfigCase{'CORE_TIMEOUT_MS', '18446744073709551615', 'CORE_TIMEOUT_MS is "18446744073709551615", out of range; accepted 1000 to 15000'},
		ConfigCase{'HQ_PERIOD_MS', '', '1500'},
		ConfigCase{'HQ_PERIOD_MS', '100', '100'},
		ConfigCase{'HQ_PERIOD_MS', '3000', '3000'},
		ConfigCase{'HQ_PERIOD_MS', '0', 'HQ_PERIOD_MS is "0", out of range; accepted 100 to 3000'},
		ConfigCase{'HQ_PERIOD_MS', '99', 'HQ_PERIOD_MS is "99", out of range; accepted 100 to 3000'},
		ConfigCase{'HQ_PERIOD_MS', '-1500', 'HQ_PERIOD_MS is "-1500", out of range; accepted 100 to 3000'},
		ConfigCase{'HQ_PERIOD_MS', '1.5', 'HQ_PERIOD_MS is "1.5", not a whole number; accepted 100 to 3000'},
		ConfigCase{'HQ_PERIOD_MS', '3001', 'HQ_PERIOD_MS is "3001", out of range; accepted 100 to 3000'},
		ConfigCase{'HQ_PERIOD_MS', '9223372036854775807', 'HQ_PERIOD_MS is "9223372036854775807", out of range; accepted 100 to 3000'},
		ConfigCase{'HQ_PERIOD_MS', '1500\nmagi: MELCHIOR-1 approve', 'HQ_PERIOD_MS is "1500\\x0amagi: MELCHIOR-1 approve", not a whole number; accepted 100 to 3000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '', '10000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '5000', '5000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '60000', '60000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '0', 'MAGI_COOLDOWN_MS is "0", out of range; accepted 5000 to 60000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '4999', 'MAGI_COOLDOWN_MS is "4999", out of range; accepted 5000 to 60000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '-10000', 'MAGI_COOLDOWN_MS is "-10000", out of range; accepted 5000 to 60000'},
		ConfigCase{'MAGI_COOLDOWN_MS', ' 30000', 'MAGI_COOLDOWN_MS is " 30000", not a whole number; accepted 5000 to 60000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '60001', 'MAGI_COOLDOWN_MS is "60001", out of range; accepted 5000 to 60000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '-9223372036854775809', 'MAGI_COOLDOWN_MS is "-9223372036854775809", out of range; accepted 5000 to 60000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '', '45000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '40000', '40000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '60000', '60000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '0', 'UMBILICAL_GRACE_MS is "0", out of range; accepted 40000 to 60000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '1000', 'UMBILICAL_GRACE_MS is "1000", out of range; accepted 40000 to 60000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '-1', 'UMBILICAL_GRACE_MS is "-1", out of range; accepted 40000 to 60000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '45e3', 'UMBILICAL_GRACE_MS is "45e3", not a whole number; accepted 40000 to 60000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '60001', 'UMBILICAL_GRACE_MS is "60001", out of range; accepted 40000 to 60000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '9223372036854775808', 'UMBILICAL_GRACE_MS is "9223372036854775808", out of range; accepted 40000 to 60000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '', '300000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '0', '0'},
		ConfigCase{'INTERNAL_BUDGET_MS', '300000', '300000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '-1', 'INTERNAL_BUDGET_MS is "-1", out of range; accepted 0 to 300000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '-', 'INTERNAL_BUDGET_MS is "-", not a whole number; accepted 0 to 300000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '--5', 'INTERNAL_BUDGET_MS is "--5", not a whole number; accepted 0 to 300000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '5min', 'INTERNAL_BUDGET_MS is "5min", not a whole number; accepted 0 to 300000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '300001', 'INTERNAL_BUDGET_MS is "300001", out of range; accepted 0 to 300000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '18446744073709551616', 'INTERNAL_BUDGET_MS is "18446744073709551616", out of range; accepted 0 to 300000'},
		ConfigCase{'CORE_BACKEND', '', 'llm'},
		ConfigCase{'CORE_BACKEND', 'llm', 'llm'},
		ConfigCase{'CORE_BACKEND', 'cl1', 'cl1'},
		ConfigCase{'CORE_BACKEND', 'LLM', 'CORE_BACKEND is "LLM", not a known value; accepted llm, cl1'},
		ConfigCase{'CORE_BACKEND', 'cl2', 'CORE_BACKEND is "cl2", not a known value; accepted llm, cl1'},
		ConfigCase{'CORE_BACKEND', 'llm ', 'CORE_BACKEND is "llm ", not a known value; accepted llm, cl1'},
		ConfigCase{'CORE_BACKEND', '\x1b[2Jllm', 'CORE_BACKEND is "\\x1b[2Jllm", not a known value; accepted llm, cl1'},
		ConfigCase{'CORE_BACKEND', 'x'.repeat(100), 'CORE_BACKEND is "${'x'.repeat(64)}"..., not a known value; accepted llm, cl1'},
		ConfigCase{'BALTHASAR_BACKEND', '', 'jev.Endpoint'},
		ConfigCase{'BALTHASAR_BACKEND', 'jev', 'jev.Endpoint'},
		ConfigCase{'BALTHASAR_BACKEND', 'llm', 'oai.Endpoint'},
		ConfigCase{'BALTHASAR_BACKEND', 'Jev', 'BALTHASAR_BACKEND is "Jev", not a known value; accepted jev, llm'},
		ConfigCase{'BALTHASAR_BACKEND', 'gemma', 'BALTHASAR_BACKEND is "gemma", not a known value; accepted jev, llm'},
		ConfigCase{'BALTHASAR_BACKEND', 'j\xc3\xa9v', 'BALTHASAR_BACKEND is "j\\xc3\\xa9v", not a known value; accepted jev, llm'},
		ConfigCase{'BALTHASAR_BACKEND', 'jev"\\', 'BALTHASAR_BACKEND is "jev\\"\\\\", not a known value; accepted jev, llm'},
		ConfigCase{'BALTHASAR_BACKEND', 'jev\r\nmagi: forged', 'BALTHASAR_BACKEND is "jev\\x0d\\x0amagi: forged", not a known value; accepted jev, llm'},
		ConfigCase{'UNIT_ID', '', 'eva01'},
		ConfigCase{'UNIT_ID', 'eva-02', 'eva-02'},
		ConfigCase{'UNIT_ID', 'u'.repeat(32), 'u'.repeat(32)},
		ConfigCase{'UNIT_ID', 'u'.repeat(33), 'UNIT_ID is "${'u'.repeat(33)}", not a unit name; accepted 1 to 32 lowercase letters, digits and hyphens'},
		ConfigCase{'UNIT_ID', 'Eva01', 'UNIT_ID is "Eva01", not a unit name; accepted 1 to 32 lowercase letters, digits and hyphens'},
		ConfigCase{'UNIT_ID', '*', 'UNIT_ID is "*", not a unit name; accepted 1 to 32 lowercase letters, digits and hyphens'},
		ConfigCase{'UNIT_ID', 'eva01/goal', 'UNIT_ID is "eva01/goal", not a unit name; accepted 1 to 32 lowercase letters, digits and hyphens'},
		ConfigCase{'UNIT_ID', '$*', 'UNIT_ID is "$*", not a unit name; accepted 1 to 32 lowercase letters, digits and hyphens'},
		ConfigCase{'UNIT_ID', 'eva 01', 'UNIT_ID is "eva 01", not a unit name; accepted 1 to 32 lowercase letters, digits and hyphens'},
		ConfigCase{'UNIT_ID', 'eva01\nhq: forged', 'UNIT_ID is "eva01\\x0ahq: forged", not a unit name; accepted 1 to 32 lowercase letters, digits and hyphens'},
		ConfigCase{'UMBILICAL_KEY', '', ''},
		ConfigCase{'UMBILICAL_KEY', '0f'.repeat(32), '0f'.repeat(32)},
		ConfigCase{'UMBILICAL_KEY', 'A1b2'.repeat(16), 'a1b2'.repeat(16)},
		ConfigCase{'UMBILICAL_KEY', 'a'.repeat(63), 'UMBILICAL_KEY is not 64 hex digits; generate one with `openssl rand -hex 32`'},
		ConfigCase{'UMBILICAL_KEY', 'a'.repeat(65), 'UMBILICAL_KEY is not 64 hex digits; generate one with `openssl rand -hex 32`'},
		ConfigCase{'UMBILICAL_KEY', 'g'.repeat(64), 'UMBILICAL_KEY is not 64 hex digits; generate one with `openssl rand -hex 32`'},
		ConfigCase{'UMBILICAL_KEY', 'sk-or-v1-secret', 'UMBILICAL_KEY is not 64 hex digits; generate one with `openssl rand -hex 32`'},
		ConfigCase{'PILOT_KEY', '', ''},
		ConfigCase{'PILOT_KEY', 'aB'.repeat(32), 'ab'.repeat(32)},
		ConfigCase{'PILOT_KEY', 'shinji', 'PILOT_KEY is not 64 hex digits; generate one with `openssl rand -hex 32`'},
		ConfigCase{'UMBILICAL_ENDPOINT', '', 'tcp/127.0.0.1:7447'},
		ConfigCase{'UMBILICAL_ENDPOINT', 'tcp/0.0.0.0:7447', 'tcp/0.0.0.0:7447'},
	]
	for c in cases {
		os.unsetenv(c.key)
	}
	for c in cases {
		if c.val != '' {
			os.setenv(c.key, c.val, true)
		}
		got := if cfg := load_config() { config_value(cfg, c.key) } else { err.msg() }
		assert got == c.want, '${c}'

		// One printable line, whatever the value holds.
		assert got.bytes().all(it >= ` ` && it <= `~`), got
		os.unsetenv(c.key)
	}
}

// Whatever values the spans accept, a healthy HQ pulses the cable before the grace runs out,
// and the cooldown outlasts the pause, so it holds back the next deliberation.
fn test_accepted_timings_fit_together() {
	assert 2 * deadline_span.max + period_span.max < grace_span.min
	assert period_span.max < cooldown_span.min
}

struct CommandCase {
	args []string
	want string // the command, or the line command refuses the arguments with
}

fn test_command() {
	cases := [
		CommandCase{[]string{}, ''},
		CommandCase{['magi-eval'], 'magi-eval'},
		CommandCase{['magi-eval', '3', 'tools/scenarios.json'], 'magi-eval'},
		CommandCase{['hq'], 'hq'},
		CommandCase{['field'], 'field'},
		CommandCase{['hq', 'field'], 'hq takes no argument, not "field"'},
		CommandCase{['field', '--verbose\nfield: forged'], 'field takes no argument, not "--verbose\\x0afield: forged"'},
		CommandCase{['HQ'], 'command is "HQ", not a known value; accepted magi-eval, hq, field, or none to fly a mission'},
		CommandCase{['magi-evl', '3'], 'command is "magi-evl", not a known value; accepted magi-eval, hq, field, or none to fly a mission'},
		CommandCase{['--help'], 'command is "--help", not a known value; accepted magi-eval, hq, field, or none to fly a mission'},
		CommandCase{[''], 'command is "", not a known value; accepted magi-eval, hq, field, or none to fly a mission'},
		CommandCase{['3', 'magi-eval'], 'command is "3", not a known value; accepted magi-eval, hq, field, or none to fly a mission'},
		CommandCase{['magi-eval\nmagi: approved'], 'command is "magi-eval\\x0amagi: approved", not a known value; accepted magi-eval, hq, field, or none to fly a mission'},
	]
	for c in cases {
		got := command(c.args) or { err.msg() }
		assert got == c.want, '${c}'
	}
}

// magi-eval refuses an argument too many, and a scenario file it cannot read or decode, with exit
// code 2 and an error of one line, before it asks any unit.
fn test_magi_eval_refuses_unusable_arguments() {
	assert magi_eval(Config{}, ['3', 'tools/scenarios.json', 'x']) == 2
	assert magi_eval(Config{}, ['1', 'no\nsuch.json']) == 2
	garbled := os.join_path(os.temp_dir(), 'gehirn-garbled-scenarios.json')
	os.write_file(garbled, '{"scenarios": [')!
	defer {
		os.rm(garbled) or {}
	}
	for path, want in {
		'no\nsuch.json': 'cannot read: No such file or directory'
		garbled:         'not a scenario suite in JSON'
	} {
		got := if _ := load_suite(path) { 'loaded' } else { err.msg() }
		assert got == want, path
	}
}

struct BackendCase {
	backend string
	spikes  string
	sidecar string
	want    string // the start of the core's name, or of the line new_backend refuses it with
}

// A CL1 core that cannot bind its spike port or dial its sidecar is an error naming the variable
// and the cause, which main prints before it spawns anything.
fn test_new_backend() {
	// net.listen_udp sets SO_REUSEADDR on every UDP socket, and Linux lets two such sockets bind
	// one port, so with it left on here new_cl1 would bind too. macOS refuses either way.
	mut taken := net.listen_udp('127.0.0.1:0')!
	taken.sock.set_option_bool(.reuse_addr, false)!
	defer {
		taken.close() or {}
	}
	bound := net.addr_from_socket_handle(taken.sock.handle).str()
	cases := [
		BackendCase{'', '', '', 'llm:'},
		BackendCase{'cl1', bound, '', 'cl1: cannot listen on CL1_SPIKES ${bound}: net: socket error: '},
		BackendCase{'cl1', '127.0.0.1:0', '127.0.0.1:99999', 'cl1: cannot dial CL1_SIDECAR 127.0.0.1:99999: net: port out of range'},
	]
	for c in cases {
		os.setenv('CORE_BACKEND', c.backend, true)
		os.setenv('CL1_SPIKES', c.spikes, true)
		os.setenv('CL1_SIDECAR', c.sidecar, true)
		got := if b := new_backend(load_config()!) { b.name() } else { err.msg() }
		assert got.starts_with(c.want), '${c}: ${got}'
	}
	for key in ['CORE_BACKEND', 'CL1_SPIKES', 'CL1_SIDECAR'] {
		os.unsetenv(key)
	}
}

// Either end of the link refuses an endpoint Zenoh cannot read, naming the variable, before it
// starts a thread.
fn test_link_refuses_an_endpoint_zenoh_cannot_read() {
	cfg := Config{
		unit:     'eva01'
		link:     []u8{len: 32}
		endpoint: 'hq.local'
	}
	link_hq(cfg) or {
		assert err.msg() == 'UMBILICAL_ENDPOINT is "hq.local"; zenoh: config rejects listen/endpoints'
		link_field(cfg) or {
			assert err.msg() == 'UMBILICAL_ENDPOINT is "hq.local"; zenoh: config rejects connect/endpoints'
			return
		}
		assert false, 'the field linked to "hq.local"'
	}
	assert false, 'HQ listened on "hq.local"'
}

// FaultyCore never proposes, as a core whose model is down.
struct FaultyCore {}

fn (c FaultyCore) name() string {
	return 'faulty'
}

fn (mut c FaultyCore) propose(ctx lcl.Context) !lcl.Intent {
	return error('core: model down')
}

fn (mut c FaultyCore) feedback(o lcl.Outcome) {}

// A core that keeps faulting still lets HQ pulse after every deliberation, so the cable stays
// connected, but HQ sends no goal, so MAGI approves nothing (ADR-0004). The fault is said once.
fn test_a_faulting_core_keeps_hq_pulsing_and_approves_nothing() {
	journal := os.join_path(os.vtmp_dir(), 'gehirn_faulty_core_${os.getpid()}.jsonl')
	defer {
		os.rm(journal) or {}
	}
	inbox := chan lcl.Context{cap: 1}
	outbox := chan lcl.HqMsg{cap: 8}
	outcomes := chan lcl.Outcome{cap: 32}

	// V 0.5.2 emits C that does not compile for a struct literal spawned as an interface argument;
	// pass the literal directly once a V release compiles it.
	soul := core.Core(FaultyCore{})
	spawn hq(Config{ journal: journal, period_ms: 100 }, soul, inbox, outbox, outcomes)
	mut notes := []string{}
	for _ in 0 .. 3 {
		inbox <- lcl.Context{
			percept: lcl.Percept{
				pose: [0.0, 0.0]
			}
		}
		select {
			m := <-outbox {
				assert m.alive
				assert !m.approved
				notes << m.note
			}
			3 * time.second {
				assert false, 'HQ sent nothing after a core fault'
			}
		}
	}
	assert notes == ['hq: core fault: core: model down', '', '']
}
