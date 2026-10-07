module body

import math
import os
import x.json2
import lcl

// body_radius is the simulated body's radius in meters: Sim counts contact with anything solid
// whose rim lies closer to the body's center, and load_world keeps a world's start that clear.
// tools/worldgen.py BODY_R copies it.
const body_radius = 0.25

// max_entities caps a world's beacons, obstacles and humans together, since every one reaches the
// percept a model reads at each deliberation and the recorder's line 50 times a second.
const max_entities = 16

// walk_min and walk_max bound a human's walking speed in meters per second, from a stroll to a
// brisk walk; an aside human catches up with its path at walk_max. planner/planner.v walking is
// half of walk_min.
const walk_min = 0.1
const walk_max = 2.0

// max_world_bytes caps a world file's size, so a file that is no world neither fills memory nor
// slows every sense; the example world takes about 1 KiB.
const max_world_bytes = 65536

// max_radius caps an entity's radius in meters, so no circle covers most of the floor.
const max_radius = 5.0

// keep_min and keep_max bound how far a stop or aside human keeps its rim from the body's center,
// in meters. Above body_radius an aside human never touches the body.
const keep_min = 0.3
const keep_max = 3.0

// mover_keep_min is the least keep of an obstacle that walks, in meters. It stops for the body
// and never steps within its keep of the body's center, while the MuJoCo base, braking along a
// motion the armor just took out, closes by up to its stopping distance from armor.Limits v_max
// sped up by a_max for a tick, 0.117 m from 1.03 m/s, so 0.5 m still leaves more than body_radius
// and the two never touch; a human's keep_min would leave 0.18 m. armor.Limits names it back.
const mover_keep_min = 0.5

// World is a stage Sim plays: where the body starts, the beacons to deliver to, the obstacles,
// standing and moving, and the humans. main.v's load_config takes default_world, or the file WORLD
// names through load_world, and new_sim plays it. docs/worlds.md describes the file.
pub struct World {
pub:
	start     []f64 // x, y in meters
	beacons   []Spot
	obstacles []Spot // that stand
	humans    []Human
	moving    []Human // obstacles that walk as a human walks, each with reaction stop
}

// Spot is a beacon or a standing obstacle of a World, a circle that never moves.
pub struct Spot {
pub:
	id  string
	pos []f64 // x, y in meters
	r   f64   // meters
}

// Behavior is how a Human of a World walks when nothing is in its way.
pub enum Behavior {
	loop      // an ellipse around center with radii, at rate from phase
	waypoints // along points at speed, back to the first after the last if cycle
	stand     // at pos
	toward    // from pos toward the body at speed
}

// Reaction is what a Human of a World does about the body.
pub enum Reaction {
	through // nothing: it walks through the body, as the default world's h1 does
	stop    // it stands while the body is within keep and walks on once it is clear
	aside   // it steps around the body, keeping keep from it
}

// Human is a person of a World, or an obstacle that walks, a circle that walks by its Behavior
// and meets the body by its Reaction. Its distance to the body is the armor's measure, from the
// body's center to its rim.
pub struct Human {
pub:
	id       string
	r        f64 // meters
	behavior Behavior
	reaction Reaction
	pos      []f64   // stand's place and toward's start
	center   []f64   // loop
	radii    []f64   // loop, along x and along y, in meters
	rate     f64     // loop, radians per second, counterclockwise when positive
	phase    f64     // loop, radians at the start
	points   [][]f64 // waypoints
	speed    f64     // waypoints and toward, meters per second
	cycle    bool    // waypoints
	keep     f64     // stop and aside, meters
}

// WorldFile is a world file as its JSON holds it, which load_world checks into a World.
// tools/pilot.py world reads its start and first beacon too, so a change here changes that.
struct WorldFile {
	start     []f64
	beacons   []Spot
	obstacles []HumanFile // one without a behavior stands
	humans    []HumanFile
}

