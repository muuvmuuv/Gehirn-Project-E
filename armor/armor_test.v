module armor

import math
import time
import body
import lcl

// Fake is a body that records what the armor sends it, so a test sees what moved.
struct Fake {
	fail  bool // actuate errs instead of recording
	base  body.Drive
	coast f64 // s: stopping reports the speed times this
mut:
	sent    [][]f64
	effects []string
	halts   int
}

fn (f &Fake) dof() int {
	return 2
}

fn (f &Fake) drive() body.Drive {
	return f.base
}

fn (f &Fake) stopping(speed f64) f64 {
	return f.coast * speed
}

fn (mut f Fake) sense() lcl.Percept {
	return lcl.Percept{}
}

fn (mut f Fake) actuate(u []f64) ! {
	if f.fail {
		return error('fake: actuate failed')
	}
	f.sent << u.clone()
}

fn (mut f Fake) effect(verb string) ! {
	f.effects << verb
}

fn (mut f Fake) halt() {
	f.halts++
}

fn ent(kind string, pos []f64, r f64) lcl.Entity {
	return lcl.Entity{
		id:   kind
		kind: kind
		pos:  pos
		r:    r
	}
}

// boat is an obstacle that walks, with radius 1 m, at pos with velocity vel, which the armor keeps
// off where it is now.
fn boat(pos []f64, vel []f64) lcl.Entity {
	return lcl.Entity{
		...ent('obstacle', pos, 1.0)
		vel: vel
	}
}

// patch is a patch of ground with radius r m at pos that leaves the body factor of its top speed.
fn patch(pos []f64, r f64, factor f64) lcl.Entity {
	return lcl.Entity{
		...ent('ground', pos, r)
		factor: factor
	}
}

// at is a percept with the body at pose and the given scene.
fn at(pose []f64, scene ...lcl.Entity) lcl.Percept {
	return lcl.Percept{
		pose:  pose
		scene: scene
	}
}

fn same(a []f64, b []f64) bool {
	return a.len == b.len && lcl.dist(a, b) < 1e-9
}

struct DriveCase {
	name   string
	pose   []f64 = [0.0, 0.0]
	scene  []lcl.Entity
	last   []f64 = [0.0, 0.0]
	u      []f64
	manned bool = true
	dt     f64  = 1.0
	want   []f64
}

fn test_drive() {
	// Humans and obstacles sit east of the body or on it, so a command north passes them by.
	// Gaps are center distance minus radius: a human at 1.85 m with r 0.5 is 1.35 m away,
	// halfway between human_stop and human_slow. The Fake is holonomic, so the armor sends the
	// restrained command itself, without the lead and the shy turn of a differential body.
	cases := [
		DriveCase{
			name: 'manned speed cap'
			u:    [3.0, 4.0]
			want: [0.6, 0.8]
		},
		DriveCase{
			name:   'unmanned speed cap'
			u:      [3.0, 4.0]
			manned: false
			want:   [0.24, 0.32]
		},
		DriveCase{
			name:   'below the cap unchanged'
			u:      [0.3, 0.0]
			manned: false
			want:   [0.3, 0.0]
		},
		DriveCase{
			name: 'acceleration from rest is limited'
			u:    [0.6, 0.8]
			dt:   0.1
			want: [0.09, 0.12]
		},
		DriveCase{
			name: 'acceleration from cruise is limited'
			last: [0.6, 0.0]
			u:    [1.0, 0.0]
			dt:   0.1
			want: [0.75, 0.0]
		},
		DriveCase{
			name: 'braking to a stop is never limited'
			last: [0.6, 0.8]
			u:    [0.0, 0.0]
			dt:   0.1
			want: [0.0, 0.0]
		},
		DriveCase{
			name: 'braking partway is never limited'
			last: [1.0, 0.0]
			u:    [0.2, 0.0]
			dt:   0.1
			want: [0.2, 0.0]
		},
		DriveCase{
			name: 'a reversal at the same speed is never limited'
			last: [1.0, 0.0]
			u:    [-1.0, 0.0]
			dt:   0.1
			want: [-1.0, 0.0]
		},
		DriveCase{
			name:   'an emptied seat drops to the unmanned cap at once'
			last:   [1.0, 0.0]
			u:      [1.0, 0.0]
			manned: false
			dt:     0.1
			want:   [0.4, 0.0]
		},
		DriveCase{
			name: 'west fence'
			pose: [-5.0, 0.0]
			u:    [-0.6, 0.8]
			want: [0.0, 0.8]
		},
		DriveCase{
			name: 'east fence'
			pose: [5.0, 0.0]
			u:    [0.6, 0.8]
			want: [0.0, 0.8]
		},
		DriveCase{
			name: 'south fence'
			pose: [0.0, -5.0]
			u:    [0.6, -0.8]
			want: [0.6, 0.0]
		},
		DriveCase{
			name: 'north fence'
			pose: [0.0, 5.0]
			u:    [0.6, 0.8]
			want: [0.6, 0.0]
		},
		DriveCase{
			name: 'back inside from the fence'
			pose: [5.0, 0.0]
			u:    [-0.6, 0.8]
			want: [-0.6, 0.8]
		},
		DriveCase{
			name: 'beyond the corner'
			pose: [5.5, 5.5]
			u:    [0.6, 0.8]
			want: [0.0, 0.0]
		},
		DriveCase{
			name:  'full speed at human_slow'
			scene: [ent('human', [2.5, 0.0], 0.5)]
			u:     [0.0, 1.0]
			want:  [0.0, 1.0]
		},
		DriveCase{
			name:  'half speed halfway to human_stop'
			scene: [ent('human', [1.85, 0.0], 0.5)]
			u:     [0.0, 1.0]
			want:  [0.0, 0.5]
		},
		DriveCase{
			name:   'unmanned scales its own cap'
			scene:  [ent('human', [1.85, 0.0], 0.5)]
			u:      [0.0, 1.0]
			manned: false
			want:   [0.0, 0.2]
		},
		DriveCase{
			name:  'a fifth of the speed near human_stop'
			scene: [ent('human', [1.3, 0.0], 0.5)]
			u:     [0.0, 1.0]
			want:  [0.0, 0.2]
		},
		DriveCase{
			name:  'toward a human at human_stop creeps'
			scene: [ent('human', [1.2, 0.0], 0.5)]
			u:     [1.0, 0.0]
			want:  [0.2, 0.0]
		},
		DriveCase{
			name:  'nothing toward a human inside human_stop'
			scene: [ent('human', [1.0, 0.0], 0.5)]
			u:     [1.0, 0.0]
			want:  [0.0, 0.0]
		},
		DriveCase{
			name:  'past a human inside human_stop'
			scene: [ent('human', [1.0, 0.0], 0.5)]
			u:     [0.6, 0.8]
			want:  [0.0, 0.16]
		},
		DriveCase{
			name:  'away from a human inside human_stop'
			scene: [ent('human', [1.0, 0.0], 0.5)]
			u:     [-0.6, 0.8]
			want:  [-0.12, 0.16]
		},
		DriveCase{
			name:  'slides along an obstacle'
			scene: [ent('obstacle', [2.0, 0.0], 1.8)]
			u:     [0.6, 0.8]
			want:  [0.0, 0.8]
		},
		DriveCase{
			name:  'leaves an obstacle freely'
			scene: [ent('obstacle', [1.0, 0.0], 0.8)]
			u:     [-0.6, 0.8]
			want:  [-0.6, 0.8]
		},
		DriveCase{
			name:  'an obstacle at solid_keep does not deflect'
			scene: [ent('obstacle', [0.85, 0.0], 0.5)]
			u:     [0.6, 0.8]
			want:  [0.6, 0.8]
		},
		DriveCase{
			name:  'an obstacle within the lead of a differential body does not deflect'
			scene: [ent('obstacle', [2.17, 0.0], 1.8)]
			u:     [0.6, 0.8]
			want:  [0.6, 0.8]
		},
		DriveCase{
			name:  'an obstacle centered on the body has no direction to drop'
			scene: [ent('obstacle', [0.0, 0.0], 0.5)]
			u:     [0.6, 0.8]
			want:  [0.6, 0.8]
		},
		DriveCase{
			name:  'a beacon is not solid'
			scene: [ent('beacon', [0.5, 0.0], 0.3)]
			u:     [0.6, 0.8]
			want:  [0.6, 0.8]
		},
	]
	for c in cases {
		mut f := &Fake{}
		mut a := restrain(f, Limits{})
		a.last = c.last.clone()
		got := a.drive(c.u, at(c.pose, ...c.scene), c.dt, c.manned)
		assert same(got, c.want), '${c.name}: got ${got}'
		assert f.sent.len == 1 && same(f.sent[0], got)
		assert same(a.last, got)
	}
}

