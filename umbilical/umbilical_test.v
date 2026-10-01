module umbilical

struct Step {
	name      string
	at        i64
	pulse     bool
	state     State
	remaining i64
}

fn test_state() {
	// One cable through a cut, depletion and two reconnects, with a grace of 1 s and a budget
	// of 5 s. The budget runs from the first look past the grace.
	mut c := plug_in(10_000, 5000, 1000)
	steps := [
		Step{'plugged in', 10_000, false, .connected, 5000},
		Step{'silent to the end of the grace', 11_000, false, .connected, 5000},
		Step{'cut past the grace', 11_001, false, .internal, 5000},
		Step{'internal to the last ms of the budget', 16_000, false, .internal, 1},
		Step{'depleted once the budget is spent', 16_001, false, .depleted, 0},
		Step{'a pulse reconnects a depleted cable', 16_500, true, .connected, 5000},
		Step{'silent to the end of the new grace', 17_500, false, .connected, 5000},
		Step{'a new cut gets the whole budget', 17_501, false, .internal, 5000},
		Step{'internal runs down', 19_501, false, .internal, 3000},
		Step{'a pulse reconnects an internal cable', 19_600, true, .connected, 5000},
		Step{'the grace restarts at the pulse', 20_600, false, .connected, 5000},
	]
	for s in steps {
		if s.pulse {
			c.pulse(s.at)
		}
		assert c.state(s.at) == s.state, s.name
		assert c.remaining_ms(s.at) == s.remaining, s.name
	}
}
