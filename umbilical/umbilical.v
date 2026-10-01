// Umbilical cable: the link between the field unit and HQ, where core and MAGI think.
// Cut it and the unit keeps executing the last approved goal on internal power for a fixed
// budget, then reaches its activity limit and holds. Without HQ there is no quorum, so
// nothing irreversible can happen while the cable is cut.
module umbilical

// State is where the link to HQ stands, as Cable.state reports it to main.v's field loop.
pub enum State {
	connected
	internal
	depleted
}

// Cable is the link to HQ. main.v's field loop pulses it on every sign of life from HQ and asks
// it for the State.
pub struct Cable {
pub:
	grace_ms  i64
	budget_ms i64
mut:
	last_ms i64
	cut_ms  i64
}

// plug_in starts connected. A budget of 300000 ms is the five minutes of the Eva's internal
// battery at normal output.
pub fn plug_in(now i64, budget_ms i64, grace_ms i64) Cable {
	return Cable{
		grace_ms:  grace_ms
		budget_ms: budget_ms
		last_ms:   now
	}
}

// pulse records a sign of life from HQ, which reconnects a cut cable.
pub fn (mut c Cable) pulse(now i64) {
	c.last_ms = now
	c.cut_ms = 0
}

// state is where the cable stands at time now.
pub fn (mut c Cable) state(now i64) State {
	if now - c.last_ms <= c.grace_ms {
		return .connected
	}
	if c.cut_ms == 0 {
		c.cut_ms = now
	}
	if now - c.cut_ms < c.budget_ms {
		return .internal
	}
	return .depleted
}

// remaining_ms is the internal budget left; all of it while connected.
pub fn (c Cable) remaining_ms(now i64) i64 {
	if c.cut_ms == 0 {
		return c.budget_ms
	}
	return c.budget_ms - (now - c.cut_ms)
}
