// Restraint armor. The Eva's armor is really a restraint that holds it in check; this layer is
// the same idea: deterministic, no model inside, and the only thing that holds the body.
// main never gets a handle to it. On hardware this layer is duplicated on the motor
// controller behind a physical e-stop, because neither Linux nor Vinix is a real time system.
module armor

import math
import body
import lcl

// Limits are the armor's hard numbers. main.v hands them to restrain and their fence to every MAGI
// unit. core/llm.v core_prompt and the magi/magi.v personas repeat some in prose,
// tools/mock_endpoint.py FENCE and HUMAN_CLEARANCE in code, tools/scenarios.json S13 and S14
// release_keep in the words of Armor.refusal, and bridge/draw.v human_stop and release_keep as the
// scene's rings, so change them together: bounds is the -5 to 5 m fence, human_stop 0.7 m,
// human_slow 2 m, release_keep 2 m and, as center distance, 2.5 m (plus a 0.3 m human radius and a
// 0.2 m margin, so MAGI's release line sits outside the armor's; MAGI's percept is as old as the
// slowest ballot once their verdict lands, so the armor can refuse a release MAGI approved), and
// verbs goto, hold, release.
pub struct Limits {
pub:
	v_max        f64      = 1.0                    // m/s with a pilot or the dummy seated
	v_unmanned   f64      = 0.4                    // m/s when the core drives alone
	a_max        f64      = 1.5                    // m/s², speeding up only; braking is never limited
	bounds       []f64    = [-5.0, -5.0, 5.0, 5.0] // xmin, ymin, xmax, ymax
	solid_keep   f64      = 0.35                   // m: no motion into anything solid closer than this
	human_stop   f64      = 0.7                    // m: no motion toward a human closer than this
	human_slow   f64      = 2.0                    // m: speed and separation monitoring starts here
	release_keep f64      = 2.0                    // m: no irreversible effector with a human this close
	verbs        []string = ['goto', 'hold', 'release']
}

// Armor is the restraint that holds the body. main.v's field loop senses, drives and runs
// effectors only through it, and checks every approved goal against it (Invariants 1 and 5).
pub struct Armor {
	limits Limits
mut:
	bd      body.Body
	last    []f64
	ejected bool
}

// restrain takes the body. From here on nothing else holds it.
pub fn restrain(bd body.Body, limits Limits) Armor {
	return Armor{
		limits: limits
		bd:     bd
		last:   []f64{len: bd.dof()}
	}
}

// sense passes the body's percept through.
pub fn (mut a Armor) sense() lcl.Percept {
	return a.bd.sense()
}

// is_ejected reports whether the eject latch has tripped.
pub fn (a Armor) is_ejected() bool {
	return a.ejected
}

// permits is the capability check for a goal or an effector. A percept the armor cannot measure
// permits nothing.
pub fn (a Armor) permits(verb string, p lcl.Percept) bool {
	return a.refusal(verb, p) == ''
}

// refusal is why permits refuses verb on p, empty when it permits it. main.v's field loop puts it
// into the outcome of a refused goal, which the core and MAGI read in RECENT, so a unit learns
// that a refused release met a human within reach at that moment and was no flaw of the release.
// tools/scenarios.json S13 and S14 copy the reason for a release.
pub fn (a Armor) refusal(verb string, p lcl.Percept) string {
	if a.ejected {
		return 'the pilot had ejected'
	}
	if verb !in a.limits.verbs {
		return 'a verb the armor does not know'
	}
	if !a.measurable(p) {
		return 'a percept the armor could not measure'
	}
	if lcl.is_irreversible(verb) && nearest_human(p) < a.limits.release_keep {
		return 'a human was within ${a.limits.release_keep:.1f} m at that moment'
	}
	return ''
}

// effect runs an effector if permits allows it here and now.
pub fn (mut a Armor) effect(verb string, p lcl.Percept) ! {
	if !a.permits(verb, p) {
		return error('armor: ${verb} not permitted here')
	}
	a.bd.effect(verb)!
}

// eject latches. There is no un-eject; restart the process with a pilot present.
pub fn (mut a Armor) eject() {
	a.ejected = true
	a.bd.halt()
}