// A holonomic body moves toward no human inside human_stop and into no solid inside solid_keep,
// and speeds up by no more than a_max * dt, where restraining the command one step after another
// would break one: the blend from a last velocity toward a human who just stepped within reach,
// two drops in turn, the fence after a drop, and the fence after the blend. The first two are the
// probes of PLAN Known issue 32. In the second and third every motion within 90 degrees of the
// command closes on the human or the pillar or leaves the fence, so the body stands.
fn test_drive_moves_a_holonomic_body_toward_nothing_within_reach() {
	ne := 0.9 / math.sqrt(2.0)
	cases := [
		DriveCase{
			name:  'no blend toward a human just inside human_stop'
			scene: [ent('human', [0.95, 0.0], 0.3)]
			last:  [0.1, 0.0]
			u:     [0.0, 0.2]
			dt:    0.02
			want:  [0.0, 0.06 / math.sqrt(5.0)]
		},
		DriveCase{
			name:  'no drop toward a human brings back motion into a pillar'
			scene: [ent('obstacle', [1.0, 0.0], 0.8), ent('human', [-ne, ne], 0.3)]
			u:     [0.6, 0.8]
			want:  [0.0, 0.0]
		},
		DriveCase{
			name:  'no fence brings back motion toward a human'
			pose:  [-5.0, 0.0]
			scene: [ent('human', [-5.0 + ne, ne], 0.3)]
			u:     [-1.0, 0.5]
			want:  [0.0, 0.0]
		},
		DriveCase{
			name: 'speeds up along the fence by a_max where the fence leaves the blend past it'
			pose: [-5.0, 0.0]
			last: [-0.01, 0.5]
			u:    [0.0, 1.0]
			dt:   0.02
			want: [0.0, 0.5 + math.sqrt(0.0008)]
		},
	]
	for c in cases {
		mut f := &Fake{}
		mut a := restrain(f, Limits{})
		a.last = c.last.clone()
		got := a.drive(c.u, at(c.pose, ...c.scene), c.dt, c.manned)
		assert same(got, c.want), '${c.name}: got ${got}'
		assert f.sent.len == 1 && same(f.sent[0], got)
	}
}

// deg is a in degrees, in rad.
fn deg(a f64) f64 {
	return a * math.pi / 180.0
}

// along is speed m/s along heading, in rad.
fn along(speed f64, heading f64) []f64 {
	return body.Course{
		speed: speed
	}.motion(heading)
}

struct SteerCase {
	name    string
	pose    []f64 = [0.0, 0.0]
	heading f64
	scene   []lcl.Entity
	last    []f64 = [0.0, 0.0]
	u       []f64
	manned  bool = true
	dt      f64  = 1.0
	want    []f64 // the motion drive returns
	sent    []f64 // the Course it actuates, speed and heading
}

fn test_drive_on_a_differential_body() {
	// Each refused case has a twin with the heading on the other side of the slid command, which
	// drives: only the motion along the heading decides. The human north of the body sits 0.5 m
	// from it, inside human_stop, so its speed cap is a fifth of v_max. Steered along the slid
	// command at the heading of each first twin, a base would close on the human, push into the
	// obstacle or cross the fence. A command slid along the human or the obstacle turns body.shy
	// away from it, and one slid along the fence does not.
	north := ent('human', [0.0, 1.0], 0.5)
	east := ent('obstacle', [2.0, 0.0], 1.8)
	slid := 0.2 / math.sqrt(1.0 + 1.5 * 1.5) // the x part of [0.2, 0.3] capped at 0.2 m/s
	cases := [
		SteerCase{
			name: 'drives along its heading'
			u:    [0.6, 0.0]
			want: [0.6, 0.0]
			sent: [0.6, 0.0]
		},
		SteerCase{
			name:    'drives the projection within align while it turns'
			heading: 0.3
			u:       [0.6, 0.0]
			want:    along(0.6 * math.cos(0.3), 0.3)
			sent:    [0.6 * math.cos(0.3), 0.0]
		},
		SteerCase{
			name: 'turns in place beyond align'
			u:    [0.0, 0.6]
			want: [0.0, 0.0]
			sent: [0.0, math.pi / 2.0]
		},
		SteerCase{
			name:    'stands on a zero command and keeps its heading'
			heading: 1.0
			u:       [0.0, 0.0]
			want:    [0.0, 0.0]
			sent:    [0.0, 1.0]
		},
		SteerCase{
			name:    'manned speed cap'
			heading: math.atan2(4.0, 3.0)
			u:       [3.0, 4.0]
			want:    [0.6, 0.8]
			sent:    [1.0, math.atan2(4.0, 3.0)]
		},
		SteerCase{
			name:    'unmanned speed cap'
			heading: math.atan2(4.0, 3.0)
			u:       [3.0, 4.0]
			manned:  false
			want:    [0.24, 0.32]
			sent:    [0.4, math.atan2(4.0, 3.0)]
		},
		SteerCase{
			name: 'acceleration from rest is limited'
			u:    [1.0, 0.0]
			dt:   0.1
			want: [0.15, 0.0]
			sent: [0.15, 0.0]
		},
		SteerCase{
			name: 'speeds up along its heading by a_max'
			last: [0.8, 0.0]
			u:    [1.0, 0.0]
			dt:   0.02
			want: [0.83, 0.0]
			sent: [0.83, 0.0]
		},
		SteerCase{
			name:    'keeps its speed while it turns faster than a_max lets it speed up'
			heading: deg(5)
			last:    [0.8, 0.0]
			u:       along(1.0, deg(20))
			dt:      0.02
			want:    along(0.8, deg(5))
			sent:    [0.8, deg(20)]
		},
		SteerCase{
			name:    'turns in place where its heading would close on a human inside human_stop'
			heading: deg(25)
			scene:   [north]
			u:       [0.2, 0.3]
			want:    [0.0, 0.0]
			sent:    [0.0, -body.shy]
		},
		SteerCase{
			name:    'drives where its heading leads away from a human inside human_stop'
			heading: deg(-25)
			scene:   [north]
			u:       [0.2, 0.3]
			want:    along(slid * math.cos(deg(25) - body.shy), deg(-25))
			sent:    [slid * math.cos(deg(25) - body.shy), -body.shy]
		},
		SteerCase{
			name:    'turns in place where its heading would push into an obstacle'
			heading: deg(70)
			scene:   [east]
			u:       [0.6, 0.8]
			want:    [0.0, 0.0]
			sent:    [0.0, math.pi / 2.0 + body.shy]
		},
		SteerCase{
			name:    'drives where its heading leaves an obstacle'
			heading: deg(110)
			scene:   [east]
			u:       [0.6, 0.8]
			want:    along(0.8 * math.cos(deg(20) - body.shy), deg(110))
			sent:    [0.8 * math.cos(deg(20) - body.shy), math.pi / 2.0 + body.shy]
		},
		SteerCase{
			name:    'drives along the slide while it turns shy of the obstacle'
			heading: math.pi / 2.0
			scene:   [east]
			u:       [0.6, 0.8]
			want:    [0.0, 0.8 * math.cos(body.shy)]
			sent:    [0.8 * math.cos(body.shy), math.pi / 2.0 + body.shy]
		},
		SteerCase{
			name:    'slides along an obstacle within its lead before solid_keep'
			heading: math.pi / 2.0
			scene:   [ent('obstacle', [2.17, 0.0], 1.8)]
			u:       [0.6, 0.8]
			want:    [0.0, 0.8 * math.cos(body.shy)]
			sent:    [0.8 * math.cos(body.shy), math.pi / 2.0 + body.shy]
		},
		SteerCase{
			name:    'past its lead an obstacle does not deflect'
			heading: math.atan2(0.8, 0.6)
			scene:   [ent('obstacle', [2.25, 0.0], 1.8)]
			u:       [0.6, 0.8]
			want:    [0.6, 0.8]
			sent:    [1.0, math.atan2(0.8, 0.6)]
		},
		SteerCase{
			name:    'turns in place where its heading would cross the east fence'
			pose:    [5.0, 0.0]
			heading: deg(70)
			u:       [0.6, 0.8]
			want:    [0.0, 0.0]
			sent:    [0.0, math.pi / 2.0]
		},
		SteerCase{
			name:    'drives back inside from the east fence'
			pose:    [5.0, 0.0]
			heading: deg(110)
			u:       [0.6, 0.8]
			want:    along(0.8 * math.cos(deg(20)), deg(110))
			sent:    [0.8 * math.cos(deg(20)), math.pi / 2.0]
		},
		SteerCase{
			name:    'beyond the corner it stands'
			pose:    [5.5, 5.5]
			heading: 0.5
			u:       [0.6, 0.8]
			want:    [0.0, 0.0]
			sent:    [0.0, 0.5]
		},
		SteerCase{
			name:  'a human outside human_stop slows it but lets it head toward them'
			scene: [ent('human', [1.85, 0.0], 0.5)]
			u:     [1.0, 0.0]
			want:  [0.5, 0.0]
			sent:  [0.5, 0.0]
		},
		SteerCase{
			name:  'a beacon is not solid'
			scene: [ent('beacon', [0.5, 0.0], 0.3)]
			u:     [0.6, 0.0]
			want:  [0.6, 0.0]
			sent:  [0.6, 0.0]
		},
	]
	for c in cases {
		mut f := &Fake{
			base: .differential
		}
		mut a := restrain(f, Limits{})
		a.last = c.last.clone()
		p := lcl.Percept{
			pose:    c.pose
			heading: c.heading
			scene:   c.scene
		}
		got := a.drive(c.u, p, c.dt, c.manned)
		assert same(got, c.want), '${c.name}: got ${got}'
		assert f.sent.len == 1 && same(f.sent[0], c.sent), '${c.name}: sent ${f.sent}'
		assert same(a.last, got), c.name
	}
}