// HumanFile is one human or obstacle of a WorldFile, with its behavior and reaction still text.
struct HumanFile {
	id       string
	r        f64
	behavior string
	reaction string
	pos      []f64
	center   []f64
	radii    []f64
	rate     f64
	phase    f64
	points   [][]f64
	speed    f64
	cycle    bool
	keep     f64
}

// default_world is the world Sim plays while WORLD is unset, the reference every earlier
// measurement flew: the body starts at -3.5,-2.5, beacon b1 lies past pillar o1, and human h1
// walks a 21 s ellipse past both and through the body. worlds/default.json holds the same world,
// tools/scenarios.json copies it with the human standing still, and tools/pilot.py START and
// BEACON copy its start and its beacon.
pub fn default_world() World {
	return World{
		start:     [-3.5, -2.5]
		beacons:   [Spot{
			id:  'b1'
			pos: [3.0, 2.0]
			r:   0.3
		}]
		obstacles: [Spot{
			id:  'o1'
			pos: [0.0, -0.3]
			r:   0.8
		}]
		humans:    [
			Human{
				id:       'h1'
				r:        0.3
				behavior: .loop
				reaction: .through
				center:   [0.8, 1.2]
				radii:    [1.8, 1.2]
				rate:     0.3
			},
		]
	}
}

// load_world reads the world file at path for main.v's load_config and refuses it unless Sim can
// play it inside fence, the armor's xmin, ymin, xmax, ymax. Each error is one line without the
// path, which load_config quotes, that says what is wrong and what a world accepts.
pub fn load_world(path string, fence []f64) !World {
	accepted := 'accepted a regular file of at most ${max_world_bytes} bytes'

	// A device or a pipe would fill memory or hang the start, so only a regular file is read.
	st := os.stat(path) or {
		return error('cannot be read: ${lcl.escaped(err.msg())}; ${accepted}')
	}
	if st.get_filetype() != .regular {
		return error('is not a regular file; ${accepted}')
	}
	if st.size > max_world_bytes {
		return error('holds ${st.size} bytes; ${accepted}')
	}
	text := os.read_file(path) or {
		// Only a failed open sets errno, and only its message names the path.
		why := if err.code() > 0 { os.posix_get_error_msg(err.code()) } else { err.msg() }
		return error('cannot be read: ${lcl.escaped(why)}; ${accepted}')
	}
	if !lcl.complete(text) {
		return error('not a world in JSON, since its brackets do not close or nest past ${lcl.max_depth}; accepted one JSON object')
	}
	f := json2.decode[WorldFile](text) or {
		return error('not a world in JSON; accepted an object of start, beacons, obstacles and humans')
	}
	return f.world(fence)
}

// world checks f into a World.
fn (f WorldFile) world(fence []f64) !World {
	n := f.beacons.len + f.obstacles.len + f.humans.len
	if n > max_entities {
		return error('${n} entities; accepted at most ${max_entities} beacons, obstacles and humans in all')
	}
	if f.beacons.len == 0 {
		return error('no beacon; accepted at least one beacon to deliver to')
	}
	place('start', f.start, fence)!
	mut ids := []string{}
	for b in f.beacons {
		spot('beacon', b, fence, mut ids)!
	}
	mut obstacles := []Spot{}
	mut moving := []Human{}
	for o in f.obstacles {
		if o.behavior == '' {
			s := Spot{
				id:  o.id
				pos: o.pos
				r:   o.r
			}
			spot('obstacle', s, fence, mut ids)!
			obstacles << s
		} else {
			moving << o.human('obstacle', fence, mut ids)!
		}
	}
	mut humans := []Human{}
	for h in f.humans {
		humans << h.human('human', fence, mut ids)!
	}
	for o in obstacles {
		if touches(f.start, o.pos, o.r) {
			return error('start touches obstacle ${o.id}; accepted a start more than ${body_radius} m from every solid rim')
		}
	}
	for h in humans {
		if touches(f.start, h.path(0), h.r) {
			return error('start touches human ${h.id} where it starts; accepted a start more than ${body_radius} m from every solid rim')
		}
	}
	for o in moving {
		if touches(f.start, o.path(0), o.r) {
			return error('start touches obstacle ${o.id} where it starts; accepted a start more than ${body_radius} m from every solid rim')
		}
	}
	return World{
		start:     f.start
		beacons:   f.beacons
		obstacles: obstacles
		humans:    humans
		moving:    moving
	}
}

