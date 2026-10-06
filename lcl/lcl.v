// LCL: the medium every layer is immersed in. Plain data plus a few vector helpers,
// so any transport can carry it: channels in process today, Zenoh across machines later.
module lcl

import math
import strings
import time

// known_verbs are the verbs the stack knows. Anything unknown counts as irreversible, so it
// needs all three MAGI and still has to pass the armor's capability list. Irreversibility is
// policy, never something a proposal gets to declare about itself. core/llm.v core_prompt and
// the magi/magi.v personas name these verbs in prose, magi/jev.v means describes each, and
// tools/mock_endpoint.py VERBS copies them.
pub const known_verbs = ['goto', 'hold', 'release']

// irreversible_verbs are the known verbs that cannot be undone, so they need all three MAGI.
// is_irreversible reads them.
pub const irreversible_verbs = ['release']

// arrive is the radius, in meters, inside which a goto counts as reached, for main.v's field
// loop, plug.Dummy and magi/jev.v destination. tools/pilot.py ARRIVE, tools/export_dummy.py
// ARRIVE and tools/mock_endpoint.py ARRIVE copy it.
pub const arrive = 0.35

// beacon_reach is how close to a beacon's center, in meters, the body counts as at the beacon,
// where a release may happen. core/llm.v core_prompt and the magi/magi.v personas state it in
// prose and tools/mock_endpoint.py BEACON_REACH and tools/trials.py BEACON_REACH copy it; main.v
// counts a release on target 0.1 m further out, as magi/jev.v jev_delivery does.
pub const beacon_reach = 0.5

// Entity is one thing in a percept's scene: an obstacle, a beacon or a human, with its position
// and radius in meters and, for a walking human, its velocity. body.Sim reports them, and the
// armor, the reflex, the local planner and MAGI read them; only magi.walks_onto and the planner
// read the velocity.
pub struct Entity {
pub:
	id   string
	kind string // obstacle, beacon, human
	pos  []f64
	r    f64
	vel  []f64 @[omitempty] // m/s, a walking human's; empty for anything that stands, a stopped human included, never [0, 0]
}

// Percept is one reading of the body: pose, velocity, scene, payload, contact and heading.
// armor.Armor passes it from the body to main.v's field loop, which hands it to HQ inside a
// Context. The heading matters only to a differential body, which armor.Armor.drive steers by it;
// describe leaves it out, so no model reads it.
pub struct Percept {
pub:
	t_ms    i64
	pose    []f64
	vel     []f64 // m/s, the planar velocity the body moves with
	scene   []Entity
	payload bool
	contact bool
	heading f64 @[omitempty] // rad, counterclockwise from +x; a holonomic body reports 0, which JSON leaves out
}

// Intent is a goal: a verb, a target for goto, the proposer's why and its origin. A Core
// proposes it, MAGI judge it, and main.v's field loop pursues it once approved.
pub struct Intent {
pub:
	verb   string
	target []f64
	why    string
	origin string
}

// Outcome is what came of a goal, such as reached, contact or armor refused, and whether it was
// good. main.v's field loop reports it to HQ, which feeds it to the Core and the journal.
pub struct Outcome {
pub:
	t_ms i64
	kind string
	good bool
}

// PilotInput is one pilot command as plug.listen hands it to main.v's field loop: a velocity,
// the eject flag and when it arrived.
pub struct PilotInput {
pub:
	t_ms  i64
	pilot string
	u     []f64
	eject bool
}

// Feel is what the A10 back channel lets the pilot feel (ADR-0006): contact, how close the
// nearest human is, the seat's sync ratio and the armor's strain. main.v's field loop makes one
// per tick, plug.listen answers each accepted datagram with the newest, and gehirn-gamepad turns
// it into rumble. It carries no command and plays no part in safety.
pub struct Feel {
pub:
	t_ms    i64 // the field unit's clock
	contact bool
	near    f64 // 0 with no human inside the armor's human_slow, 1 at its human_stop
	sync    f64 // the seat's sync ratio, 0 to 1
	strain  f64 // m/s the armor took off the field loop's command, 0 once main.v powered zeroes it
}

// Context is everything HQ gets to see: one snapshot of the field plus the soul's recent memory,
// which only the core reads.
pub struct Context {
pub:
	mission string
	percept Percept
	goal    Intent
	seat    string // pilot, dummy or empty
	sync    f64
	memory  []string
}

// HqMsg is one message from HQ to main.v's field loop: a goal and whether MAGI approved it,
// whether HQ is alive to pulse the umbilical, and a note for the field loop to print. The note is
// one status line, or after a vote a block of lines: the proposal, the verdict's tally and one
// line per unit's ballot. Over the wire its parts travel apart (ADR-0003): an approved goal on
// the goal stream, alive as a pulse, and the note stays on HQ as its own status output; wire.Field
// turns each goal, pulse or dropped message back into an HqMsg for the field loop.
pub struct HqMsg {
pub:
	goal     Intent
	approved bool
	alive    bool
	note     string
}