// A differential body slid along a walking human keeps moving. Each tick it heads where the
// last one aimed it, body.shy away from the human, so the degree the human walks round it in a
// tick leaves its motion clear of them; headed exactly along the last slide, it would close on
// the human and be refused tick after tick.
fn test_a_differential_body_keeps_moving_past_a_walking_human() {
	mut f := &Fake{
		base: .differential
	}
	mut a := restrain(f, Limits{})
	mut heading := -body.shy
	for bearing in [90.0, 89.0, 88.0] {
		human := ent('human', [math.cos(deg(bearing)), math.sin(deg(bearing))], 0.5)
		p := lcl.Percept{
			pose:    [0.0, 0.0]
			heading: heading
			scene:   [human]
		}
		got := a.drive([0.2, 0.3], p, 1.0, true)
		assert lcl.norm(got) > 0.0, '${bearing}: stood'
		assert lcl.dot(got, human.pos) < 0.0, '${bearing}: ${got}'

		// Headed along the slide of a tick before, with the human a degree further round, it
		// would close on them.
		assert !a.allows(along(lcl.norm(got), deg(bearing + 1.0 - 90.0)), p, 1.0, 1.0, 0.0), '${bearing}'
		heading = f.sent.last()[1]
	}
}

struct TowardCase {
	name string
	kind string
	vel  []f64
	gap  f64 // m from the body's center to the entity's rim
	want bool
}

// toward gives the direction to every entity but a beacon whose rim lies within its keep, widened
// by the margin: a human within human_stop, and anything else within solid_keep, an obstacle that
// moves, a ditch and a kind no code names alike, so a new kind counts as solid and fails closed.
fn test_toward() {
	margin := 0.1
	cases := [
		TowardCase{'a beacon under the body', 'beacon', [], -0.5, false},
		TowardCase{'a human inside human_stop and the margin', 'human', [], 0.79, true},
		TowardCase{'a human past them', 'human', [], 0.81, false},
		TowardCase{'an obstacle inside solid_keep and the margin', 'obstacle', [], 0.44, true},
		TowardCase{'an obstacle past them', 'obstacle', [], 0.46, false},
		TowardCase{'an obstacle that moves, inside', 'obstacle', [-0.5, 0.0], 0.44, true},
		TowardCase{'an obstacle that moves away, inside', 'obstacle', [0.5, 0.0], 0.44, true},
		TowardCase{'an obstacle that moves, past', 'obstacle', [-0.5, 0.0], 0.46, false},
		TowardCase{'a ditch inside', 'ditch', [], 0.44, true},
		TowardCase{'a ditch past', 'ditch', [], 0.46, false},
		TowardCase{'a landing zone inside', 'impact', [], 0.44, true},
		TowardCase{'a landing zone past', 'impact', [], 0.46, false},
		TowardCase{'a kind no code names, inside', 'lava', [], 0.44, true},
		TowardCase{'a kind no code names, past', 'lava', [], 0.46, false},
	]
	a := restrain(&Fake{}, Limits{})
	for c in cases {
		e := lcl.Entity{
			...ent(c.kind, [c.gap + 0.5, 0.0], 0.5)
			vel: c.vel
		}
		got := a.toward(at([0.0, 0.0], e), margin)
		assert (got.len == 1) == c.want, c.name
		if c.want {
			assert same(got[0], e.pos), '${c.name}: ${got}'
		}
	}
}

struct GroundCase {
	name   string
	ground []lcl.Entity
	scene  []lcl.Entity
	manned bool = true
	want   f64 // the speed drive leaves a command east at 3 m/s from rest over 1 s
}

// On ground drive lowers the top speed by the least factor of the patches within reach, the body
// inside one included, times separation near a human, seated or not; past the reach, its stopping
// distance plus a tick of travel, 1.5 m from rest over a tick of 1 s, a patch slows nothing.
fn test_ground_factor() {
	o := [0.0, 0.0]
	north := [ent('human', [0.0, 1.85], 0.5)] // 1.35 m off, halfway between human_stop and human_slow
	cases := [
		GroundCase{'inside a patch', [patch(o, 1.0, 0.5)], [], true, 0.5},
		GroundCase{'inside a patch, unmanned', [patch(o, 1.0, 0.5)], [], false, 0.2},
		GroundCase{'inside a patch with a human halfway in', [
			patch(o, 1.0, 0.5)], north, true, 0.25},
		GroundCase{'inside two patches', [patch(o, 1.0, 0.5),
			patch([0.5, 0.0], 1.0, 0.3)], [], true, 0.3},
		GroundCase{'inside one and within reach of another', [
			patch(o, 1.0, 0.5), patch([0.0, -3.0], 1.6, 0.2)], [], true, 0.2},
		GroundCase{'a rim just within reach', [patch([0.0, -3.0], 1.51, 0.5)], [], true, 0.5},
		GroundCase{'a rim just past reach', [patch([0.0, -3.0], 1.49, 0.5)], [], true, 1.0},
	]
	for c in cases {
		mut f := &Fake{}
		mut a := restrain(f, Limits{})
		got := a.drive([3.0, 0.0], lcl.Percept{ pose: o, scene: c.scene, ground: c.ground }, 1.0,
			c.manned)
		assert math.abs(lcl.norm(got) - c.want) < 1e-9, '${c.name}: got ${got}'
		assert same(got, [c.want, 0.0]), '${c.name}: got ${got}'
	}
}