// spot checks a beacon or an obstacle and adds its id to ids.
fn spot(kind string, s Spot, fence []f64, mut ids []string) ! {
	identify(kind, s.id, mut ids)!
	place('${kind} ${s.id}', s.pos, fence)!
	radius('${kind} ${s.id}', s.r)!
}

// human checks one human, or one obstacle that walks, of a world file, kind naming which in its
// errors, and adds its id to ids. An obstacle that walks reacts stop only, with a keep from
// mover_keep_min: through would ram a body the armor cannot move away, and aside lets the body
// push it past the fence.
fn (f HumanFile) human(kind string, fence []f64, mut ids []string) !Human {
	identify(kind, f.id, mut ids)!
	what := '${kind} ${f.id}'
	radius(what, f.r)!
	if ![f.rate, f.phase, f.speed, f.keep].all(math.is_finite(it)) {
		return error('${what} has a number that is not finite; accepted finite numbers')
	}
	behavior := Behavior.from_string(f.behavior) or {
		return error('${what} has behavior ${lcl.quoted(f.behavior)}, not a known value; accepted loop, waypoints, stand, toward')
	}
	reaction := Reaction.from_string(f.reaction) or {
		return error('${what} has reaction ${lcl.quoted(f.reaction)}, not a known value; accepted through, stop, aside')
	}
	match behavior {
		.loop {
			place('${what} center', f.center, fence)!
			if f.radii.len != 2 || !f.radii.all(it >= 0.0 && math.is_finite(it)) {
				return error('${what} radii are not one x and one y, each finite and 0 or more; accepted [x, y] in meters')
			}
			place('${what} loop', lcl.sub(f.center, f.radii), fence)!
			place('${what} loop', lcl.add(f.center, f.radii), fence)!
			walks(what, math.abs(f.rate) * math.max(f.radii[0], f.radii[1]))!
		}
		.waypoints {
			if f.points.len < 2 {
				return error('${what} has fewer than 2 waypoints; accepted 2 or more')
			}
			for i, p in f.points {
				place('${what} waypoint ${i + 1}', p, fence)!
			}
			if length(f.points, f.cycle) == 0.0 {
				return error('${what} has waypoints all in one place; accepted waypoints apart')
			}
			walks(what, f.speed)!
		}
		.stand {
			place('${what} pos', f.pos, fence)!
		}
		.toward {
			place('${what} pos', f.pos, fence)!
			walks(what, f.speed)!
			if reaction == .through {
				return error('${what} walks toward the body and through it, which would hold the body in contact; accepted reaction stop or aside')
			}
		}
	}

	if kind == 'obstacle' && (reaction != .stop || f.keep < mover_keep_min || f.keep > keep_max) {
		return error('${what} reacts ${reaction} with keep ${f.keep} m; accepted reaction stop with keep ${mover_keep_min} to ${keep_max}')
	}
	match reaction {
		.through {}
		.stop, .aside {
			if !(f.keep >= keep_min && f.keep <= keep_max) {
				return error('${what} keeps ${f.keep} m from the body; accepted ${keep_min} to ${keep_max}')
			}
		}
	}

	return Human{
		id:       f.id
		r:        f.r
		behavior: behavior
		reaction: reaction
		pos:      f.pos
		center:   f.center
		radii:    f.radii
		rate:     f.rate
		phase:    f.phase
		points:   f.points
		speed:    f.speed
		cycle:    f.cycle
		keep:     f.keep
	}
}

