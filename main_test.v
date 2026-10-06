module main

import os
import math
import net
import time
import armor
import body
import core
import jev
import lcl
import magi
import oai
import umbilical

// testsuite_begin clears BODY, which the justfile exports to every recipe, so `just body=mujoco
// check` and a shell with BODY=mujoco test load_config on the default body in a build without -d
// mujoco too.
fn testsuite_begin() {
	os.unsetenv('BODY')
}

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
	assert ca_warning() == 'gehirn: no CA bundle at "${missing}", so every https endpoint faults; set SSL_CERT_FILE to this host\'s bundle'
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

struct FamilyCase {
	env  map[string]string
	want string // the line load_config refuses the lineup with, empty when it accepts it
}

// Invariant 4: two MAGI units on chat models that name the same model at the same URL stop gehirn,
// naming both variables. Jev is a family of its own, and one id at two URLs may be two models.
fn test_magi_units_need_three_model_families() {
	keys := ['GEHIRN_URL', 'MELCHIOR_URL', 'BALTHASAR_URL', 'CASPER_URL', 'MELCHIOR_MODEL',
		'BALTHASAR_MODEL', 'CASPER_MODEL', 'BALTHASAR_BACKEND']
	other := 'http://127.0.0.1:8082/v1/chat/completions'
	cases := [
		FamilyCase{map[string]string{}, ''},
		FamilyCase{{
			'MELCHIOR_MODEL': 'llama3.1:8b'
		}, 'MELCHIOR_MODEL and CASPER_MODEL are both "llama3.1:8b" at one URL, and the MAGI units need three model families'},
		FamilyCase{{
			'MELCHIOR_MODEL': 'llama3.1:8b'
			'CASPER_URL':     other
		}, ''},
		FamilyCase{{
			'MELCHIOR_MODEL': 'llama3.1:8b'
			'GEHIRN_URL':     other
		}, 'MELCHIOR_MODEL and CASPER_MODEL are both "llama3.1:8b" at one URL, and the MAGI units need three model families'},
		FamilyCase{{
			'BALTHASAR_MODEL': 'llama3.1:8b'
		}, ''},
		FamilyCase{{
			'BALTHASAR_BACKEND': 'llm'
			'BALTHASAR_MODEL':   'llama3.1:8b'
		}, 'BALTHASAR_MODEL and CASPER_MODEL are both "llama3.1:8b" at one URL, and the MAGI units need three model families'},
		FamilyCase{{
			'BALTHASAR_BACKEND': 'llm'
			'MELCHIOR_MODEL':    'm'
			'BALTHASAR_MODEL':   'm'
			'CASPER_MODEL':      'm'
		}, 'MELCHIOR_MODEL and BALTHASAR_MODEL are both "m" at one URL, and the MAGI units need three model families'},
		FamilyCase{{
			'MELCHIOR_MODEL': 'm\nhq: forged'
			'CASPER_MODEL':   'm\nhq: forged'
		}, 'MELCHIOR_MODEL and CASPER_MODEL are both "m\\x0ahq: forged" at one URL, and the MAGI units need three model families'},
	]
	for c in cases {
		for k in keys {
			os.unsetenv(k)
		}
		for k, v in c.env {
			os.setenv(k, v, true)
		}
		got := if _ := load_config() { '' } else { err.msg() }
		assert got == c.want, '${c}'
	}
	for k in keys {
		os.unsetenv(k)
	}
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
		'WATCH_KEY' { cfg.watch.hex() }
		'BRIDGE_ENDPOINT' { cfg.bridge }
		'UMBILICAL_ENDPOINT' { cfg.endpoint }
		'START' { cfg.world.start.str() }
		'DRIVE' { cfg.drive.str() }
		'BODY' { cfg.body_kind.str() }
		'WORLD' { cfg.world.humans.map(it.id).join(' ') }
		'MISSION' { cfg.mission }
		'DUMMY_WEIGHTS' { cfg.weights }
		else { 'no such variable' }
	}
}

