module main

import os
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
		b := magi_backend('BALTHASAR', 'gemma3:4b', '', 1000)
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
	b := magi_backend('BALTHASAR', 'gemma3:4b', '', 1000)
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
	units := load_config().units
	assert units.map(it.ep.type_name()) == ['oai.Endpoint', 'jev.Endpoint', 'oai.Endpoint']
}

// BALTHASAR-2 asks Jev unless told otherwise, and without TYPESAFE_API_KEY it says so at startup
// and faults every ballot, which blocks every irreversible proposal. No other backend steps in.
fn test_jev_without_key_fails_safe() {
	os.unsetenv('BALTHASAR_BACKEND')
	os.unsetenv('TYPESAFE_API_KEY')
	os.setenv('TYPESAFE_URL', 'http://127.0.0.1:9/v1/systemone', true)
	units := load_config().units
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
	assert key_warning(load_config().units) == ''
	os.setenv('BALTHASAR_BACKEND', 'llm', true)
	assert key_warning(load_config().units) == ''
}