// A body driven east at 1 m/s through a patch of 0.5 has slowed to half the top speed when its
// center crosses the rim, since the cap starts within its stopping distance plus a tick of travel
// of the rim and not before, stays on until it is that far out again, and on the way out speeds up
// by no more than a_max a tick, on either drive, whether it stops at once or coasts 0.02 or 0.1 s
// at its speed.
fn test_drive_slows_the_body_through_a_patch_of_ground() {
	lake := patch([2.0, 0.0], 1.0, 0.5) // from x 1 to x 3
	limits := Limits{}
	dt := 0.02
	for base in [body.Drive.holonomic, .differential] {
		for coast in [0.0, 0.02, 0.1] {
			name := '${base}, coasting ${coast} s'
			mut f := &Fake{
				base:  base
				coast: coast
			}
			mut a := restrain(f, limits)
			mut pose := [-1.0, 0.0]
			mut last := [0.0, 0.0]
			mut slow := 0
			for pose[0] < 4.0 {
				v := a.drive([1.0, 0.0], lcl.Percept{
					pose:   pose
					vel:    last
					ground: [
						lake,
					]
				}, dt, true)
				reach := lcl.norm(last) + limits.a_max * dt
				gap := lcl.dist(pose, lake.pos) - lake.r
				if gap < f.stopping(reach) + reach * dt {
					assert lcl.norm(v) <= 0.5 + 1e-9, '${name}: ${lcl.norm(v)} m/s at ${pose}'
					slow++
				} else {
					assert same(v, [math.min(1.0, reach), 0.0]), '${name}: ${v} at ${pose}'
				}
				pose = lcl.add(pose, lcl.scale(v, dt))
				last = v.clone()
			}
			assert slow > 2.0 / 0.5 / dt, '${name}: ${slow} ticks slowed'
		}
	}
}

struct CoastCase {
	name    string
	base    body.Drive
	coast   f64   = 0.1
	pose    []f64 = [0.0, 0.0]
	heading f64
	scene   []lcl.Entity
	last    []f64 = [1.0, 0.0]
	vel     []f64 = [0.0, 0.0]
	u       []f64 = [1.0, 0.0]
	want    []f64 // the motion drive returns
	sent    []f64 // what it actuates, want when empty
}

// A body that moves on along a motion once a command takes it out gets every keep and the fence
// widened by the stopping distance it reports at the speed it may reach, the faster of last and
// its velocity sped up by a_max for a tick, here 0.1 s at 1.03 m/s, 0.103 m, so on either drive no
// motion takes it toward a solid, a human or out of the fence within that margin. Each case has a
// twin that stops at once, or reports no velocity, and drives as before, and past the margin a
// coasting body drives as before too. In the last two the command slides along a human 0.75 m
// north, and at 20 degrees north of east the heading lets the body drive, so only the check of
// that motion against the widened keep turns it in place.
fn test_drive_widens_the_keeps_and_the_fence_by_the_stopping_distance() {
	ne := [0.6, 0.8]
	solid := [ent('obstacle', [1.4, 0.0], 1.0)] // 0.4 m off, 0.05 m outside solid_keep
	human := [ent('human', [1.25, 0.0], 0.5)] // 0.75 m off, 0.05 m outside human_stop
	north := [ent('human', [0.0, 1.25], 0.5)]
	far := [ent('obstacle', [1.55, 0.0], 1.0)] // 0.55 m off, past the margin
	slid := 0.2 / math.sqrt(1.0 + 1.5 * 1.5)
	cases := [
		CoastCase{
			name:  'a holonomic body slides along a solid within the margin'
			scene: solid
			last:  ne
			u:     ne
			want:  [0.0, 0.8]
		},
		CoastCase{
			name:  'a holonomic body that stops at once drives on past that solid'
			coast: 0.0
			scene: solid
			last:  ne
			u:     ne
			want:  ne
		},
		CoastCase{
			name:  'a holonomic body slides along a solid within what a_max adds to its speed'
			scene: [ent('obstacle', [1.4515, 0.0], 1.0)] // 0.1015 m outside solid_keep
			last:  ne
			u:     ne
			want:  [0.0, 0.8]
		},
		CoastCase{
			name:  'a holonomic body at rest slides along a solid within the margin of its velocity'
			scene: solid
			last:  [0.0, 0.0]
			vel:   [1.0, 0.0]
			u:     ne
			want:  [0.0, 0.03]
		},
		CoastCase{
			name:  'a holonomic body at rest that reports no velocity speeds up toward that solid'
			scene: solid
			last:  [0.0, 0.0]
			u:     ne
			want:  [0.018, 0.024]
		},
		CoastCase{
			name:  'a holonomic body moves nothing toward a human within the margin'
			scene: human
			last:  ne
			u:     ne
			want:  [0.0, 0.16]
		},
		CoastCase{
			name:  'a holonomic body that stops at once moves on toward that human, slowed'
			coast: 0.0
			scene: human
			last:  ne
			u:     ne
			want:  [0.12, 0.16]
		},
		CoastCase{
			name: 'a holonomic body moves nothing out toward a wall within the margin'
			pose: [4.95, 0.0]
			last: ne
			u:    ne
			want: [0.0, 0.8]
		},
		CoastCase{
			name:  'a holonomic body that stops at once moves on toward that wall'
			coast: 0.0
			pose:  [4.95, 0.0]
			last:  ne
			u:     ne
			want:  ne
		},
		CoastCase{
			name:  'a holonomic body slides along a moving obstacle within the margin, where it is'
			scene: [boat([1.4, 0.0], [-0.5, 0.0])]
			last:  ne
			u:     ne
			want:  [0.0, 0.8]
		},
		CoastCase{
			name:  'a holonomic body slides as much along a moving obstacle walking away'
			scene: [boat([1.4, 0.0], [0.5, 0.0])]
			last:  ne
			u:     ne
			want:  [0.0, 0.8]
		},
		CoastCase{
			name:  'a holonomic body moves nothing toward a moving obstacle head on within the margin'
			scene: [boat([1.4, 0.0], [-0.5, 0.0])]
			last:  [1.0, 0.0]
			u:     [1.0, 0.0]
			want:  [0.0, 0.0]
		},
		CoastCase{
			name:  'a holonomic body slides along a ditch within the margin'
			scene: [ent('ditch', [1.4, 0.0], 1.0)]
			last:  ne
			u:     ne
			want:  [0.0, 0.8]
		},
		CoastCase{
			name:  'a holonomic body moves nothing into a ditch head on within the margin'
			scene: [ent('ditch', [1.4, 0.0], 1.0)]
			last:  [1.0, 0.0]
			u:     [1.0, 0.0]
			want:  [0.0, 0.0]
		},
		CoastCase{
			name:  'a holonomic body slides along a landing zone within the margin'
			scene: [ent('impact', [1.4, 0.0], 1.0)]
			last:  ne
			u:     ne
			want:  [0.0, 0.8]
		},
		CoastCase{
			name:  'a holonomic body moves nothing into a landing zone head on within the margin'
			scene: [ent('impact', [1.4, 0.0], 1.0)]
			last:  [1.0, 0.0]
			u:     [1.0, 0.0]
			want:  [0.0, 0.0]
		},
		CoastCase{
			name:  'past the margin a solid does not deflect a holonomic body'
			scene: far
			last:  ne
			u:     ne
			want:  ne
		},
		CoastCase{
			name:  'a differential body turns in place before a solid within the margin and its lead'
			base:  .differential
			scene: [ent('obstacle', [1.45, 0.0], 1.0)]
			want:  [0.0, 0.0]
			sent:  [0.0, 0.0]
		},
		CoastCase{
			name:  'a differential body that stops at once drives on'
			base:  .differential
			coast: 0.0
			scene: [ent('obstacle', [1.45, 0.0], 1.0)]
			want:  [1.0, 0.0]
		},
		CoastCase{
			name:  'a differential body turns in place before a ditch within the margin'
			base:  .differential
			scene: [ent('ditch', [1.45, 0.0], 1.0)]
			want:  [0.0, 0.0]
			sent:  [0.0, 0.0]
		},
		CoastCase{
			name:  'a differential body turns in place before a landing zone within the margin'
			base:  .differential
			scene: [ent('impact', [1.45, 0.0], 1.0)]
			want:  [0.0, 0.0]
			sent:  [0.0, 0.0]
		},
		CoastCase{
			name:  'a differential body turns in place before a moving obstacle within the margin'
			base:  .differential
			scene: [boat([1.45, 0.0], [-0.5, 0.0])]
			want:  [0.0, 0.0]
			sent:  [0.0, 0.0]
		},
		CoastCase{
			name:  'a differential body turns in place before a human within the margin'
			base:  .differential
			scene: human
			want:  [0.0, 0.0]
			sent:  [0.0, 0.0]
		},
		CoastCase{
			name:  'a differential body that stops at once drives on, slowed'
			base:  .differential
			coast: 0.0
			scene: human
			want:  [0.2, 0.0]
		},
		CoastCase{
			name: 'a differential body turns in place before a wall within the margin'
			base: .differential
			pose: [4.95, 0.0]
			want: [0.0, 0.0]
			sent: [0.0, 0.0]
		},
		CoastCase{
			name:  'a differential body that stops at once drives on'
			base:  .differential
			coast: 0.0
			pose:  [4.95, 0.0]
			want:  [1.0, 0.0]
		},
		CoastCase{
			name:  'past the margin and its lead a solid does not deflect a differential body'
			base:  .differential
			scene: [ent('obstacle', [1.6, 0.0], 1.0)]
			want:  [1.0, 0.0]
		},
		CoastCase{
			name:    'a differential body turns in place where its heading closes on a human within the margin'
			base:    .differential
			heading: deg(20)
			scene:   north
			u:       [0.2, 0.3]
			want:    [0.0, 0.0]
			sent:    [0.0, -body.shy]
		},
		CoastCase{
			name:    'a differential body drives where its heading leads away from that human'
			base:    .differential
			heading: deg(-20)
			scene:   north
			u:       [0.2, 0.3]
			want:    along(slid * math.cos(deg(20) - body.shy), deg(-20))
			sent:    [slid * math.cos(deg(20) - body.shy), -body.shy]
		},
	]
	for c in cases {
		mut f := &Fake{
			base:  c.base
			coast: c.coast
		}
		mut a := restrain(f, Limits{})
		a.last = c.last.clone()
		p := lcl.Percept{
			pose:    c.pose
			vel:     c.vel
			heading: c.heading
			scene:   c.scene
		}
		got := a.drive(c.u, p, 0.02, true)
		assert same(got, c.want), '${c.name}: got ${got}'
		sent := if c.sent.len > 0 { c.sent } else { c.want }
		assert f.sent.len == 1 && same(f.sent[0], sent), '${c.name}: sent ${f.sent}'
	}
}