// identify refuses an id that is not 1 to 16 lowercase letters, digits and hyphens, since ids reach
// status lines and every prompt, or one that ids already holds, and adds it to ids.
fn identify(kind string, id string, mut ids []string) ! {
	if id == '' || id.len > 16 || !id.contains_only('abcdefghijklmnopqrstuvwxyz0123456789-') {
		return error('${kind} has id ${lcl.quoted(id)}; accepted 1 to 16 lowercase letters, digits and hyphens')
	}
	if id in ids {
		return error('${kind} has id ${id}, which another entity has; accepted an id per entity')
	}
	ids << id
}

// place refuses a position that is not two finite numbers inside fence.
fn place(what string, p []f64, fence []f64) ! {
	if p.len != 2 {
		return error('${what} is not one x and one y; accepted [x, y] in meters')
	}
	if !p.all(math.is_finite(it)) {
		return error('${what} has a number that is not finite; accepted finite numbers')
	}
	if p[0] < fence[0] || p[0] > fence[2] || p[1] < fence[1] || p[1] > fence[3] {
		return error('${what} lies outside the fence; accepted x from ${fence[0]} to ${fence[2]} and y from ${fence[1]} to ${fence[3]}')
	}
}

// radius refuses a radius that is not above 0 and at most max_radius.
fn radius(what string, r f64) ! {
	if !(r > 0.0 && r <= max_radius) {
		return error('${what} has radius ${r}; accepted a radius above 0 and at most ${max_radius} m')
	}
}

// walks refuses a walking speed outside walk_min to walk_max.
fn walks(what string, speed f64) ! {
	if !(speed >= walk_min && speed <= walk_max) {
		return error('${what} walks at ${speed:.2f} m/s; accepted ${walk_min} to ${walk_max}')
	}
}

// touches reports whether the body at at touches a solid circle at pos of radius r, by Sim's rule
// of contact.
fn touches(at []f64, pos []f64, r f64) bool {
	return lcl.dist(at, pos) < r + body_radius
}

// path is where human h is clock_ms into its walk, for loop and waypoints; the other behaviors
// start at pos.
fn (h Human) path(clock_ms i64) []f64 {
	match h.behavior {
		.loop {
			// The cosine and sine come before any index, which keeps the default world's loop bit
			// for bit what it was in a release build. With an index between them, a -prod build
			// put the sine one ulp off at about one sense in 180, as if clang no longer merged
			// the two calls into one sincos. A dev build gives both orders alike, so just test
			// runs body_test.v test_scene in a release build too.
			a := f64(clock_ms) / 1000.0 * h.rate + h.phase
			cos, sin := math.cos(a), math.sin(a)
			return [h.center[0] + h.radii[0] * cos, h.center[1] + h.radii[1] * sin]
		}
		.waypoints {
			return along(h.points, h.cycle, math.max(0.0, f64(clock_ms) / 1000.0 * h.speed))
		}
		.stand, .toward {
			return h.pos.clone()
		}
	}
}

// along is the point d meters along the line through points, closed back to the first point if
// cycle, and the line's end once a walk that does not cycle has come to it.
fn along(points [][]f64, cycle bool, d f64) []f64 {
	line := route(points, cycle)
	mut left := if cycle { math.fmod(d, length(points, cycle)) } else { d }
	for i in 1 .. line.len {
		gap := lcl.dist(line[i - 1], line[i])
		if left < gap {
			return lcl.add(line[i - 1], lcl.scale(lcl.sub(line[i], line[i - 1]), left / gap))
		}
		left -= gap
	}
	return line.last().clone()
}

// length is how far a walk along points goes, back to the first point if cycle.
fn length(points [][]f64, cycle bool) f64 {
	line := route(points, cycle)
	mut sum := 0.0
	for i in 1 .. line.len {
		sum += lcl.dist(line[i - 1], line[i])
	}
	return sum
}