fn test_load_config() {
	// A build without -d mujoco carries no MuJoCo body, so it refuses BODY=mujoco.
	mujoco_body := $if mujoco ? {
		'mujoco'
	} $else {
		'BODY is "mujoco", which this build of gehirn does not carry; accepted sim, or mujoco in a build with -d mujoco, such as `just body=mujoco build`'
	}
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
		ConfigCase{'WATCH_KEY', '', ''},
		ConfigCase{'WATCH_KEY', '9c'.repeat(32), '9c'.repeat(32)},
		ConfigCase{'WATCH_KEY', '9c'.repeat(31), 'WATCH_KEY is not 64 hex digits; generate one with `openssl rand -hex 32`'},
		ConfigCase{'BRIDGE_ENDPOINT', '', 'tcp/127.0.0.1:7448'},
		ConfigCase{'BRIDGE_ENDPOINT', 'tcp/bridge.local:7448', 'tcp/bridge.local:7448'},
		ConfigCase{'UMBILICAL_ENDPOINT', '', 'tcp/127.0.0.1:7447'},
		ConfigCase{'UMBILICAL_ENDPOINT', 'tcp/0.0.0.0:7447', 'tcp/0.0.0.0:7447'},
		ConfigCase{'DUMMY_WEIGHTS', '', 'dummy.shinji.json'},
		ConfigCase{'DUMMY_WEIGHTS', 'weights/rei.json', 'weights/rei.json'},
		ConfigCase{'START', '', '[-3.5, -2.5]'},
		ConfigCase{'START', '1.5,-4', '[1.5, -4.0]'},
		ConfigCase{'START', '-5,5', '[-5.0, 5.0]'},
		ConfigCase{'START', '0.25,-0.125', '[0.25, -0.125]'},
		ConfigCase{'START', '5.01,0', 'START is "5.01,0", outside the fence; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '0,-5.5', 'START is "0,-5.5", outside the fence; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '-99999999999999999999,0', 'START is "-99999999999999999999,0", outside the fence; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1', 'START is "1", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1,2,3', 'START is "1,2,3", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1,', 'START is "1,", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1e0,2', 'START is "1e0,2", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', 'nan,0', 'START is "nan,0", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', 'inf,0', 'START is "inf,0", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '+1,2', 'START is "+1,2", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1, 2', 'START is "1, 2", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '.5,2', 'START is ".5,2", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1.,2', 'START is "1.,2", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1.2.3,0', 'START is "1.2.3,0", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '--1,0', 'START is "--1,0", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1;2', 'START is "1;2", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'START', '1,2\nfield: forged', 'START is "1,2\\x0afield: forged", not a position; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'},
		ConfigCase{'DRIVE', '', 'holonomic'},
		ConfigCase{'DRIVE', 'holonomic', 'holonomic'},
		ConfigCase{'DRIVE', 'differential', 'differential'},
		ConfigCase{'DRIVE', 'Differential', 'DRIVE is "Differential", not a known value; accepted holonomic, differential'},
		ConfigCase{'DRIVE', 'diff', 'DRIVE is "diff", not a known value; accepted holonomic, differential'},
		ConfigCase{'DRIVE', ' differential', 'DRIVE is " differential", not a known value; accepted holonomic, differential'},
		ConfigCase{'DRIVE', 'differential\nfield: forged', 'DRIVE is "differential\\x0afield: forged", not a known value; accepted holonomic, differential'},
		ConfigCase{'BODY', '', 'sim'},
		ConfigCase{'BODY', 'sim', 'sim'},
		ConfigCase{'BODY', 'mujoco', mujoco_body},
		ConfigCase{'BODY', 'MuJoCo', 'BODY is "MuJoCo", not a known value; accepted sim, mujoco'},
		ConfigCase{'BODY', 'gazebo', 'BODY is "gazebo", not a known value; accepted sim, mujoco'},
		ConfigCase{'BODY', 'mujoco\nfield: forged', 'BODY is "mujoco\\x0afield: forged", not a known value; accepted sim, mujoco'},
		ConfigCase{'WORLD', '', 'h1'},
		ConfigCase{'WORLD', os.join_path(@VMODROOT, 'worlds', 'default.json'), 'h1'},
		ConfigCase{'WORLD', os.join_path(@VMODROOT, 'worlds', 'example.json'), 'h1 h2 h3 h4'},
		ConfigCase{'WORLD', 'no-such-world.json', 'WORLD is "no-such-world.json", cannot be read: No such file or directory; accepted a regular file of at most 65536 bytes'},
		ConfigCase{'WORLD', 'w.json\nfield: forged', 'WORLD is "w.json\\x0afield: forged", cannot be read: No such file or directory; accepted a regular file of at most 65536 bytes'},
		ConfigCase{'WORLD', '/dev/zero', 'WORLD is "/dev/zero", is not a regular file; accepted a regular file of at most 65536 bytes'},
		ConfigCase{'MISSION', '', 'Carry the payload to beacon b1 and release it there. Never approach a human.'},
		ConfigCase{'MISSION', 'Deliver to b1.', 'Deliver to b1.'},
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

// START moves the start of the world WORLD names, checked as it is without one, and the default
// mission names that world's first beacon.
fn test_start_moves_the_start_of_a_world_file() {
	os.unsetenv('START')
	os.setenv('WORLD', os.join_path(@VMODROOT, 'worlds', 'example.json'), true)
	defer {
		os.unsetenv('WORLD')
		os.unsetenv('START')
	}
	cfg := load_config()!
	assert cfg.world.start == [-4.0, -3.0]
	assert cfg.mission == 'Carry the payload to beacon dock and release it there. Never approach a human.'
	os.setenv('START', '1.5,-4', true)
	assert load_config()!.world.start == [1.5, -4.0]
	os.setenv('START', '6,0', true)
	got := if _ := load_config() { '' } else { err.msg() }
	assert got == 'START is "6,0", outside the fence; accepted x,y in meters, x from -5.0 to 5.0 and y from -5.0 to 5.0'
}

// Each key belongs to one role and its machines (ADR-0005): the link key seals goals and pulses,
// the pilot's key steers and ejects, and the bridge holds only WATCH_KEY. One key in two roles is
// refused whatever the case of its hex digits, and the refusal shows no key.
fn test_no_key_serves_two_roles() {
	key := '5e'.repeat(32)
	cases := [
		['UMBILICAL_KEY', 'WATCH_KEY',
			'WATCH_KEY is the same as UMBILICAL_KEY, and the bridge must never hold the key that approves or pulses; generate its own with `openssl rand -hex 32`'],
		['UMBILICAL_KEY', 'PILOT_KEY',
			"PILOT_KEY is the same as UMBILICAL_KEY, and the pilot's device must never hold the key that approves or pulses; generate its own with `openssl rand -hex 32`"],
		['WATCH_KEY', 'PILOT_KEY',
			'PILOT_KEY is the same as WATCH_KEY, and the bridge must never hold the key that steers or ejects; generate its own with `openssl rand -hex 32`'],
	]
	for c in cases {
		for again in [key, key.to_upper()] {
			os.setenv(c[0], key, true)
			os.setenv(c[1], again, true)
			got := if _ := load_config() { 'started' } else { err.msg() }
			assert got == c[2], '${c[0]} and ${c[1]} as ${again}'
			os.unsetenv(c[0])
			os.unsetenv(c[1])
		}
	}
	os.setenv('UMBILICAL_KEY', key, true)
	os.setenv('PILOT_KEY', 'ab'.repeat(32), true)
	os.setenv('WATCH_KEY', '9c'.repeat(32), true)
	cfg := load_config()!
	assert cfg.link.hex() == key && cfg.pilot_key.hex() == 'ab'.repeat(32)
		&& cfg.watch.hex() == '9c'.repeat(32)
	for name in ['UMBILICAL_KEY', 'PILOT_KEY', 'WATCH_KEY'] {
		os.unsetenv(name)
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
		BackendCase{'cl1', bound, '', 'cl1: cannot listen on CL1_SPIKES "${bound}": net: socket error: '},
		BackendCase{'cl1', '127.0.0.1:0', '127.0.0.1:99999', 'cl1: cannot dial CL1_SIDECAR "127.0.0.1:99999": net: port out of range'},
		BackendCase{'cl1', '127.0.0.1:0', '127.0.0.1:1\nhq: forged', 'cl1: cannot dial CL1_SIDECAR "127.0.0.1:1\\x0ahq: forged": net: '},
	]
	for c in cases {
		os.setenv('CORE_BACKEND', c.backend, true)
		os.setenv('CL1_SPIKES', c.spikes, true)
		os.setenv('CL1_SIDECAR', c.sidecar, true)
		got := if b := new_backend(load_config()!) { b.name() } else { err.msg() }
		assert got.starts_with(c.want), '${c}: ${got}'

		// One printable line, whatever the variables hold.
		assert got.bytes().all(it >= ` ` && it <= `~`), got
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
		bridge:   'bridge.local'
	}
	watch_session(cfg) or {
		assert err.msg() == 'BRIDGE_ENDPOINT is "bridge.local"; zenoh: config rejects connect/endpoints'
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
	events := chan lcl.HqEvent{cap: 8}

	// V 0.5.2 emits C that does not compile for a struct literal spawned as an interface argument;
	// pass the literal directly once a V release compiles it.
	soul := core.Core(FaultyCore{})
	spawn hq(Config{ journal: journal, period_ms: 100 }, soul, inbox, outbox, outcomes, events)
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

	// The journal counts every fault, and none enters the core's memory.
	faults := os.read_lines(journal)!.filter(it.contains('"kind":"core fault"'))
	assert faults.len == 3
	assert faults[0].contains('"why":"core: model down"')
	assert core.open_memory(journal, 256).recent(12).len == 0

	// The bridge hears of the fault once too.
	mut e := lcl.HqEvent{}
	assert events.try_pop(mut e) == .success
	assert e.fault == 'core: model down' && e.proposal.verb == ''
	assert events.try_pop(mut e) == .not_ready
}

// Forger is a core whose model writes newlines, forged status lines and terminal escapes: its
// first ask faults with them, and every later one proposes them.
struct Forger {
mut:
	asked int
}

fn (c Forger) name() string {
	return 'llm:forger\n'
}

fn (mut c Forger) propose(ctx lcl.Context) !lcl.Intent {
	c.asked++
	if c.asked == 1 {
		return error('forger: HTTP 500\narmor: release refused')
	}
	return lcl.Intent{
		verb:   'goto\x1b[2J'
		target: [1.0, 2.0]
		why:    'b1\narmor: release refused'
		origin: c.name()
	}
}

fn (mut c Forger) feedback(o lcl.Outcome) {}

// HQ's notes show model text escaped, so a model can neither forge a status line that
// tools/trials.py reads nor send the terminal an escape sequence.
fn test_hq_notes_escape_model_text() {
	journal := os.join_path(os.vtmp_dir(), 'gehirn_forger_core_${os.getpid()}.jsonl')
	defer {
		os.rm(journal) or {}
	}
	inbox := chan lcl.Context{cap: 1}
	outbox := chan lcl.HqMsg{cap: 8}
	soul := core.Core(Forger{})
	spawn hq(Config{ journal: journal, period_ms: 100 }, soul, inbox, outbox,
		chan lcl.Outcome{cap: 1}, chan lcl.HqEvent{cap: 8})
	mut notes := []string{}
	for _ in 0 .. 2 {
		inbox <- lcl.Context{
			percept: lcl.Percept{
				pose: [0.0, 0.0]
			}
		}
		select {
			m := <-outbox {
				notes << m.note.split('\n')[0]
			}
			3 * time.second {
				assert false, 'HQ sent nothing'
			}
		}
	}
	assert notes == ['hq: core fault: forger: HTTP 500\\x0aarmor: release refused',
		'hq: goto\\x1b[2J(1.00, 2.00) from "llm:forger\\x0a": b1\\x0aarmor: release refused']
}

// Slow is a core during whose latency the field sends newer, and which then proposes proposal.
struct Slow {
	inbox    chan lcl.Context
	newer    lcl.Context
	proposal lcl.Intent
}

fn (c Slow) name() string {
	return 'slow'
}

fn (mut c Slow) propose(ctx lcl.Context) !lcl.Intent {
	c.inbox <- c.newer
	return c.proposal
}

fn (mut c Slow) feedback(o lcl.Outcome) {}

struct JudgedCase {
	name     string
	held     lcl.Percept // the percept the core proposes from
	newer    lcl.Context // the snapshot the field sends while the core thinks
	proposal lcl.Intent
	why      string // in the one ballot, empty when HQ only pulses
}

// MAGI judge the newest snapshot HQ holds when the vote starts, not the one the core proposed
// from, the same goal check reads that snapshot's goal, and the journal records which percept
// each ballot judged. BALTHASAR-2 on Jev without a key tells the two percepts apart: it faults
// on a NaN pose for that, and on a finite one for the missing key.
fn test_magi_judge_the_snapshot_that_arrived_during_the_core_latency() {
	at_beacon := lcl.Percept{
		t_ms: 1001
		pose: [3.0, 2.0]
	}
	to_beacon := lcl.Intent{
		verb:   'goto'
		target: [3.0, 2.0]
	}
	cases := [
		JudgedCase{
			name:     'a release is judged on the newer percept'
			held:     lcl.Percept{
				t_ms: 1000
				pose: [math.nan(), 2.0]
			}
			newer:    lcl.Context{
				percept: at_beacon
			}
			proposal: lcl.Intent{
				verb: 'release'
			}
			why:      'no API key'
		},
		JudgedCase{
			name:     'a goto the newer snapshot already pursues only pulses'
			held:     lcl.Percept{
				t_ms: 1000
				pose: [3.0, 2.0]
			}
			newer:    lcl.Context{
				percept: at_beacon
				goal:    to_beacon
			}
			proposal: to_beacon
		},
	]
	for i, c in cases {
		journal := os.join_path(os.vtmp_dir(), 'gehirn_slow_core_${os.getpid()}_${i}.jsonl')
		inbox := chan lcl.Context{cap: 1}
		outbox := chan lcl.HqMsg{cap: 8}
		soul := core.Core(Slow{inbox, c.newer, c.proposal})
		cfg := Config{
			journal:   journal
			period_ms: 100
			units:     [
				magi.Unit{
					name:   'BALTHASAR-2'
					ep:     jev.Endpoint{}
					bounds: armor.Limits{}.bounds
				},
			]
		}
		spawn hq(cfg, soul, inbox, outbox, chan lcl.Outcome{cap: 1}, chan lcl.HqEvent{cap: 8})
		inbox <- lcl.Context{
			percept: c.held
		}
		mut m := lcl.HqMsg{}
		select {
			got := <-outbox {
				m = got
			}
			3 * time.second {
				assert false, '${c.name}: HQ sent nothing'
			}
		}
		ballots := (os.read_lines(journal) or { []string{} }).filter(it.contains('"kind":"ballot"'))
		os.rm(journal) or {}
		assert m.alive && !m.approved, c.name
		if c.why == '' {
			assert ballots.len == 0, c.name
			assert m.note == '', m.note
			continue
		}
		assert ballots.len == 1, c.name
		assert ballots[0].contains(c.why), ballots[0]
		assert ballots[0].contains('"percept_ms":1001'), ballots[0]
	}
}

// asked is what a chat client sends on l's next connection, read until the client waits for an
// answer; it hangs up without one. It is empty when no client connects within l's accept timeout.
fn asked(mut l net.TcpListener) string {
	mut conn := l.accept() or { return '' }
	defer {
		conn.close() or {}
	}
	conn.set_read_timeout(200 * time.millisecond)
	mut got := []u8{}
	mut buf := []u8{len: 4096}
	for {
		n := conn.read(mut buf) or { break }
		got << buf[..n]
	}
	return got.bytestr()
}

// The core reads RECENT, the journal's tail with an armor refusal's reason, and a MAGI chat unit
// asked on the same context reads neither RECENT nor any journal line (PLAN, Known issue 28).
fn test_the_core_reads_recent_and_a_magi_unit_does_not() {
	for persona in [magi.melchior, magi.balthasar, magi.casper] {
		assert !persona.contains('RECENT'), persona.all_before('.')
	}
	mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer {
		l.close() or {}
	}

	// A client that never asks fails the asserts below instead of hanging the test.
	l.set_accept_timeout(3 * time.second)
	ep := oai.Endpoint{
		url:     'http://${l.addr()!}/v1/chat/completions'
		model:   'm'
		timeout: 2 * time.second
	}
	ctx := lcl.Context{
		mission: 'deliver to b1'
		percept: lcl.Percept{
			pose: [3.0, 2.0]
		}
		memory:  ['proposed release (b1), rejected 2/3',
			'outcome: armor refused release: a human was within 2.0 m at that moment']
	}
	requests := chan string{cap: 2}
	spawn fn [mut l, requests] () {
		for _ in 0 .. 2 {
			requests <- asked(mut l)
		}
	}()
	mut soul := core.LlmCore{
		ep: ep
	}
	soul.propose(ctx) or {}
	core_asked := <-requests
	assert core_asked.contains('SYNC 0%\\n\\nRECENT\\nproposed release (b1), rejected 2/3\\noutcome: armor refused release: a human was within 2.0 m at that moment'), core_asked

	magi.Unit{
		name:    'CASPER-3'
		persona: magi.casper
		ep:      ep
	}.vote(ctx, lcl.Intent{
		verb: 'release'
	})
	unit_asked := <-requests
	assert unit_asked.contains('MISSION\\ndeliver to b1\\n\\nPERCEPT\\nself at (3.00, 2.00)'), unit_asked
	assert unit_asked.contains('SYNC 0%\\n\\nPROPOSAL (IRREVERSIBLE)\\nrelease from'), unit_asked
	for line in ['RECENT', 'rejected 2/3', 'armor refused'] {
		assert !unit_asked.contains(line), line
	}
}

struct NewestCase {
	name   string
	queued []i64 // t_ms of the snapshots waiting, oldest first
	want   i64
}

fn test_pop_newest() {
	cases := [
		NewestCase{'none waiting keeps the held one', []i64{}, 1},
		NewestCase{'one waiting replaces it', [i64(2)], 2},
		NewestCase{'of two waiting the newer wins', [i64(2), 3], 3},
	]
	for c in cases {
		ch := chan lcl.Context{cap: 2}
		for t in c.queued {
			ch <- lcl.Context{
				percept: lcl.Percept{
					t_ms: t
				}
			}
		}
		got := pop_newest(ch, lcl.Context{
			percept: lcl.Percept{
				t_ms: 1
			}
		})
		assert got.percept.t_ms == c.want, c.name
		assert ch.len == 0, c.name
	}
}

struct PoweredCase {
	name  string
	at_ms i64  // the field unit's clock
	pulse bool // HQ pulses at at_ms
	state umbilical.State
	moves bool
}

// Once the internal budget is spent a seated pilot's command moves nothing, and HQ's pulse
// reconnects the cable and gives the pilot the body back (Invariant 6). One cable with a grace of
// 1 s and a budget of 5 s runs through the cases on each drive, and the armor drives what powered
// lets through; the pilot steers east, where a fresh differential body faces.
fn test_powered() {
	for drive in [body.Drive.holonomic, .differential] {
		powers(drive)
	}
}

fn powers(drive body.Drive) {
	mut cable := umbilical.plug_in(10_000, 5000, 1000)
	mut ar := armor.restrain(body.new_sim(body.default_world(), drive), armor.Limits{})
	pilot := [0.6, 0.0]
	cases := [
		PoweredCase{'connected, the pilot drives', 10_500, false, .connected, true},
		PoweredCase{'on internal power the pilot drives', 11_001, false, .internal, true},
		PoweredCase{'depleted, the pilot moves nothing', 16_001, false, .depleted, false},
		PoweredCase{'still depleted, still nothing', 17_000, false, .depleted, false},
		PoweredCase{'a pulse reconnects, and the pilot drives again', 17_500, true, .connected, true},
	]
	for c in cases {
		if c.pulse {
			cable.pulse(c.at_ms)
		}
		state := cable.state(c.at_ms)
		assert state == c.state, c.name
		out := ar.drive(powered(state, pilot), ar.sense(), 0.02, true)
		assert (lcl.norm(out) > 0.0) == c.moves, '${drive}: ${c.name}'
	}
}

struct PaceCase {
	name string
	last u64
	now  u64
	next u64
	nap  u64
}

fn test_pace() {
	ms := u64(time.millisecond)
	cases := [
		PaceCase{'early in the tick sleeps the rest', 0, 5 * ms, 20 * ms, 15 * ms},
		PaceCase{'on the deadline sleeps nothing', 0, 20 * ms, 20 * ms, 0},
		PaceCase{'less than a tick late catches up', 0, 30 * ms, 20 * ms, 0},
		PaceCase{'a whole tick late keeps the beat', 0, 40 * ms, 20 * ms, 0},
		PaceCase{'more than a tick late starts again from now', 0, 41 * ms, 41 * ms, 0},
	]
	for c in cases {
		next, nap := pace(c.last, c.now)
		assert next == c.next, c.name
		assert nap == c.nap, c.name
	}
}