struct TickCase {
	name  string
	world body.World // the body starts at its start
	last  []f64      // m/s, the motion the body moves with as the case begins
	u     []f64
}

// Sim moves along a command until the next sense, which its stopping reports, so a body moving at
// a keep or the fence stands before it whatever the tick, here ticks of at least 20, 34, 47 and
// 60 ms in real time. Each case starts beyond 20 ms of travel from its keep and within 34 ms of
// it, at the top speed the armor allows there, where a Sim that moved for the whole of a 34 ms
// tick ended it 9 mm past the north fence, 9 mm inside the pillar's solid_keep and 1.8 mm inside
// the standing human's human_stop.
fn test_a_sim_body_stands_before_its_keeps_and_the_fence_on_any_tick() {
	cases := [
		TickCase{'the north fence 2.5 cm ahead', body.World{
			start: [0.0, 4.975]
		}, [0.0, 1.0], [0.0, 1.0]},
		TickCase{'a pillar 2.5 cm outside solid_keep', body.World{
			start:     [0.0, 0.0]
			obstacles: [body.Spot{'o1', [0.875, 0.0], 0.5}]
		}, [1.0, 0.0], [1.0, 0.0]},
		TickCase{'a standing human 5 mm outside human_stop', body.World{
			start:  [0.0, 0.0]
			humans: [body.Human{
				id:       'h1'
				r:        0.3
				behavior: .stand
				pos:      [1.005, 0.0]
			}]
		}, [0.2, 0.0], [1.0, 0.0]},
	]
	limits := Limits{}
	for ms in [20, 34, 47, 60] {
		for c in cases {
			mut a := restrain(body.new_sim(c.world, .holonomic), limits)
			a.last = c.last.clone()
			mut p := lcl.Percept{
				...a.sense()
				vel: c.last
			}
			for n in 0 .. 5 {
				a.drive(c.u, p, 0.02, true)
				time.sleep(ms * time.millisecond)
				p = a.sense()
				at := '${c.name}, ${ms} ms, tick ${n}: ${p.pose}'
				assert math.abs(p.pose[0]) <= 5.0 && math.abs(p.pose[1]) <= 5.0, at
				for e in p.scene {
					keep := if e.kind == 'human' { limits.human_stop } else { limits.solid_keep }
					assert lcl.dist(p.pose, e.pos) - e.r >= keep, at
				}
			}
		}
	}
}

struct TopCase {
	name   string
	p      lcl.Percept
	manned bool
	want   f64
}

// top_speed is the cap drive clamps a command to, which main.v hands the local planner: v_max
// seated, v_unmanned otherwise, slowed by separation from human_slow down to a fifth at
// human_stop, and nothing on a percept the armor cannot measure.
fn test_top_speed() {
	o := [0.0, 0.0]
	cases := [
		TopCase{'seated, nobody around', at(o), true, 1.0},
		TopCase{'unmanned, nobody around', at(o), false, 0.4},
		TopCase{'a human rim at human_slow', at(o, ent('human', [2.3, 0.0], 0.3)), true, 1.0},
		TopCase{'a human rim halfway in', at(o, ent('human', [1.65, 0.0], 0.3)), true, 0.5},
		TopCase{'a human rim at human_stop', at(o, ent('human', [1.0, 0.0], 0.3)), true, 0.2},
		TopCase{'a human rim at human_stop, unmanned', at(o, ent('human', [1.0, 0.0], 0.3)), false, 0.08},
		TopCase{'an obstacle is no human', at(o, ent('obstacle', [0.5, 0.0], 0.3)), true, 1.0},
		TopCase{'a percept it cannot measure', at([math.nan(), 0.0]), true, 0.0},
	]
	for c in cases {
		mut f := &Fake{}
		a := restrain(f, Limits{})
		got := a.top_speed(c.p, c.manned)
		assert math.abs(got - c.want) < 1e-9, '${c.name}: ${got}'
	}
}

struct AllowsCase {
	name   string
	pose   []f64
	scene  []lcl.Entity
	last   []f64
	m      []f64
	manned bool
	dt     f64
	want   bool
}

// allows refuses a differential body's motion that breaks any restraint drive puts on a command,
// and lets through what keeps them all, rounding toward a solid included.
fn test_allows() {
	o := [0.0, 0.0]
	east := [5.0, 0.0]
	human := [ent('human', [1.0, 0.0], 0.5)]
	halfway := [ent('human', [1.85, 0.0], 0.5)]
	obstacle := [ent('obstacle', [2.0, 0.0], 1.8)]
	empty := []lcl.Entity{}
	cases := [
		AllowsCase{'at the manned cap', o, empty, o, [0.0, 1.0], true, 1.0, true},
		AllowsCase{'past the manned cap', o, empty, o, [0.0, 1.01], true, 1.0, false},
		AllowsCase{'at the unmanned cap', o, empty, o, [0.0, 0.4], false, 1.0, true},
		AllowsCase{'past the unmanned cap', o, empty, o, [0.0, 0.41], false, 1.0, false},
		AllowsCase{'past the cap halfway to human_stop', o, halfway, o, [0.0, 0.6], true, 1.0, false},
		AllowsCase{'speeding up by a_max', o, empty, [0.5, 0.0], [0.65, 0.0], true, 0.1, true},
		AllowsCase{'speeding up past a_max', o, empty, [0.5, 0.0], [0.66, 0.0], true, 0.1, false},
		AllowsCase{'braking', o, empty, [1.0, 0.0], [0.1, 0.0], true, 0.1, true},
		AllowsCase{'turning at the same speed', o, empty, [1.0, 0.0], [0.0, 1.0], true, 0.1, true},
		AllowsCase{'speeding up while turning within a_max', o, empty, [0.5, 0.0], [0.55, 0.1], true, 0.1, true},
		AllowsCase{'speeding up while turning past a_max', o, empty, [0.5, 0.0], [0.5, 0.2], true, 0.1, false},
		AllowsCase{'toward a human inside human_stop', o, human, o, [0.05, 0.1], true, 1.0, false},
		AllowsCase{'a rounding toward a human inside human_stop', o, human, o, [1e-12, 0.1], true, 1.0, true},
		AllowsCase{'away from a human inside human_stop', o, human, o, [-0.05, 0.1], true, 1.0, true},
		AllowsCase{'into an obstacle inside solid_keep', o, obstacle, o, [0.1, 0.5], true, 1.0, false},
		AllowsCase{'along an obstacle inside solid_keep', o, obstacle, o, [0.0, 0.5], true, 1.0, true},
		AllowsCase{'out of the east fence', east, empty, o, [0.1, 0.5], true, 1.0, false},
		AllowsCase{'along the east fence', east, empty, o, [0.0, 0.5], true, 1.0, true},
		AllowsCase{'back inside from the east fence', east, empty, o, [-0.1, 0.5], true, 1.0, true},
	]
	for c in cases {
		mut f := &Fake{
			base: .differential
		}
		mut a := restrain(f, Limits{})
		a.last = c.last.clone()
		vmax := if c.manned { a.limits.v_max } else { a.limits.v_unmanned }
		assert a.allows(c.m, at(c.pose, ...c.scene), c.dt, vmax, 0.0) == c.want, c.name
	}
}