// drive pushes one command through every restraint, actuates, and returns what was sent. On a
// command or percept it cannot use, and when the body fails to actuate, it halts the body and
// returns zeros, so the next command ramps up from rest.
pub fn (mut a Armor) drive(u []f64, p lcl.Percept, dt f64, manned bool) []f64 {
	if a.ejected || u.len != a.last.len || !finite(u) || !a.measurable(p) {
		a.bd.halt()
		a.last = []f64{len: a.last.len}
		return a.last.clone()
	}
	vmax := if manned { a.limits.v_max } else { a.limits.v_unmanned }
	mut v := lcl.clamp_norm(u, vmax * a.separation(p))

	// Nothing pushes into anything solid, whoever is steering. What is left of the command
	// slides along the surface, so a pilot leaning into a pillar gets walked around it.
	for e in p.scene {
		if e.kind == 'beacon' {
			continue
		}
		keep := if e.kind == 'human' { a.limits.human_stop } else { a.limits.solid_keep }
		if lcl.dist(p.pose, e.pos) - e.r < keep {
			v = drop_toward(v, lcl.sub(e.pos, p.pose))
		}
	}
	if lcl.norm(v) > lcl.norm(a.last) {
		v = lcl.add(a.last, lcl.clamp_norm(lcl.sub(v, a.last), a.limits.a_max * dt))
	}
	b := a.limits.bounds
	if (p.pose[0] <= b[0] && v[0] < 0.0) || (p.pose[0] >= b[2] && v[0] > 0.0) {
		v[0] = 0.0
	}
	if (p.pose[1] <= b[1] && v[1] < 0.0) || (p.pose[1] >= b[3] && v[1] > 0.0) {
		v[1] = 0.0
	}
	a.bd.actuate(v) or {
		a.bd.halt()
		a.last = []f64{len: a.last.len}
		return a.last.clone()
	}
	a.last = v.clone()
	return v
}

// closeness is how close the nearest human is in the armor's own terms, for the A10 back channel:
// 0 at human_slow or further, 1 at human_stop or closer, linear between. A percept the armor
// cannot measure reads 1, since drive halts on it.
pub fn (a Armor) closeness(p lcl.Percept) f64 {
	if !a.measurable(p) {
		return 1.0
	}
	k := (a.limits.human_slow - nearest_human(p)) / (a.limits.human_slow - a.limits.human_stop)
	return math.min(1.0, math.max(0.0, k))
}

// separation scales speed down between human_slow and human_stop. Inside human_stop the
// machine may still creep, but drive has already removed every component toward the human.
fn (a Armor) separation(p lcl.Percept) f64 {
	d := nearest_human(p)
	if d >= a.limits.human_slow {
		return 1.0
	}
	return math.max(0.2, (d - a.limits.human_stop) / (a.limits.human_slow - a.limits.human_stop))
}

// measurable reports whether p has a finite pose with one coordinate per degree of freedom, and
// every entity a finite position of the same length and a finite radius. A NaN fails every
// comparison, so a human at a NaN position would pass the release_keep check. A position shorter
// than the pose would panic lcl.dist, and a longer one the lcl.sub(e.pos, p.pose) in drive.
fn (a Armor) measurable(p lcl.Percept) bool {
	return p.pose.len == a.last.len && finite(p.pose) && p.scene.all(it.pos.len == p.pose.len
		&& finite(it.pos) && math.is_finite(it.r))
}

fn finite(v []f64) bool {
	return v.all(math.is_finite(it))
}

fn nearest_human(p lcl.Percept) f64 {
	mut best := 1e9
	for e in p.scene {
		if e.kind == 'human' {
			best = math.min(best, lcl.dist(p.pose, e.pos) - e.r)
		}
	}
	return best
}

// drop_toward removes the part of v that points along dir.
fn drop_toward(v []f64, dir []f64) []f64 {
	n := lcl.norm(dir)
	if n == 0.0 {
		return v
	}
	k := lcl.dot(v, dir) / n
	if k <= 0.0 {
		return v
	}
	return lcl.sub(v, lcl.scale(dir, k / n))
}
