module armor

import math
import lcl

// Fake is a body that records what the armor sends it, so a test sees what moved.
struct Fake {
	fail bool // actuate errs instead of recording
mut:
	sent    [][]f64
	effects []string
	halts   int
}

fn (f &Fake) dof() int {
	return 2
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
	// halfway between human_stop and human_slow.
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