struct SimCase {
	name   string
	pose   []f64 = sim_start // where the percept puts the body
	scene  []lcl.Entity
	u      []f64
	manned bool  = true
	dt     f64   = 0.02
	want   []f64 = [0.0, 0.0] // the motion drive returns
	turns  bool // the body turns clockwise in place
}

// sim_start is where test_a_differential_sim_moves_as_the_armor_checked puts each body, clear of
// Sim's pillar and human.
const sim_start = [-4.0, -4.0]

// off is r m from sim_start toward bearing degrees.
fn off(bearing f64, r f64) []f64 {
	return lcl.add(sim_start, along(r, deg(bearing)))
}

// A differential Sim moves with the very motion drive checked. Where the motion along its heading,
// east at the start, would break a restraint, the body stays where it stood and at most turns;
// where it keeps them all, the body moves along the velocity drive returned and reports it as its
// own. The first three commands slide along what lies 80 or 100 degrees off them and end up 15
// degrees off the heading, within align, so the armor's check of the motion decides.
fn test_a_differential_sim_moves_as_the_armor_checked() {
	cases := [
		SimCase{
			name:  'turns in place where it would close on a human inside human_stop'
			scene: [ent('human', off(80, 0.8), 0.3)]
			u:     lcl.add(along(0.2, deg(-10)), along(0.1, deg(80)))
			turns: true
		},
		SimCase{
			name:  'turns in place where it would push into a solid inside solid_keep'
			scene: [ent('obstacle', off(80, 0.8), 0.5)]
			u:     lcl.add(along(0.2, deg(-10)), along(0.1, deg(80)))
			turns: true
		},
		SimCase{
			name:  'drives where its heading leads away from a human inside human_stop'
			scene: [ent('human', off(100, 0.8), 0.3)]
			u:     lcl.add(along(0.2, deg(10)), along(0.1, deg(100)))
			want:  [0.03, 0.0]
		},
		SimCase{
			name: 'stands at the east fence'
			pose: [5.0, 0.0]
			u:    [0.6, 0.0]
		},
		SimCase{
			name:   'moves at the unmanned cap'
			u:      [1.0, 0.0]
			manned: false
			dt:     1.0
			want:   [0.4, 0.0]
		},
		SimCase{
			name: 'speeds up from rest by a_max'
			u:    [1.0, 0.0]
			want: [0.03, 0.0]
		},
	]
	for c in cases {
		mut s := body.new_sim(body.World{
			...body.default_world()
			start: sim_start
		}, .differential)
		mut a := restrain(s, Limits{})
		start := a.sense()
		p := lcl.Percept{
			...start
			pose:  c.pose
			scene: c.scene
		}
		got := a.drive(c.u, p, c.dt, c.manned)
		assert same(got, c.want), '${c.name}: got ${got}'

		// Long enough for the Sim to integrate, far inside its 200 ms lapse.
		time.sleep(5 * time.millisecond)
		q := a.sense()
		assert q.vel == got, c.name
		step := lcl.sub(q.pose, start.pose)
		if lcl.norm(got) > 0.0 {
			assert lcl.norm(step) > 0.0, c.name
			assert math.abs(step[0] * got[1] - step[1] * got[0]) < 1e-12, c.name
		} else {
			assert q.pose == start.pose, c.name
		}
		assert (q.heading < 0.0) == c.turns, '${c.name}: heading ${q.heading}'
	}
}

struct MujocoCase {
	name   string
	start  []f64 = sim_start
	scene  []lcl.Entity // what each percept shows the armor in place of the body's own world
	u      []f64
	toward []f64 // the direction of the part of u drive removes
	moves  bool  // the base drives off within the run, rather than only turns
}

// The MuJoCo base of ADR-0008, starting from rest, moves nowhere along the part of a command
// drive removed, toward a human inside human_stop, a solid inside solid_keep or out of the fence,
// over 30 ticks of the field loop in real time: it turns away first and drives where its heading
// leads clear. Each start lies far from the default world's pillar and human. A base already
// moving brakes along its motion instead, which drive leaves room for, as
// test_a_moving_mujoco_body_stands_before_its_keeps shows.
fn test_a_mujoco_body_moves_nowhere_toward_what_drive_removed() {
	$if mujoco ? {
		u := lcl.add(along(0.2, deg(-10)), along(0.1, deg(80)))
		cases := [
			MujocoCase{
				name:   'a human inside human_stop'
				scene:  [ent('human', off(80, 0.8), 0.3)]
				u:      u
				toward: along(1.0, deg(80))
				moves:  true
			},
			MujocoCase{
				name:   'a solid inside solid_keep'
				scene:  [ent('obstacle', off(80, 0.8), 0.5)]
				u:      u
				toward: along(1.0, deg(80))
				moves:  true
			},
			MujocoCase{
				name:   'the east fence'
				start:  [5.0, 0.0]
				u:      [0.4, 0.4]
				toward: [1.0, 0.0]
			},
		]
		for c in cases {
			b := body.new_mujoco(body.World{
				...body.default_world()
				start: c.start
			})!
			mut a := restrain(b, Limits{})
			mut p := a.sense()
			for _ in 0 .. 30 {
				a.drive(c.u, lcl.Percept{ ...p, scene: c.scene }, 0.02, true)
				time.sleep(20 * time.millisecond)
				p = a.sense()
				assert lcl.dot(lcl.sub(p.pose, c.start), c.toward) <= 1e-9, '${c.name}: ${p.pose}'
			}
			assert (lcl.dist(p.pose, c.start) > 0.02) == c.moves, '${c.name}: ${p.pose}'
			assert math.abs(p.heading) > deg(5), '${c.name}: heading ${p.heading}'
		}
	}
}

struct MovingCase {
	name      string
	start     []f64
	obstacles []body.Spot
	falling   []body.Falling // whose landing zone, no geom on MuJoCo, the armor alone keeps the base off
	human     []f64          // where a human of radius 0.3 stands in every percept, nowhere when empty
	steps_in  bool           // a human of radius 0.3 steps in with its rim 0.65 m ahead once the base runs at v_max
	ticks     int            // slows the base to 1 cm/s even where every tick lasts exactly tick_ms (PLAN, Known issue 36)
	tick_ms   int = 20 // between a drive and the next sense
}

// depth is how far the base at p stands inside the keep of the case: past the east fence, inside
// solid_keep of its pillar or its landing zone, or inside human_stop of its standing human.
fn (c MovingCase) depth(p lcl.Percept, l Limits) f64 {
	if c.obstacles.len > 0 {
		return l.solid_keep - (lcl.dist(p.pose, c.obstacles[0].pos) - c.obstacles[0].r)
	}
	if c.falling.len > 0 {
		return l.solid_keep - (lcl.dist(p.pose, c.falling[0].pos) - c.falling[0].r)
	}
	if c.human.len > 0 {
		return l.human_stop - (lcl.dist(p.pose, c.human) - 0.3)
	}
	return p.pose[0] - l.bounds[2]
}