// route is the line a waypoints walk follows: points, then the first point again if cycle.
fn route(points [][]f64, cycle bool) [][]f64 {
	mut line := points.clone()
	if cycle {
		line << points[0]
	}
	return line
}

// Walker is where one human or moving obstacle of Sim's world is, how fast it last walked and how
// long it has stood waiting for the body.
struct Walker {
mut:
	at        []f64
	vel       []f64 // m/s, the step of its last walk over that time; empty when that step was zero
	waited_ms i64
}

// step moves the walker of human h to elapsed_ms after the world began, dt_ms after its last
// step, with the body at pose, and sets its velocity to that step over dt_ms. A step of no time
// keeps the velocity it had. A stop human's walk resumes where it stood, since its clock runs
// without the time it waited.
fn (mut w Walker) step(h Human, elapsed_ms i64, dt_ms i64, pose []f64) {
	prev := w.at.clone()
	dt := f64(dt_ms) / 1000.0
	next := match h.behavior {
		.loop, .waypoints { h.path(elapsed_ms - w.waited_ms) }
		.stand { h.pos.clone() }
		.toward { lcl.add(w.at, lcl.clamp_norm(lcl.sub(pose, w.at), h.speed * dt)) }
	}

	match h.reaction {
		.through {
			w.at = next
		}
		.stop {
			// Testing the step's end as well keeps a late sense from carrying the human inside
			// keep, and with it into a contact Sim would hold for good while the human waits.
			if lcl.dist(pose, w.at) - h.r < h.keep || lcl.dist(pose, next) - h.r < h.keep {
				w.waited_ms += dt_ms
			} else {
				w.at = next
			}
		}
		.aside {
			gap := h.r + h.keep
			mut v := lcl.clamp_norm(lcl.sub(next, w.at), walk_max * dt)
			out := lcl.sub(w.at, pose)

			// Within a step of the rim and heading into it, the human walks along the rim when
			// its way leads past the body, and waits on the rim when its way ends inside it.
			if lcl.dist(next, pose) >= gap && lcl.norm(out) > 0.0
				&& lcl.norm(out) < gap + walk_max * dt && lcl.dot(v, out) < 0.0 {
				v = around(v, out)
			}
			w.at = clear_of(lcl.add(w.at, v), pose, gap)
		}
	}

	if dt_ms > 0 {
		moved := lcl.sub(w.at, prev)
		w.vel = if lcl.norm(moved) > 0.0 { lcl.scale(moved, 1000.0 / f64(dt_ms)) } else { []f64{} }
	}
}

// around is the step v turned along the rim of a circle whose outward normal at the walker is
// out, at v's speed: to the side v leans to, or counterclockwise when v heads straight in, so a
// walk that leads through the circle's center still gets around.
fn around(v []f64, out []f64) []f64 {
	n := lcl.scale(out, 1.0 / lcl.norm(out))
	t := lcl.sub(v, lcl.scale(n, lcl.dot(v, n)))
	dir := if lcl.norm(t) > 1e-9 { t } else { [-n[1], n[0]] }
	return lcl.scale(dir, lcl.norm(v) / lcl.norm(dir))
}

// clear_of is at moved straight away from pose until it lies at least gap from it.
// ponytail: it knows neither the fence nor the obstacles, which no human's walk avoids either, so
// the body can push an aside human past the fence or into a pillar; keep the fence in World and
// step around the solids once a world needs its humans kept out of both.
fn clear_of(at []f64, pose []f64, gap f64) []f64 {
	d := lcl.dist(at, pose)
	if d >= gap {
		return at
	}
	if d == 0.0 {
		return [pose[0] + gap, pose[1]]
	}
	return lcl.add(pose, lcl.scale(lcl.sub(at, pose), gap / d))
}
