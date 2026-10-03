module umbilical

struct Step {
	name      string
	at        i64
	pulse     bool
	state     State
	remaining i64
	silent    i64
}

fn test_state() {
	// One cable through a cut, depletion and two reconnects, with a grace of 1 s and a budget
	// of 5 s. The budget runs from the first look past the grace.
	mut c := plug_in(10_000, 5000, 1000)
	steps := [
		Step{'plugged in', 10_000, false, .connected, 5000, 0},
		Step{'silent to the end of the grace', 11_000, false, .connected, 5000, 1000},
		Step{'cut past the grace', 11_001, false, .internal, 5000, 1001},
		Step{'internal to the last ms of the budget', 16_000, false, .internal, 1, 6000},
		Step{'depleted once the budget is spent', 16_001, false, .depleted, 0, 6001},
		Step{'a depleted budget stays at zero', 16_400, false, .depleted, 0, 6400},
		Step{'a pulse reconnects a depleted cable', 16_500, true, .connected, 5000, 0},
		Step{'silent to the end of the new grace', 17_500, false, .connected, 5000, 1000},
		Step{'a new cut gets the whole budget', 17_501, false, .internal, 5000, 1001},
		Step{'internal runs down', 19_501, false, .internal, 3000, 3001},
		Step{'a pulse reconnects an internal cable', 19_600, true, .connected, 5000, 0},
		Step{'the grace restarts at the pulse', 20_600, false, .connected, 5000, 1000},
	]
	for s in steps {
		if s.pulse {
			c.pulse(s.at)
		}
		assert c.state(s.at) == s.state, s.name
		assert c.remaining_ms(s.at) == s.remaining, s.name
		assert c.silent_ms(s.at) == s.silent, s.name
	}
}

fn test_cable_awaits_hq_until_the_first_pulse() {
	mut c := plug_in(10_000, 5000, 1000)
	assert c.awaiting()
	assert c.state(11_001) == .internal
	assert c.awaiting(), 'a cut before any pulse still awaits HQ'
	c.pulse(11_500)
	assert !c.awaiting()
	assert c.state(13_000) == .internal
	assert !c.awaiting(), 'a cut after a pulse no longer awaits HQ'
}