// A MuJoCo base driving east at v_max brakes to a stand outside the keep it drives at, since drive
// widens the keeps and the fence by its stopping distance (PLAN, Known issue 33): at the fence,
// also on ticks of 60 ms, longer than the 50 ms one sense runs the base's last command, from two
// starts half such a tick of travel apart, head on at a pillar, whose keep drive widens by
// body.lead too, head on at a falling object's landing zone, which is no geom the base could
// stop at, also on ticks of 60 ms, and before a standing human, whom it slows for. A human who steps in already
// inside human_stop leaves it no room to brake, and the base moves on toward them by no more than
// its stopping distance from the speed it had.
fn test_a_moving_mujoco_body_stands_before_its_keeps() {
	$if mujoco ? {
		cases := [
			MovingCase{
				name:  'the east fence'
				start: [3.8, -4.0]
				ticks: 150
			},
			MovingCase{
				name:    'the east fence on long ticks'
				start:   [3.8, -4.0]
				ticks:   60
				tick_ms: 60
			},
			MovingCase{
				name:    'the east fence on long ticks half a tick on'
				start:   [3.825, -4.0]
				ticks:   60
				tick_ms: 60
			},
			MovingCase{
				name:      'a pillar head on'
				start:     [-2.2, -4.0]
				obstacles: [body.Spot{
					id:  'o1'
					pos: [0.0, -4.0]
					r:   0.8
				}]
				ticks:     140
			},
			MovingCase{
				name:    'a landing zone head on'
				start:   [-2.2, -4.0]
				falling: [body.Falling{'rock', [0.0, -4.0], 0.8, 600.0}]
				ticks:   140
			},
			MovingCase{
				name:    'a landing zone head on, on long ticks'
				start:   [-2.2, -4.0]
				falling: [body.Falling{'rock', [0.0, -4.0], 0.8, 600.0}]
				ticks:   60
				tick_ms: 60
			},
			MovingCase{
				name:  'a standing human'
				start: [-3.0, -4.0]
				human: [-1.0, -4.0]
				ticks: 250
			},
			MovingCase{
				name:     'a human stepping in'
				start:    [-4.0, -4.0]
				steps_in: true
				ticks:    100
			},
		]
		for c in cases {
			b := body.new_mujoco(body.World{
				start:     c.start
				beacons:   body.default_world().beacons
				obstacles: c.obstacles
				falling:   c.falling
			})!
			mut a := restrain(b, Limits{})
			mut p := a.sense()
			mut scene := p.scene.clone()
			if c.human.len > 0 {
				scene << ent('human', c.human, 0.3)
			}
			mut stopped := []f64{}
			mut speed := 0.0
			mut most := 0.0
			mut deepest := -1.0

			// Once the base stands, drive lets it creep on as its stopping distance shrinks, and
			// head on at the pillar a rounding error can start it sliding around, so the run asks
			// that the base slowed to 1 cm/s after it ran, not that it stands at the end.
			mut ran := false
			mut stood := false
			for _ in 0 .. c.ticks {
				if c.steps_in && scene.len == p.scene.len && lcl.norm(p.vel) > 0.999 {
					scene << ent('human', lcl.add(p.pose, [0.95, 0.0]), 0.3)
				}
				v := a.drive([1.0, 0.0], lcl.Percept{ ...p, scene: scene }, 0.02, true)
				if stopped.len == 0 && v[0] <= 1e-9 && lcl.norm(p.vel) > 0.5 {
					stopped = p.pose.clone()
					speed = lcl.norm(p.vel)
				}
				time.sleep(c.tick_ms * time.millisecond)
				p = a.sense()
				if stopped.len > 0 {
					most = math.max(most, p.pose[0] - stopped[0])
				}
				deepest = math.max(deepest, c.depth(p, a.limits))
				ran = ran || lcl.norm(p.vel) > 0.5
				stood = stood || (ran && lcl.norm(p.vel) < 0.01)
			}
			assert stood, '${c.name}: ${p.vel}'
			if c.steps_in {
				assert speed > 0.95, '${c.name}: stopped from ${speed} m/s'
				assert most <= b.stopping(speed), '${c.name}: ${most} m on'
			} else {
				assert deepest <= 1e-9, '${c.name}: ${deepest} m inside'
			}
		}
	}
}

struct PermitCase {
	name  string
	verb  string
	scene []lcl.Entity
	want  bool
}

fn test_permits() {
	far := ent('human', [2.5, 0.0], 0.5)
	near := ent('human', [2.25, 0.0], 0.5)
	touching := ent('human', [0.5, 0.0], 0.5)
	pillar := ent('obstacle', [0.5, 0.0], 0.8)
	cases := [
		PermitCase{'goto in the open', 'goto', [], true},
		PermitCase{'hold in the open', 'hold', [], true},
		PermitCase{'release in the open', 'release', [], true},
		PermitCase{'release with a human at release_keep', 'release', [far], true},
		PermitCase{'release with a human inside release_keep', 'release', [near], false},
		PermitCase{'release judged by the nearest human', 'release', [far, near], false},
		PermitCase{'release beside an obstacle', 'release', [pillar], true},
		PermitCase{'goto beside a human', 'goto', [touching], true},
		PermitCase{'hold beside a human', 'hold', [touching], true},
		PermitCase{'unknown verb', 'selfdestruct', [], false},
		PermitCase{'empty verb', '', [], false},
	]
	for c in cases {
		mut f := &Fake{}
		a := restrain(f, Limits{})
		assert a.permits(c.verb, at([0.0, 0.0], ...c.scene)) == c.want, c.name
	}
}

struct RefusalCase {
	name    string
	verb    string
	p       lcl.Percept
	ejected bool
	want    string
}

fn test_refusal() {
	o := [0.0, 0.0]
	near := at(o, ent('human', [2.25, 0.0], 0.5))
	blind := at([math.nan(), 0.0])
	cases := [
		RefusalCase{'release in the open', 'release', at(o), false, ''},
		RefusalCase{'release with a human inside release_keep', 'release', near, false, 'a human was within 2.0 m at that moment'},
		RefusalCase{'unknown verb', 'selfdestruct', at(o), false, 'a verb the armor does not know'},
		RefusalCase{'unmeasurable percept', 'goto', blind, false, 'a percept the armor could not measure'},
		RefusalCase{'after an eject', 'hold', at(o), true, 'the pilot had ejected'},
	]
	for c in cases {
		mut f := &Fake{}
		mut a := restrain(f, Limits{})
		if c.ejected {
			a.eject()
		}
		assert a.refusal(c.verb, c.p) == c.want, c.name
	}
}

struct ClosenessCase {
	name string
	p    lcl.Percept
	want f64
}

fn test_closeness() {
	// Gaps are center distance minus radius, from the body at the origin.
	at_slow := ent('human', [2.5, 0.0], 0.5)
	halfway := ent('human', [1.85, 0.0], 0.5)
	cases := [
		ClosenessCase{'nobody around', at([0.0, 0.0]), 0.0},
		ClosenessCase{'an obstacle is no human', at([0.0, 0.0], ent('obstacle', [0.5, 0.0], 0.4)), 0.0},
		ClosenessCase{'a human beyond human_slow', at([0.0, 0.0], ent('human', [4.0, 0.0], 0.5)), 0.0},
		ClosenessCase{'a human at human_slow', at([0.0, 0.0], at_slow), 0.0},
		ClosenessCase{'a human halfway in', at([0.0, 0.0], halfway), 0.5},
		ClosenessCase{'a human at human_stop', at([0.0, 0.0], ent('human', [1.2, 0.0], 0.5)), 1.0},
		ClosenessCase{'a human touching', at([0.0, 0.0], ent('human', [0.5, 0.0], 0.5)), 1.0},
		ClosenessCase{'the nearest human counts', at([0.0, 0.0], at_slow, halfway), 0.5},
		ClosenessCase{'a human at a NaN position', at([0.0, 0.0], ent('human', [
			math.nan(), 0.0], 0.5)), 1.0},
		ClosenessCase{'a pose of the wrong length', at([0.0]), 1.0},
	]
	for c in cases {
		mut f := &Fake{}
		a := restrain(f, Limits{})
		got := a.closeness(c.p)
		assert math.abs(got - c.want) < 1e-9, '${c.name}: ${got}'
	}
}

