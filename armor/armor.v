// Restraint armor. The Eva's armor is really a restraint that holds it in check; this layer is
// the same idea: deterministic, no model inside, and the only thing that holds the body.
// main never gets a handle to it. On hardware this layer is duplicated on the motor
// controller behind a physical e-stop, because neither Linux nor Vinix is a real time system.
module armor

import math
import body
import lcl

// Limits are the armor's hard numbers. main.v hands them to restrain, their fence to every MAGI
// unit and their keeps and fence to the local planner. core/llm.v core_prompt and the magi/magi.v
// personas repeat some in prose, magi/magi.v course_speed v_max, tools/mock_endpoint.py FENCE and
// HUMAN_CLEARANCE, tools/trials.py HUMAN_STOP, planner/planner_test.v solid_keep, human_stop and
// top and tools/worldgen.py the speeds, a_max and the keeps in code, tools/scenarios.json S13 and
// S14 release_keep in the words of Armor.refusal, bridge/draw.v human_stop and release_keep as
// the scene's rings, and body/world.v mover_keep_min v_max and a_max through the MuJoCo base's
// braking, so change them together: v_max is 1 m/s, bounds the -5 to 5 m fence,
// human_stop 0.7 m, human_slow 2 m, release_keep 2 m and, as center distance, 2.5 m (plus a 0.3 m
// human radius and a 0.2 m margin, so MAGI's release line sits outside the armor's; MAGI's percept
// is as old as the slowest ballot once their verdict lands, so the armor can refuse a release MAGI
// approved), and verbs goto, hold, release.
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
	last    []f64 // m/s, the planar velocity the body moves with since the last drive
	ejected bool
}

// still is the speed, in m/s, below which drive takes a part of a body's motion for rounding:
// steered along the slide past a pillar, the cosine and sine of a differential body's heading
// leave about 1e-16 m/s toward the pillar, and a drop as little. tools/worldgen.py STILL copies it.
const still = 1e-9

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

