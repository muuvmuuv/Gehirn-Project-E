// LCL: the medium every layer is immersed in. Plain data plus a few vector helpers,
// so any transport can carry it: channels in process today, Zenoh across machines later.
module lcl

import math
import time

// Verbs the stack knows. Anything unknown counts as irreversible, so it needs all three MAGI
// and still has to pass the armor's capability list. Irreversibility is policy, never
// something a proposal gets to declare about itself. core/llm.v core_prompt and the magi/magi.v
// personas name these verbs in prose, magi/jev.v means describes each, and
// tools/mock_endpoint.py VERBS copies them.
pub const known_verbs = ['goto', 'hold', 'release']
pub const irreversible_verbs = ['release']

// A goto counts as reached inside this radius, in meters. tools/pilot.py ARRIVE copies it.
pub const arrive = 0.35

// beacon_reach is how close to a beacon's center, in meters, the body counts as at the beacon,
// where a release may happen. core/llm.v core_prompt and the magi/magi.v personas state it in
// prose and tools/mock_endpoint.py BEACON_REACH copies it; main.v counts a release on target
// 0.1 m further out, as magi/jev.v jev_delivery does.
pub const beacon_reach = 0.5

pub struct Entity {
pub:
	id   string
	kind string // obstacle, beacon, human
	pos  []f64
	r    f64
}

pub struct Percept {
pub:
	t_ms    i64
	pose    []f64
	vel     []f64
	scene   []Entity
	payload bool
	contact bool
}

pub struct Intent {
pub:
	verb   string
	target []f64
	why    string
	origin string
}

pub struct Outcome {
pub:
	t_ms i64
	kind string
	good bool
}

pub struct PilotInput {
pub:
	t_ms  i64
	pilot string
	u     []f64
	eject bool
}

// Context is everything HQ gets to see: one snapshot of the field plus the soul's recent memory.
pub struct Context {
pub:
	mission string
	percept Percept
	goal    Intent
	seat    string // pilot, dummy or empty
	sync    f64
	memory  []string
}

// is_irreversible reports whether a verb needs all three MAGI. Unknown verbs do.
pub fn is_irreversible(verb string) bool {
	return verb !in known_verbs || verb in irreversible_verbs
}

// now_ms is wall clock time in milliseconds, the time base of every LCL message.
pub fn now_ms() i64 {
	return time.now().unix_milli()
}

// label renders an intent as verb(x, y) for logs and prompts.
// tools/mock_endpoint.py PROPOSAL parses this layout.
pub fn (i Intent) label() string {
	if i.target.len >= 2 {
		return '${i.verb}(${i.target[0]:.2f}, ${i.target[1]:.2f})'
	}
	return i.verb
}

// describe renders a percept as text for language backends.
// tools/mock_endpoint.py parses this layout.
pub fn (p Percept) describe() string {
	mut lines := [
		'self at (${p.pose[0]:.2f}, ${p.pose[1]:.2f}), carrying payload: ${p.payload}, in contact: ${p.contact}',
	]
	for e in p.scene {
		d := dist(p.pose, e.pos)
		lines << '${e.kind} ${e.id} at (${e.pos[0]:.2f}, ${e.pos[1]:.2f}), radius ${e.r:.2f}, distance ${d:.2f}'
	}
	return lines.join('\n')
}

// render is the one view of the world that every language backend and every MAGI unit reads.
// tools/mock_endpoint.py parses this layout.
pub fn (c Context) render() string {
	memory := if c.memory.len == 0 { '(none)' } else { c.memory.join('\n') }
	sync_pct := c.sync * 100.0
	return 'MISSION\n${c.mission}\n\nPERCEPT\n${c.percept.describe()}\n\nACTIVE GOAL\n${c.goal.label()}\n\nSEAT ${c.seat}, SYNC ${sync_pct:.0f}%\n\nRECENT\n${memory}'
}

// dot is the scalar product of a and b.
pub fn dot(a []f64, b []f64) f64 {
	mut s := 0.0
	for i in 0 .. math.min(a.len, b.len) {
		s += a[i] * b[i]
	}
	return s
}

// norm is the Euclidean length of a.
pub fn norm(a []f64) f64 {
	return math.sqrt(dot(a, a))
}

// add is a plus b, element by element.
pub fn add(a []f64, b []f64) []f64 {
	return []f64{len: a.len, init: a[index] + b[index]}
}

// sub is a minus b, element by element.
pub fn sub(a []f64, b []f64) []f64 {
	return []f64{len: a.len, init: a[index] - b[index]}
}

// scale is a times k.
pub fn scale(a []f64, k f64) []f64 {
	return a.map(it * k)
}

// dist is the Euclidean distance between a and b.
pub fn dist(a []f64, b []f64) f64 {
	return norm(sub(a, b))
}

// clamp_norm shortens a vector to at most max, keeping its direction.
pub fn clamp_norm(a []f64, max f64) []f64 {
	n := norm(a)
	if n <= max || n == 0.0 {
		return a.clone()
	}
	return scale(a, max / n)
}

// blend is shared control: authority 0 is all pilot, 1 is all core.
pub fn blend(pilot []f64, own []f64, authority f64) []f64 {
	return []f64{len: own.len, init: (1.0 - authority) * pilot[index] + authority * own[index]}
}