fn test_effect() {
	near := ent('human', [2.25, 0.0], 0.5)
	cases := [
		PermitCase{'release in the open', 'release', [], true},
		PermitCase{'goto in the open', 'goto', [], true},
		PermitCase{'hold in the open', 'hold', [], true},
		PermitCase{'release with a human inside release_keep', 'release', [near], false},
		PermitCase{'unknown verb', 'selfdestruct', [], false},
	]
	for c in cases {
		mut f := &Fake{}
		mut a := restrain(f, Limits{})
		mut got := ''
		a.effect(c.verb, at([0.0, 0.0], ...c.scene)) or { got = err.msg() }
		want := if c.want { '' } else { 'armor: ${c.verb} not permitted here' }
		assert got == want, c.name
		assert f.effects == if c.want {
			[c.verb]
		} else {
			[]string{}
		}
	}
}

fn test_eject_latches() {
	mut f := &Fake{}
	mut a := restrain(f, Limits{})
	p := at([0.0, 0.0])
	_ = a.drive([0.5, 0.0], p, 1.0, true)
	a.eject()
	assert a.is_ejected()
	assert f.halts == 1
	for verb in ['goto', 'hold', 'release'] {
		assert !a.permits(verb, p), verb
		mut got := ''
		a.effect(verb, p) or { got = err.msg() }
		assert got == 'armor: ${verb} not permitted here'
	}
	assert f.effects.len == 0
	assert a.drive([0.5, 0.0], p, 1.0, true) == [0.0, 0.0]
	assert f.sent.len == 1
	assert f.halts == 2
	assert a.is_ejected()
}

fn test_unmeasurable_percept_permits_nothing_and_halts() {
	nan := math.nan()
	inf := math.inf(1)
	o := [0.0, 0.0]
	far := ent('human', [4.0, 0.0], 0.3)
	cases := {
		'pose x NaN':                            at([nan, 0.0])
		'pose y infinite':                       at([0.0, inf])
		'pose empty':                            at([]f64{})
		'pose too short':                        at([0.0])
		'pose too long':                         at([0.0, 0.0, 0.0])
		'heading NaN':                           lcl.Percept{
			pose:    o
			heading: nan
		}
		'heading infinite':                      lcl.Percept{
			pose:    o
			heading: inf
		}
		'human at a NaN position':               at(o, ent('human', [nan, 1.2], 0.3))
		'human at an infinite position':         at(o, ent('human', [3.0, inf], 0.3))
		'human with a NaN radius':               at(o, ent('human', [3.0, 0.0], nan))
		'human with a negative infinite radius': at(o, ent('human', [0.5, 0.0], -inf))
		'human with a short position':           at(o, ent('human', [3.0], 0.3))
		'human with a long position':            at(o, ent('human', [3.0, 0.0, 0.0], 0.3))
		'human with no position':                at(o, ent('human', []f64{}, 0.3))
		'NaN human behind a far one':            at(o, far, ent('human', [nan, 0.0], 0.3))
		'obstacle at a NaN position':            at(o, ent('obstacle', [nan, 0.0], 0.8))
		'beacon at an infinite position':        at(o, ent('beacon', [inf, 2.0], 0.3))
		'ground that slows to nothing':          lcl.Percept{
			pose:   o
			ground: [patch(o, 1.0, 0.0)]
		}
		'ground with a negative factor':         lcl.Percept{
			pose:   o
			ground: [patch(o, 1.0, -0.3)]
		}
		'ground that speeds the body up':        lcl.Percept{
			pose:   o
			ground: [patch(o, 1.0, 1.5)]
		}
		'ground with a NaN factor':              lcl.Percept{
			pose:   o
			ground: [patch(o, 1.0, nan)]
		}
		'ground with an infinite factor':        lcl.Percept{
			pose:   o
			ground: [patch(o, 1.0, inf)]
		}
		'ground at a NaN position':              lcl.Percept{
			pose:   o
			ground: [patch([nan, 0.0], 1.0, 0.5)]
		}
		'ground with a long position':           lcl.Percept{
			pose:   o
			ground: [patch([3.0, 0.0, 0.0], 1.0, 0.5)]
		}
		'ground with an infinite radius':        lcl.Percept{
			pose:   o
			ground: [patch([3.0, 0.0], inf, 0.5)]
		}
	}
	for name, p in cases {
		mut f := &Fake{}
		mut a := restrain(f, Limits{})
		a.last = [0.5, 0.0]
		for verb in ['goto', 'hold', 'release'] {
			assert !a.permits(verb, p), '${name}: ${verb} permitted'
		}
		mut got := ''
		a.effect('release', p) or { got = err.msg() }
		assert got == 'armor: release not permitted here', name
		assert f.effects.len == 0, name
		assert a.drive([0.5, 0.0], p, 1.0, true) == [0.0, 0.0], name
		assert f.sent.len == 0, name
		assert f.halts == 1, name
		assert a.last == [0.0, 0.0], name
	}
}

// A stopping distance that is NaN, negative or infinite, and a velocity that leaves a coasting
// body's margin so, halt the body on either drive as a percept the armor cannot measure does,
// since no keep can be widened by it. Each case gives the Fake's coast and the velocity.
fn test_an_unmeasurable_stopping_distance_halts() {
	nan := math.nan()
	inf := math.inf(1)
	cases := {
		'a NaN stopping distance':                    [nan, 0.0]
		'a negative stopping distance':               [-0.01, 0.0]
		'an infinite stopping distance':              [inf, 0.0]
		'a NaN velocity of a body that coasts':       [0.1, nan]
		'an infinite velocity of a body that coasts': [0.1, inf]
	}
	for name, c in cases {
		for base in [body.Drive.holonomic, .differential] {
			mut f := &Fake{
				base:  base
				coast: c[0]
			}
			mut a := restrain(f, Limits{})
			a.last = [0.5, 0.0]
			p := lcl.Percept{
				pose: [0.0, 0.0]
				vel:  [c[1], 0.0]
			}
			assert a.drive([0.5, 0.0], p, 0.02, true) == [0.0, 0.0], '${name}, ${base}'
			assert f.sent.len == 0, '${name}, ${base}'
			assert f.halts == 1, '${name}, ${base}'
			assert a.last == [0.0, 0.0], '${name}, ${base}'
		}
	}
}

fn test_command_of_the_wrong_length_halts() {
	// Each command is slower than last, so no acceleration limit runs that would panic on it:
	// only the length check keeps it from the body.
	cases := {
		'command too short': [0.5]
		'command too long':  [0.5, 0.0, 0.0]
		'command empty':     []f64{}
	}
	for name, u in cases {
		mut f := &Fake{}
		mut a := restrain(f, Limits{})
		a.last = [1.0, 0.0]
		assert a.drive(u, at([0.0, 0.0]), 1.0, true) == [0.0, 0.0], name
		assert f.sent.len == 0, name
		assert f.halts == 1, name
		assert a.last == [0.0, 0.0], name
	}
}

fn test_non_finite_command_halts() {
	cases := {
		'NaN along x':       [math.nan(), 0.0]
		'+inf along y':      [0.0, math.inf(1)]
		'-inf along x':      [math.inf(-1), 0.0]
		'NaN on both axes':  [math.nan(), math.nan()]
		'one finite of two': [0.5, math.nan()]
	}
	for name, u in cases {
		mut f := &Fake{}
		mut a := restrain(f, Limits{})
		a.last = [0.5, 0.0]
		assert a.drive(u, at([0.0, 0.0]), 1.0, true) == [0.0, 0.0], name
		assert f.sent.len == 0, name
		assert f.halts == 1, name
		assert a.last == [0.0, 0.0], name
	}
}

fn test_failed_actuation_halts() {
	mut f := &Fake{
		fail: true
	}
	mut a := restrain(f, Limits{})
	assert a.drive([0.5, 0.0], at([0.0, 0.0]), 1.0, true) == [0.0, 0.0]
	assert f.halts == 1

	// The body never moved, so the next command ramps up from rest, not from the command
	// that failed.
	assert a.last == [0.0, 0.0]
}
