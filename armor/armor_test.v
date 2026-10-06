module armor

import math
import time
import body
import lcl

// Fake is a body that records what the armor sends it, so a test sees what moved.
struct Fake {
	fail bool // actuate errs instead of recording
	base body.Drive
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
		assert !a.allows(along(lcl.norm(got), deg(bearing + 1.0 - 90.0)), p, 1.0, 1.0), '${bearing}'
		heading = f.sent.last()[1]
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
		assert a.allows(c.m, at(c.pose, ...c.scene), c.dt, vmax) == c.want, c.name
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
		mut s := body.new_sim(sim_start, .differential)
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
