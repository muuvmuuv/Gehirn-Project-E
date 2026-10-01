module main

import os
import net
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
		else { 'no such variable' }
	}
}

fn test_load_config() {
	cases := [
		ConfigCase{'MAGI_TIMEOUT_MS', '', '10000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '2500', '2500'},
		ConfigCase{'MAGI_TIMEOUT_MS', '1', '1'},
		ConfigCase{'MAGI_TIMEOUT_MS', '3600000', '3600000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '10s', 'MAGI_TIMEOUT_MS is "10s", not a whole number; accepted 1 to 3600000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '0', 'MAGI_TIMEOUT_MS is "0", out of range; accepted 1 to 3600000'},
		ConfigCase{'MAGI_TIMEOUT_MS', '3600001', 'MAGI_TIMEOUT_MS is "3600001", out of range; accepted 1 to 3600000'},
		ConfigCase{'CORE_TIMEOUT_MS', '', '10000'},
		ConfigCase{'CORE_TIMEOUT_MS', '20000', '20000'},
		ConfigCase{'CORE_TIMEOUT_MS', 'abc', 'CORE_TIMEOUT_MS is "abc", not a whole number; accepted 1 to 3600000'},
		ConfigCase{'CORE_TIMEOUT_MS', '99999999999', 'CORE_TIMEOUT_MS is "99999999999", out of range; accepted 1 to 3600000'},
		ConfigCase{'HQ_PERIOD_MS', '', '1500'},
		ConfigCase{'HQ_PERIOD_MS', '500', '500'},
		ConfigCase{'HQ_PERIOD_MS', '1.5', 'HQ_PERIOD_MS is "1.5", not a whole number; accepted 1 to 3600000'},
		ConfigCase{'HQ_PERIOD_MS', '-1500', 'HQ_PERIOD_MS is "-1500", out of range; accepted 1 to 3600000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '', '10000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '30000', '30000'},
		ConfigCase{'MAGI_COOLDOWN_MS', ' 30000', 'MAGI_COOLDOWN_MS is " 30000", not a whole number; accepted 1 to 3600000'},
		ConfigCase{'MAGI_COOLDOWN_MS', '0', 'MAGI_COOLDOWN_MS is "0", out of range; accepted 1 to 3600000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '', '300000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '60000', '60000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '5min', 'INTERNAL_BUDGET_MS is "5min", not a whole number; accepted 1 to 3600000'},
		ConfigCase{'INTERNAL_BUDGET_MS', '9223372036854775808', 'INTERNAL_BUDGET_MS is "9223372036854775808", out of range; accepted 1 to 3600000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '', '45000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '1000', '1000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '45e3', 'UMBILICAL_GRACE_MS is "45e3", not a whole number; accepted 1 to 3600000'},
		ConfigCase{'UMBILICAL_GRACE_MS', '-1', 'UMBILICAL_GRACE_MS is "-1", out of range; accepted 1 to 3600000'},
		ConfigCase{'CORE_BACKEND', '', 'llm'},
		ConfigCase{'CORE_BACKEND', 'llm', 'llm'},
		ConfigCase{'CORE_BACKEND', 'cl1', 'cl1'},
		ConfigCase{'CORE_BACKEND', 'LLM', 'CORE_BACKEND is "LLM", not a known value; accepted llm, cl1'},
		ConfigCase{'CORE_BACKEND', 'cl2', 'CORE_BACKEND is "cl2", not a known value; accepted llm, cl1'},
		ConfigCase{'BALTHASAR_BACKEND', '', 'jev.Endpoint'},
		ConfigCase{'BALTHASAR_BACKEND', 'jev', 'jev.Endpoint'},
		ConfigCase{'BALTHASAR_BACKEND', 'llm', 'oai.Endpoint'},
		ConfigCase{'BALTHASAR_BACKEND', 'Jev', 'BALTHASAR_BACKEND is "Jev", not a known value; accepted jev, llm'},
		ConfigCase{'BALTHASAR_BACKEND', 'gemma', 'BALTHASAR_BACKEND is "gemma", not a known value; accepted jev, llm'},
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
		os.unsetenv(c.key)
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