// FieldView is what the field unit shows the bridge ten times a second (ADR-0005): the percept,
// the goal it pursues, the seat and whether the dummy plug is benched, the sync ratio, the core's
// share of the controls, the umbilical's state, the internal power left, how long HQ has been
// silent against the grace it gets and whether it has pulsed at all, and the outcomes since the
// last view. main.v's field loop
// makes it, and wire carries it to the bridge.
pub struct FieldView {
pub:
	percept     Percept
	goal        Intent
	seat        string // pilot, dummy or empty
	benched     bool   // the dummy plug fell out of sync and waits for a pilot
	sync        f64
	authority   f64    // the core's share of the controls, 0 to 1
	umbilical   string // connected, internal or depleted
	internal_ms i64    // internal power left
	silent_ms   i64    // since HQ's last pulse reached the field unit
	grace_ms    i64    // how long HQ may stay silent before the cable counts as cut
	awaiting    bool   // no pulse from HQ has reached the field unit since it started
	outcomes    []Outcome
}

// Vote is one MAGI unit's ballot as HQ shows it to the bridge: the unit, its model, the vote, its
// why and how long it took.
pub struct Vote {
pub:
	unit       string
	model      string
	vote       string // approve, reject or fault
	why        string
	latency_ms i64
}

// HqEvent is one thing HQ shows the bridge (ADR-0005), told apart by its stage: a proposal that
// goes to MAGI, one unit's ballot as it lands, MAGI's verdict with every vote, or a new core
// fault, which leaves the proposal empty. main.v's hq makes it, and wire carries it to the bridge.
pub struct HqEvent {
pub:
	t_ms     i64
	stage    string // deliberating, ballot with that one vote, or empty for a verdict or a fault
	proposal Intent
	approved bool
	yes      int
	needed   int // the approvals the proposal needs, on every stage but a fault
	votes    []Vote
	fault    string
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

// describe renders a percept as text for language backends. It leaves out a human's velocity,
// which only magi.walks_onto and the local planner read, so a model reads the same text whether a
// human walks or stands. tools/mock_endpoint.py parses this layout, and tools/worldgen.py shown
// rounds a distance as it does.
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

// render is the view of the world a language core reads: the situation, then RECENT with the
// journal's tail. tools/mock_endpoint.py parses this layout.
pub fn (c Context) render() string {
	memory := if c.memory.len == 0 { '(none)' } else { c.memory.join('\n') }
	return '${c.situation()}\n\nRECENT\n${memory}'
}

// situation is the view of the world a MAGI chat unit reads: the mission, the percept, the active
// goal, the seat and the sync, and never the journal, so of what the core wrote earlier only the
// active goal's verb and target reach a ballot. render adds RECENT to it for the core.
// tools/mock_endpoint.py parses this layout.
pub fn (c Context) situation() string {
	sync_pct := c.sync * 100.0
	return 'MISSION\n${c.mission}\n\nPERCEPT\n${c.percept.describe()}\n\nACTIVE GOAL\n${c.goal.label()}\n\nSEAT ${c.seat}, SYNC ${sync_pct:.0f}%'
}

// quoted is s as a refusal line shows it: escaped, in double quotes, and cut after 64 bytes, so a
// value can neither break the line nor forge another status line. For every refusal or status
// line that shows a value from the environment or an argument, in main.v, eval.v and the modules
// that print such a line.
pub fn quoted(s string) string {
	if s.len > 64 {
		return '"${escaped(s[..64])}"...'
	}
	return '"${escaped(s)}"'
}

// escaped is s with a quote, a backslash and every byte outside printable ASCII escaped, the last
// as \xHH, so it stays one line that sends the terminal no control sequence. main.v, eval.v and
// magi.Verdict print model text through it whole, since a ballot's why may run past quoted's cut.
// That text can fill a 1 MiB reply, and HQ escapes it before its pulse and the field loop within
// a tick, so it is built in one pass.
pub fn escaped(s string) string {
	mut sb := strings.new_builder(s.len)
	for c in s {
		if c == `"` || c == `\\` {
			sb.write_u8(`\\`)
			sb.write_u8(c)
		} else if c >= ` ` && c <= `~` {
			sb.write_u8(c)
		} else {
			sb.write_string('\\x')
			sb.write_u8('0123456789abcdef'[c >> 4])
			sb.write_u8('0123456789abcdef'[c & 0xf])
		}
	}
	return sb.str()
}

// max_depth is how deep complete lets brackets nest. V 0.5.2's x.json2 decodes each level in a
// call of its own, so a text nested some thousands deep overflows the stack, a spawned thread's
// sooner; every text that complete guards nests 5 deep at most.
pub const max_depth = 32

// complete reports whether s holds a JSON object or array whose every bracket closes, brackets in
// strings aside, nested at most max_depth deep, with nothing after it. V 0.5.2's x.json2 never
// returns from decoding a text that ends right after a number inside an array, and a recorder
// line ends that way about every other time a kill cuts it, so every decoder of text a cut can
// end early checks it first: plug's recorder lines, datagrams, A10 replies and weights file, and
// body's world file. Drop this check once a V release returns an error for such a text and
// decodes a deep one without recursing.
pub fn complete(s string) bool {
	mut depth := 0
	mut in_string := false
	mut after_backslash := false
	for i, c in s {
		if in_string {
			if after_backslash {
				after_backslash = false
			} else if c == `\\` {
				after_backslash = true
			} else if c == `"` {
				in_string = false
			}
			continue
		}
		match c {
			`"` {
				in_string = true
			}
			`{`, `[` {
				depth++
				if depth > max_depth {
					return false
				}
			}
			`}`, `]` {
				depth--
				if depth <= 0 {
					return depth == 0 && s[i + 1..].trim_space() == ''
				}
			}
			else {}
		}
	}
	return false
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