// truth passes the body's ground truth through, the scene as it stood at the last sense, which
// main.v's field loop writes into the recorder alone under SENSING=range, so measurements read the
// world rather than what the stack sensed. Nothing restrains or decides on it (ADR-0011).
pub fn (a Armor) truth() []lcl.Entity {
	return a.bd.truth()
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
// into the outcome of a refused goal, which the core reads in RECENT, so it learns that a refused
// release met a human within reach at that moment and was no flaw of the release.
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

// drive pushes one planar command through every restraint, actuates, and returns the planar
// velocity the body moves with: on a holonomic body the restrained command itself, which keeps
// every restraint allows checks. A differential body gets the Course body.steer makes of the
// command, no faster than fastest allows, and its motion along the body's heading can point where
// the restraints removed from the command, so drive checks that motion against them again and
// sends a turn in place instead of any motion that breaks one. A body that moves on along a motion
// once a command takes it out gets the keeps and the fence widened by what its stopping reports
// at the speed it may reach, so it stands before them. On a command or percept it cannot use, a
// stopping distance that is negative, NaN or infinite, and when the body fails to actuate, it
// halts the body and returns zeros, so the next command ramps up from rest.
pub fn (mut a Armor) drive(u []f64, p lcl.Percept, dt f64, manned bool) []f64 {
	// The fastest the body may move until the next command: the faster of the motion drive sent
	// last and the velocity the body reports, sped up by a_max. math.max returns its second
	// argument when that is NaN, so stopping sees a NaN velocity.
	speed := math.max(lcl.norm(a.last), lcl.norm(p.vel)) + a.limits.a_max * dt
	coast := a.bd.stopping(speed)
	if a.ejected || u.len != a.last.len || !finite(u) || !a.measurable(p) || !math.is_finite(coast)
		|| coast < 0.0 {
		a.bd.halt()
		a.last = []f64{len: a.last.len}
		return a.last.clone()
	}
	vmax := (if manned { a.limits.v_max } else { a.limits.v_unmanned }) * ground_factor(p, coast +
		speed * dt)
	mut v := lcl.clamp_norm(u, vmax * a.separation(p))

	// Nothing pushes into anything solid, whoever is steering. What is left of the command
	// slides along the surface, so a pilot leaning into a pillar gets walked around it. A
	// differential body starts to slide body.lead early, so it reaches the keep heading along the
	// slide, and slides body.shy away from what it slides along.
	mut lead := 0.0
	mut tilt := 0.0
	match a.bd.drive() {
		.holonomic {}
		.differential {
			lead = body.lead(lcl.norm(v))
			tilt = body.shy
		}
	}

	for dir in a.toward(p, lead + coast) {
		v = slide(v, dir, tilt)
	}
	mut sent := []f64{}
	match a.bd.drive() {
		.holonomic {
			if lcl.norm(v) > lcl.norm(a.last) {
				v = lcl.add(a.last, lcl.clamp_norm(lcl.sub(v, a.last), a.limits.a_max * dt))
			}

			// The blend keeps what last had toward a human or a solid that came within reach
			// since, and one drop above can bring back motion toward what another took out, so
			// kept takes the blend to the nearest velocity clear of them all and the fence. That
			// slows it at most, but can leave it further than a_max * dt from last, and then the
			// body speeds up along kept's direction only as far as fastest allows.
			v = a.kept(v, p, coast)
			if !a.allows(v, p, dt, vmax, coast) {
				v = lcl.clamp_norm(v, a.fastest(math.atan2(v[1], v[0]), dt))
			}
			sent = v.clone()
		}
		.differential {
			// The base reaches the command's direction by turning, so a_max bounds the motion
			// along its heading, not the command.
			mut c := body.steer(a.fenced(v, p, coast), p.heading)
			c = body.Course{
				speed:   math.min(c.speed, a.fastest(p.heading, dt))
				heading: c.heading
			}
			v = c.motion(p.heading)
			if !a.allows(v, p, dt, vmax, coast) {
				// Turning in place moves the body's center nowhere, so it breaks no restraint.
				c = body.Course{
					heading: c.heading
				}
				v = [0.0, 0.0]
			}
			sent = [c.speed, c.heading]
		}
	}

	a.bd.actuate(sent) or {
		a.bd.halt()
		a.last = []f64{len: a.last.len}
		return a.last.clone()
	}
	a.last = v.clone()
	return v
}

// fastest is the most speed the body may move with along heading after dt. a_max bounds its
// motion on either drive: while the body speeds up, the motion changes by at most a_max * dt from
// last, and at no more speed than last it may change freely.
fn (a Armor) fastest(heading f64, dt f64) f64 {
	ahead := lcl.dot(a.last, body.Course{
		speed: 1.0
	}.motion(heading))
	reach := a.limits.a_max * dt

	// The motion at speed s along heading lies reach from last at s = ahead ± sqrt(room).
	room := ahead * ahead - lcl.dot(a.last, a.last) + reach * reach
	if room < 0.0 {
		return lcl.norm(a.last)
	}
	return math.max(lcl.norm(a.last), ahead + math.sqrt(room))
}

// allows reports whether m, the planar motion of the body at p, keeps every restraint drive puts
// on a command: no faster than vmax scaled for the nearest human, no change from last beyond
// a_max * dt while it speeds up, and what keeps checks with the keeps and the fence widened by
// margin meters.
fn (a Armor) allows(m []f64, p lcl.Percept, dt f64, vmax f64, margin f64) bool {
	speed := lcl.norm(m)
	if speed > vmax * a.separation(p) + still {
		return false
	}
	if speed > lcl.norm(a.last) + still && lcl.dist(m, a.last) > a.limits.a_max * dt + still {
		return false
	}
	return a.keeps(m, p, margin)
}

// keeps reports whether m, a planar motion of the body at p, moves toward no human inside
// human_stop, into nothing solid inside solid_keep and no further out of the fence, each widened
// by margin meters.
fn (a Armor) keeps(m []f64, p lcl.Percept, margin f64) bool {
	return a.toward(p, margin).all(lcl.dist(drop_toward(m, it), m) <= still)
		&& lcl.dist(a.fenced(m, p, margin), m) <= still
}

// kept is the motion nearest v that keeps passes at p with margin: v itself, v without its part
// toward one entity drive moves the body no closer to or out of the fence, or rest. Each such
// entity, and each wall of the fence the body stands at, rules out the motions on one side of a
// line through rest, so the nearest motion none rules out is v, lies on the line of one that v
// crosses, or is rest.
fn (a Armor) kept(v []f64, p lcl.Percept, margin f64) []f64 {
	mut near := a.toward(p, margin).map(drop_toward(v, it))
	near << v
	near << a.fenced(v, p, margin)
	mut best := []f64{len: v.len}
	for m in near {
		if a.keeps(m, p, margin) && lcl.dist(m, v) < lcl.dist(best, v) {
			best = m.clone()
		}
	}
	return best
}

// toward is the direction from p's pose to each entity drive moves the body no closer to: a human
// inside human_stop and anything else solid inside solid_keep, each widened by margin meters.
fn (a Armor) toward(p lcl.Percept, margin f64) [][]f64 {
	mut dirs := [][]f64{}
	for e in p.scene {
		if e.kind == 'beacon' {
			continue
		}
		keep := if e.kind == 'human' { a.limits.human_stop } else { a.limits.solid_keep }
		if lcl.dist(p.pose, e.pos) - e.r < keep + margin {
			dirs << lcl.sub(e.pos, p.pose)
		}
	}
	return dirs
}

// fenced is v without the parts that would carry the body at p further out of the bounds, each
// wall moved margin meters in.
fn (a Armor) fenced(v []f64, p lcl.Percept, margin f64) []f64 {
	mut out := v.clone()
	b := a.limits.bounds
	if (p.pose[0] <= b[0] + margin && v[0] < 0.0) || (p.pose[0] >= b[2] - margin && v[0] > 0.0) {
		out[0] = 0.0
	}
	if (p.pose[1] <= b[1] + margin && v[1] < 0.0) || (p.pose[1] >= b[3] - margin && v[1] > 0.0) {
		out[1] = 0.0
	}
	return out
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

// top_speed is the fastest drive lets the body move at p off ground, in m/s: v_max with a pilot or
// the dummy plug seated, else v_unmanned, slowed by separation near a human, and 0 on a percept
// the armor cannot measure. main.v's field loop hands it to the local planner, which plans at that
// speed and wades through ground, where drive slows the body further (ADR-0010).
pub fn (a Armor) top_speed(p lcl.Percept, manned bool) f64 {
	if !a.measurable(p) {
		return 0.0
	}
	vmax := if manned { a.limits.v_max } else { a.limits.v_unmanned }
	return vmax * a.separation(p)
}

// ground_factor is the least factor of the patches of ground in p whose rim lies within margin of
// its pose, the body inside one included, or 1 with none. drive multiplies the top speed by it
// with margin the body's stopping distance plus a tick of travel, so Sim's body moves at the
// patch's speed by the time its center crosses the rim, and the MuJoCo base, whose velocity lags
// its command, within about 1% of it there (PLAN, Known issue 33); leaving the patch, the body
// speeds up within a_max.
fn ground_factor(p lcl.Percept, margin f64) f64 {
	mut k := 1.0
	for g in p.ground {
		if lcl.dist(p.pose, g.pos) - g.r < margin {
			k = math.min(k, g.factor)
		}
	}
	return k
}

// separation scales speed down between human_slow and human_stop. Inside human_stop the
// machine may still creep, but drive has already removed every component toward the human.
// tools/worldgen.py SLOWEST copies its floor.
fn (a Armor) separation(p lcl.Percept) f64 {
	d := nearest_human(p)
	if d >= a.limits.human_slow {
		return 1.0
	}
	return math.max(0.2, (d - a.limits.human_stop) / (a.limits.human_slow - a.limits.human_stop))
}

// measurable reports whether p has a finite pose with one coordinate per degree of freedom and a
// finite heading, every entity a finite position of the same length and a finite radius, and every
// patch of ground those and a factor above 0 and at most 1. A NaN fails every comparison, so a
// human at a NaN position would pass the release_keep check, and a NaN heading every check of a
// differential body's motion. A position shorter than the pose would panic lcl.dist, and a longer
// one the lcl.sub(e.pos, p.pose) in drive. A factor above 1 would raise the top speed, and a lost
// one decodes as 0.
fn (a Armor) measurable(p lcl.Percept) bool {
	return p.pose.len == a.last.len && finite(p.pose) && math.is_finite(p.heading)
		&& p.scene.all(it.pos.len == p.pose.len && finite(it.pos) && math.is_finite(it.r))
		&& p.ground.all(it.pos.len == p.pose.len && finite(it.pos) && math.is_finite(it.r)
		&& it.factor > 0.0 && it.factor <= 1.0)
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

// slide is v without its part toward dir, as drop_toward leaves it, and turned tilt rad further
// from dir at the same speed when that took anything away.
fn slide(v []f64, dir []f64, tilt f64) []f64 {
	slid := drop_toward(v, dir)
	if tilt == 0.0 || lcl.dot(v, dir) <= 0.0 {
		return slid
	}
	a := if slid[0] * dir[1] - slid[1] * dir[0] > 0.0 { -tilt } else { tilt }
	return [math.cos(a) * slid[0] - math.sin(a) * slid[1], math.sin(a) * slid[0] +
		math.cos(a) * slid[1]]
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
