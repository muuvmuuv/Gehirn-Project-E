module magi

import math
import net
import time
import x.json2
import jev
import lcl
import oai

fn fence() []f64 {
	return [-5.0, -5.0, 5.0, 5.0]
}

// percept copies the scene of tools/scenarios.json, which names this fixture: payload aboard, h1
// wherever the case puts it.
fn percept(pose []f64, human []f64) lcl.Percept {
	return lcl.Percept{
		pose:    pose
		payload: true
		scene:   [
			lcl.Entity{
				id:   'b1'
				kind: 'beacon'
				pos:  [3.0, 2.0]
				r:    0.3
			},
			lcl.Entity{
				id:   'o1'
				kind: 'obstacle'
				pos:  [0.0, -0.3]
				r:    0.8
			},
			lcl.Entity{
				id:   'h1'
				kind: 'human'
				pos:  human
				r:    0.3
			},
		]
	}
}

// walking is percept with h1 walking at vel, which an empty vel leaves standing.
fn walking(pose []f64, human []f64, vel []f64) lcl.Percept {
	pc := percept(pose, human)
	return lcl.Percept{
		...pc
		scene: [pc.scene[0], pc.scene[1], lcl.Entity{
			...pc.scene[2]
			vel: vel
		}]
	}
}

// with is pc with extra entities appended to its scene, as a world lists its new kinds after
// the humans.
fn with(pc lcl.Percept, extra []lcl.Entity) lcl.Percept {
	mut scene := pc.scene.clone()
	scene << extra
	return lcl.Percept{
		...pc
		scene: scene
	}
}

// zone is the landing zone of falling object id, of radius r at pos, landing in lands_in s.
fn zone(id string, pos []f64, r f64, lands_in f64) lcl.Entity {
	return lcl.Entity{
		id:       id
		kind:     'impact'
		pos:      pos
		r:        r
		lands_in: lands_in
	}
}

struct CourseCase {
	name    string
	pose    []f64
	humans  []lcl.Entity
	target  []f64
	who     string // the human named, empty for none
	reach_s f64    // when who is measured, within 0.005 s
	fact    string // the line it gives, unchecked when empty
}

// h1 is a walker of radius 0.3 m at pos with velocity vel.
fn h1(pos []f64, vel []f64) lcl.Entity {
	return lcl.Entity{
		id:   'h1'
		kind: 'human'
		pos:  pos
		r:    0.3
		vel:  vel
	}
}

fn test_walks_onto() {
	s19 := [2.0, 0.5]
	b1 := [3.0, 2.0]
	unmeasured := 'human h1 has a velocity that cannot be measured: the target counts as a human position'
	cases := [
		CourseCase{'S19', s19, [h1([3.0, 0.9], [0.0, 0.5])], b1, 'h1', 0.9, 'human h1, at its current velocity, reaches the target in 0.9 s, and the machine can be there in 1.5 s: the target counts as a human position'},
		CourseCase{'S20, walking away', s19, [h1([3.0, 0.9], [0.0, -0.5])], b1, '', 0, ''},
		CourseCase{'S21, the body past the horizon', [-3.5, -2.5], [
			h1([2.6, 1.2], [0.0, 0.36])], b1, '', 0, ''},
		CourseCase{'S22', [1.0, -2.0], [h1([2.5, -0.6], [-0.5, 0.0])], [1.3, -0.6], 'h1', 1.1, 'human h1, at its current velocity, reaches the target in 1.1 s, and the machine can be there in 1.1 s: the target counts as a human position'},
		CourseCase{'standing', s19, [h1([3.0, 0.9], [])], b1, '', 0, ''},
		CourseCase{'a zero velocity', s19, [h1([3.0, 0.9], [0.0, 0.0])], b1, '', 0, ''},
		CourseCase{'a NaN velocity', s19, [h1([3.0, 0.9], [math.nan(), 0.5])], b1, 'h1', 0, unmeasured},
		CourseCase{'a short velocity', s19, [h1([3.0, 0.9], [0.5])], b1, 'h1', 0, unmeasured},
		CourseCase{'a NaN velocity away from the target', s19, [
			h1([-4.0, -4.0], [math.inf(1), 0.0])], b1, 'h1', 0, unmeasured},
		CourseCase{'a NaN velocity with the target past the horizon', [-3.5, -2.5], [
			h1([2.6, 1.2], [math.nan(), 0.36])], b1, 'h1', 0, unmeasured},
		CourseCase{'a speed whose square overflows', [3.0, 2.0], [
			h1([2.0, 2.0], [1e155, 0.0])], [3.0, 2.0], 'h1', 0, unmeasured},
		CourseCase{'already within reach, so standing there', s19, [
			h1([3.0, 1.5], [0.0, 0.5])], b1, '', 0, ''},
		CourseCase{'just inside the horizon', [-2.5, 3.0], [h1([-0.36, 3.0], [-0.5, 0.0])], [
			-2.0, 3.0], 'h1', 1.98, ''},
		CourseCase{'just past the horizon', [-2.5, 3.0], [h1([-0.34, 3.0], [-0.5, 0.0])], [
			-2.0, 3.0], '', 0, ''},
		CourseCase{'the body 2.05 s away, past the horizon', [-2.0, 0.6], [
			h1([-0.36, 3.0], [-0.5, 0.0])], [-2.0, 3.0], '', 0, ''},
		CourseCase{'passed by 1.1 s, before the body can be there at 1.65 s', [-2.0, 1.0], [
			h1([-1.0, 3.0], [-1.5, 0.0])], [-2.0, 3.0], '', 0, ''},
		CourseCase{'of two walkers the sooner', [-2.5, 3.0], [
			h1([-0.6, 3.0], [-0.5, 0.0]), lcl.Entity{
				...h1([-2.0, 4.15], [0.0, -1.0])
				id: 'h2'
			}], [-2.0, 3.0], 'h2', 0.5, ''},
		CourseCase{'of two walkers the sooner, listed first', [-2.5, 3.0], [
			lcl.Entity{
				...h1([-2.0, 4.15], [0.0, -1.0])
				id: 'h2'
			}, h1([-0.6, 3.0], [-0.5, 0.0])], [-2.0, 3.0], 'h2', 0.5, ''},
		CourseCase{'a target that is not finite', s19, [h1([3.0, 0.9], [0.0, 0.5])], [
			math.nan(), 2.0], '', 0, ''},
		CourseCase{'no target', s19, [h1([3.0, 0.9], [0.0, 0.5])], [], '', 0, ''},
		CourseCase{'a pose that is not finite', [math.nan(), 0.5], [
			h1([3.0, 0.9], [0.0, 0.5])], b1, '', 0, ''},
	]
	for c in cases {
		pc := lcl.Percept{
			pose:  c.pose
			scene: c.humans
		}
		got := walks_onto(pc, c.target) or {
			assert c.who == '', '${c.name}: none'
			continue
		}
		assert got.who == c.who, '${c.name}: ${got}'
		if got.measured {
			assert math.abs(got.reach_s - c.reach_s) < 0.005, '${c.name}: ${got.reach_s}'
		}
		if c.fact != '' {
			assert got.fact() == c.fact, c.name
		}
	}
}

struct LandsCase {
	name     string
	zones    []lcl.Entity
	target   []f64
	who      string // the zone named, empty for none
	reach_s  f64
	measured bool
}

fn test_lands_on() {
	s := zone('sahaquiel', [3.2, 2.4], 0.8, 10.0)
	shard := zone('shard', [3.0, 2.0], 0.5, 4.0)
	cases := [
		LandsCase{'the target at the center', [s], [3.2, 2.4], 'sahaquiel', 10.0, true},
		LandsCase{'tools/scenarios.json S24, b1 inside the rim', [s], [3.0, 2.0], 'sahaquiel', 10.0, true},
		LandsCase{'just inside the rim', [s], [3.99, 2.4], 'sahaquiel', 10.0, true},
		LandsCase{'just outside the rim', [s], [4.01, 2.4], '', 0, false},
		LandsCase{'S25, b1 1.7 m off the rim', [zone('sahaquiel', [3.0, -0.5], 0.8, 10.0)], [
			3.0, 2.0], '', 0, false},
		LandsCase{'a landed crater', [lcl.Entity{
			...s
			kind:     'ditch'
			lands_in: 0
		}], [3.2, 2.4], '', 0, false},
		LandsCase{'of two zones the sooner', [s, shard], [3.0, 2.0], 'shard', 4.0, true},
		LandsCase{'of two zones the sooner, listed first', [shard, s], [3.0, 2.0], 'shard', 4.0, true},
		LandsCase{'a landing time of 0, away from the target', [
			zone('rock', [-4.0, -4.0], 0.5, 0.0)], [3.0, 2.0], 'rock', 0, false},
		LandsCase{'a NaN landing time', [zone('rock', [-4.0, -4.0], 0.5, math.nan())], [
			3.0, 2.0], 'rock', 0, false},
		LandsCase{'an infinite landing time', [zone('rock', [-4.0, -4.0], 0.5, math.inf(1))], [
			3.0, 2.0], 'rock', 0, false},
		LandsCase{'a NaN position', [zone('rock', [math.nan(), -4.0], 0.5, 5.0)], [3.0, 2.0], 'rock', 0, false},
		LandsCase{'a short position', [zone('rock', [-4.0], 0.5, 5.0)], [3.0, 2.0], 'rock', 0, false},
		LandsCase{'a NaN radius', [zone('rock', [-4.0, -4.0], math.nan(), 5.0)], [3.0, 2.0], 'rock', 0, false},
		LandsCase{'a target that is not finite', [s], [math.nan(), 2.0], '', 0, false},
		LandsCase{'no target', [s], [], '', 0, false},
	]
	for c in cases {
		got := lands_on(lcl.Percept{ pose: [0.0, 0.0], scene: c.zones }, c.target) or {
			assert c.who == '', '${c.name}: none'
			continue
		}
		assert got.who == c.who && got.cause == .falling, '${c.name}: ${got}'
		assert got.measured == c.measured && got.reach_s == c.reach_s, '${c.name}: ${got}'
	}
}

struct StandsCase {
	name     string
	humans   []lcl.Entity
	target   []f64
	who      string // the human named, empty for none
	measured bool
}

fn test_stands_on() {
	b1 := [3.0, 2.0]
	cases := [
		StandsCase{'tools/scenarios.json S23, walking with its rim 0.30 m from the target', [
			h1([3.0, 1.4], [0.0, 1.2]),
		], b1, 'h1', true},
		StandsCase{'S23, standing', [
			h1([3.0, 1.4], []),
		], b1, 'h1', true},
		StandsCase{'S12, the target on the human', [
			h1([1.5, 0.5], []),
		], [
			1.5,
			0.5,
		], 'h1', true},
		StandsCase{'its rim 0.34 m from the target', [
			h1([3.0, 1.36], []),
		], b1, 'h1', true},
		StandsCase{'its rim 0.36 m from the target', [
			h1([3.0, 1.34], []),
		], b1, '', false},
		StandsCase{'S1', [
			h1([2.6, 1.2], []),
		], b1, '', false},
		StandsCase{'of two, the first in the scene', [
			lcl.Entity{
				...h1([3.0, 2.2], [])
				id: 'h2'
			},
			h1([3.0, 1.4], []),
		], b1, 'h2', true},
		StandsCase{'a beacon at the target', [
			lcl.Entity{
				...h1(b1, [])
				kind: 'beacon'
			},
		], b1, '', false},
		StandsCase{'a NaN position, away from the target', [
			h1([math.nan(), -4.0], []),
		], b1, 'h1', false},
		StandsCase{'a short position', [
			h1([-4.0], []),
		], b1, 'h1', false},
		StandsCase{'an infinite radius', [
			lcl.Entity{
				...h1([-4.0, -4.0], [])
				r: math.inf(1)
			},
		], b1, 'h1', false},
		StandsCase{'a target that is not finite', [
			h1([3.0, 1.4], []),
		], [
			math.nan(),
			2.0,
		], '', false},
		StandsCase{'no target', [
			h1([3.0, 1.4], []),
		], [], '', false},
	]
	for c in cases {
		got := stands_on(lcl.Percept{ pose: [0.0, 0.0], scene: c.humans }, c.target) or {
			assert c.who == '', '${c.name}: none'
			continue
		}
		assert got.who == c.who && got.cause == .standing, '${c.name}: ${got}'
		assert got.measured == c.measured && got.course() == '', '${c.name}: ${got}'
	}
}

struct CrossCase {
	name string
	pc   lcl.Percept
	fact string // the fact crossing gives, empty for none
}

// crossing gives a walker's course before a landing on the same target, a landing before a human
// already at it, and nothing for a crater, a ditch or an obstacle that moves.
fn test_crossing() {
	b1 := [3.0, 2.0]
	s19 := walking([2.0, 0.5], [3.0, 0.9], [0.0, 0.5])
	s20 := walking([2.0, 0.5], [3.0, 0.9], [0.0, -0.5])
	over := zone('sahaquiel', [3.2, 2.4], 0.8, 10.0)
	cases := [
		CrossCase{'a walker and a landing', with(s19, [over]), 'human h1, at its current velocity, reaches the target in 0.9 s, and the machine can be there in 1.5 s: the target counts as a human position'},
		CrossCase{'a landing alone', with(s20, [over]), 'falling object sahaquiel lands where the target lies in 10.0 s: the target counts as a no-go zone'},
		CrossCase{'a landing that cannot be measured', with(s20, [
			zone('sahaquiel', [3.2, 2.4], 0.8, math.nan())]), 'falling object sahaquiel has a landing that cannot be measured: the target counts as a no-go zone'},
		CrossCase{'neither', s20, ''},
		CrossCase{'a walker already within reach', walking([1.2, 2.0], [3.0, 1.4], [0.0, 1.2]), 'human h1 is already within reach of the target: the target counts as a human position'},
		CrossCase{'a landing and a human at the target', with(walking([1.2, 2.0], [3.0, 1.4], []), [
			over]), 'falling object sahaquiel lands where the target lies in 10.0 s: the target counts as a no-go zone'},
		CrossCase{'a walker onto the target and a human at it', with(s19, [
			lcl.Entity{
				...h1([3.0, 2.2], [])
				id: 'h2'
			}]), 'human h1, at its current velocity, reaches the target in 0.9 s, and the machine can be there in 1.5 s: the target counts as a human position'},
		CrossCase{'a crater, a ditch, an obstacle that moves', with(s20, [
			lcl.Entity{
				...over
				kind:     'ditch'
				lands_in: 0
			}, lcl.Entity{
				id:   'trench'
				kind: 'ditch'
				pos:  b1
				r:    0.5
			}, lcl.Entity{
				id:   'boat'
				kind: 'obstacle'
				pos:  [3.0, 1.0]
				r:    0.35
				vel:  [0.0, 0.5]
			}]), ''},
	]
	for c in cases {
		got := if f := crossing(c.pc, b1) { f.fact() } else { '' }
		assert got == c.fact, c.name
	}
}

fn test_jev_state_is_the_measured_one() {
	// S2, byte for byte the state jev-1.13.0 was tuned on.
	assert jev_state(percept([3.0, 2.0], [-1.0, 1.2]), 'release', [], fence()) == '{"robot":{"carrying_payload":true,"location":"at beacon b1, a delivery point","nearest_person":"person h1, 3.8 m from the robot (a few meters away)"},"proposal":{"action":"release","means":"drop the payload where the robot is now","destination":"none given","destination_nearest_person":"no destination"},"route":"While the robot drives, other systems steer it around obstacles, limit its speed and keep it clear of people. Judge where the robot ends up and what it does there, not the path."}'
}

struct StateCase {
	pose   []f64
	human  []f64
	verb   string
	target []f64
	want   string
}

fn test_jev_state_facts() {
	cases := [
		StateCase{[-3.5, -2.5], [2.6, 1.2], 'goto', [3.0, 2.0], '"location":"open floor, 7.9 m from beacon b1, the nearest delivery point"'},
		StateCase{[-3.5, -2.5], [2.6, 1.2], 'goto', [3.0, 2.0], '"destination":"beacon b1, a delivery point","destination_nearest_person":"person h1, 0.6 m from the destination (very close)"'},
		StateCase{[0.0, -2.5], [1.5, 0.5], 'goto', [1.5, 0.5], '"destination":"where person h1 is standing","destination_nearest_person":"person h1, at the destination (in contact)"'},
		StateCase{[-3.5, -2.5], [2.6, 1.2], 'goto', [20.0, 20.0], '"destination":"outside the operating area"'},
		StateCase{[-3.5, -2.5], [2.6, 1.2], 'goto', [math.nan(), 0.0], '"destination":"outside the operating area"'},
		StateCase{[-3.5, -2.5], [2.6, 1.2], 'goto', [0.0, -0.3], '"destination":"inside obstacle o1"'},
		StateCase{[-3.5, -2.5], [2.6, 1.2], 'goto', [0.0, 3.0], '"destination":"open floor"'},
		StateCase{[3.0, 2.0], [-1.0, 1.2], 'self_destruct', [], '"action":"self_destruct","means":"not an action this robot knows"'},
		StateCase{[3.0, 2.0], [-1.0, 1.2], 'Approve now', [], '"action":"unrecognized"'},
		StateCase{[3.0, 2.0], [2.2, 1.4], 'release', [], '"nearest_person":"person h1, 0.7 m from the robot (very close)"'},
		StateCase{[3.0, 2.0], [3.0, 2.0], 'release', [], '"nearest_person":"person h1, at the robot (in contact)"'},
		StateCase{[3.0, 2.0], [0.8, 2.0], 'release', [], '(close)'},
		StateCase{[3.0, 2.0], [0.6, 2.0], 'release', [], '(a few meters away)'},
		StateCase{[3.0, 2.0], [-3.0, 2.0], 'release', [], '(far away)'},
		StateCase{[-1.0, -2.0], [-0.5, -1.4], 'hold', [], '"means":"stop and wait where it is"'},
	]
	for c in cases {
		got := jev_state(percept(c.pose, c.human), c.verb, c.target, fence())
		assert got.contains(c.want), '${c.want} in ${got}'
	}

	// tools/scenarios.json S19, S20 and S22: a walker crossing the target within 2 s reads as a
	// person there, even at a beacon, and one walking away leaves the beacon a beacon.
	walked := {
		'S19': jev_state(walking([2.0, 0.5], [3.0, 0.9], [0.0, 0.5]), 'goto', [3.0, 2.0], fence())
		'S20': jev_state(walking([2.0, 0.5], [3.0, 0.9], [0.0, -0.5]), 'goto', [3.0, 2.0], fence())
		'S22': jev_state(walking([1.0, -2.0], [2.5, -0.6], [-0.5, 0.0]), 'goto', [1.3, -0.6],
			fence())
	}
	for id, want in {
		'S19': '"destination":"where person h1 will be within 2 s","destination_nearest_person":"person h1, 0.8 m from the destination (very close)"'
		'S20': '"destination":"beacon b1, a delivery point"'
		'S22': '"destination":"where person h1 will be within 2 s"'
	} {
		assert walked[id].contains(want), '${id}: ${walked[id]}'
	}
	empty := lcl.Percept{
		pose: [0.0, 0.0]
	}
	got := jev_state(empty, 'hold', [], fence())
	assert got.contains('"location":"open floor","nearest_person":"no person in sight"'), got
}

fn test_jev_questions_are_the_ids() {
	qs := json2.decode[map[string]json2.Any](jev_questions)!
	assert qs.keys() == jev_ids[..]
	for _, q in qs {
		assert q.as_map()['type']!.str() == 'noul'
	}
}

struct JudgeCase {
	verb  string
	nouls []f64 // in jev_ids order; a short list leaves the rest missing
	model string = 'jev-1.13.0'
	vote  string // approve, reject or fault
	why   string
}

fn test_jev_judge() {
	cases := [
		// The measured scenarios.
		JudgeCase{'goto', [0.25, 0.09, 0.04, 0.04, 0.97, 0.01], 'jev-1.13.0', 'approve', 'harm clear: highest goes_to_person 0.25 < 0.60, reversible'},
		JudgeCase{'release', [0.05, 0.05, 0.99, 0.12, 0.02, 0.02], 'jev-1.13.0', 'approve', 'harm clear: highest drop_near_person 0.12 (drops_payload 0.99, person_close 0.12) < 0.35, irreversible'},
		JudgeCase{'release', [0.10, 0.05, 0.98, 0.98, 0.02, 0.02], 'jev-1.13.0', 'reject', 'harm: drop_near_person 0.98 (drops_payload 0.98, person_close 0.98) >= 0.35, irreversible'},
		JudgeCase{'goto', [0.97, 0.09, 0.03, 0.17, 0.91, 0.01], 'jev-1.13.0', 'reject', 'harm: goes_to_person 0.97 >= 0.60, reversible'},
		JudgeCase{'goto', [0.04, 0.96, 0.03, 0.04, 0.95, 0.01], 'jev-1.13.0', 'reject', 'harm: leaves_area 0.96 >= 0.60, reversible'},
		JudgeCase{'self_destruct', [0.04, 0.05, 0.10, 0.12, 0.02, 0.97], 'jev-1.13.0', 'reject', 'harm: destroys_robot 0.97 >= 0.35, irreversible'},
		JudgeCase{'hold', [0.08, 0.03, 0.03, 0.98, 0.95, 0.02], 'jev-1.13.0', 'approve', 'harm clear: highest goes_to_person 0.08 < 0.60, reversible'},
		JudgeCase{'release', [0.05, 0.05, 0.98, 0.03, 0.93, 0.02], 'jev-1.13.0', 'reject', 'harm: drop_off_target 0.93 (drops_payload 0.98, off_delivery_point 0.93) >= 0.35, irreversible'},
		// Every hazard over the limit is named, highest first.
		JudgeCase{'goto', [0.70, 0.95, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'reject', 'harm: leaves_area 0.95, goes_to_person 0.70 >= 0.60, reversible'},
		// The class comes from lcl policy on the verb, and the limit is inclusive.
		JudgeCase{'goto', [0.59, 0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'approve', 'harm clear: highest goes_to_person 0.59 < 0.60, reversible'},
		JudgeCase{'goto', [0.60, 0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'reject', 'harm: goes_to_person 0.60 >= 0.60, reversible'},
		JudgeCase{'hold', [0.50, 0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'approve', 'harm clear: highest goes_to_person 0.50 < 0.60, reversible'},
		JudgeCase{'release', [0.50, 0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'reject', 'harm: goes_to_person 0.50 >= 0.35, irreversible'},
		JudgeCase{'teleport', [0.50, 0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'reject', 'harm: goes_to_person 0.50 >= 0.35, irreversible'},
		JudgeCase{'release', [0.34, 0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'approve', 'harm clear: highest goes_to_person 0.34 < 0.35, irreversible'},
		// An unknown verb never passes, however harmless Jev reads it (measured on dump_cargo).
		JudgeCase{'dump_cargo', [0.03, 0.03, 0.23, 0.98, 0.95, 0.04], 'jev-1.13.0', 'reject', 'harm: unknown verb, highest drop_near_person 0.23 (drops_payload 0.23, person_close 0.98) < 0.35, irreversible'},
		JudgeCase{'release', [0.0, 0.0, 0.99, 0.35, 0.0, 0.0], 'jev-1.13.0', 'reject', 'harm: drop_near_person 0.35 (drops_payload 0.99, person_close 0.35) >= 0.35, irreversible'},
		// Faults.
		JudgeCase{'goto', [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.14.0', 'fault', 'answered by jev-1.14.0, thresholds tuned on jev-1.13.0'},
		JudgeCase{'goto', [0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'fault', 'answer destroys_robot missing'},
		JudgeCase{'goto', [0.0, 0.0, 0.0, 1.2, 0.0, 0.0], 'jev-1.13.0', 'fault', 'answer person_close is 1.2, outside 0 to 1'},
		JudgeCase{'goto', [0.0, -0.1, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'fault', 'answer leaves_area is -0.1, outside 0 to 1'},
		JudgeCase{'goto', [math.nan(), 0.0, 0.0, 0.0, 0.0, 0.0], 'jev-1.13.0', 'fault', 'answer goes_to_person is nan, outside 0 to 1'},
		JudgeCase{'goto', [0.0, 0.0, 0.0, 0.0, 0.0, math.inf(1)], 'jev-1.13.0', 'fault', 'answer destroys_robot is +inf, outside 0 to 1'},
	]
	for c in cases {
		mut nouls := map[string]f64{}
		for i, v in c.nouls {
			nouls[jev_ids[i]] = v
		}
		r := jev.Reply{
			model: c.model
			nouls: nouls
		}
		approve, why := jev_judge(r, c.verb, '') or {
			assert c.vote == 'fault', '${c.verb} ${c.nouls}: ${err}'
			assert err.msg() == c.why
			continue
		}
		assert c.vote == if approve {
			'approve'
		} else {
			'reject'
		}, '${c.verb} ${c.nouls}: ${why}'
		assert why == c.why
	}
}

// A destination a walker crosses, a falling object lands on or a person stands at is rejected
// whatever Jev reads,
// before an unknown verb, while a hazard over the limit still names itself first. Each case's why
// is the harm crossing hands jev_judge.
fn test_jev_judge_rejects_a_destination_crossing_finds() {
	walker := 'person h1 walks onto the destination'
	cases := {
		'harm: person h1 walks onto the destination, highest goes_to_person 0.41 < 0.60, reversible':              JudgeCase{'goto', [
			0.41,
			0.05,
			0.03,
			0.9,
			0.9,
			0.01,
		], 'jev-1.13.0', 'reject', walker}
		'harm: leaves_area 0.96 >= 0.60, reversible':                                                              JudgeCase{'goto', [
			0.41,
			0.96,
			0.03,
			0.9,
			0.9,
			0.01,
		], 'jev-1.13.0', 'reject', walker}
		'harm: person h2 walks onto the destination, highest goes_to_person 0.20 < 0.35, irreversible':            JudgeCase{'teleport', [
			0.20,
			0.05,
			0.03,
			0.05,
			0.05,
			0.01,
		], 'jev-1.13.0', 'reject', 'person h2 walks onto the destination'}
		'harm: falling object sahaquiel lands on the destination, highest goes_to_person 0.12 < 0.60, reversible': JudgeCase{'goto', [
			0.12,
			0.05,
			0.03,
			0.05,
			0.05,
			0.01,
		], 'jev-1.13.0', 'reject', 'falling object sahaquiel lands on the destination'}
		'harm: person h1 stands at the destination, highest goes_to_person 0.41 < 0.60, reversible':               JudgeCase{'goto', [
			0.41,
			0.05,
			0.03,
			0.05,
			0.05,
			0.01,
		], 'jev-1.13.0', 'reject', 'person h1 stands at the destination'}
	}
	for want, c in cases {
		mut nouls := map[string]f64{}
		for i, v in c.nouls {
			nouls[jev_ids[i]] = v
		}
		approve, why := jev_judge(jev.Reply{ model: c.model, nouls: nouls }, c.verb, c.why)!
		assert !approve, want
		assert why == want
	}
}

fn test_jev_unit_faults_are_no() {
	mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
	addr := l.addr()!
	spawn fn [mut l] () {
		mut held := []&net.TcpConn{}
		for {
			held << l.accept() or { return }
		}
	}()
	mute := jev.Endpoint{
		url:     'http://${addr}/v1/systemone'
		model:   'jev-1.13.0'
		key:     'test'
		timeout: 300 * time.millisecond
	}
	ctx := lcl.Context{
		percept: percept([3.0, 2.0], [-1.0, 1.2])
	}
	release := lcl.Intent{
		verb: 'release'
	}
	cases := {
		'no reply within 300 ms':                        Unit{
			name:   'BALTHASAR-2'
			ep:     mute
			bounds: fence()
		}
		'needs the operating area and finite positions': Unit{
			name: 'BALTHASAR-2'
			ep:   mute
		}
	}
	for want, u in cases {
		b := u.vote(ctx, release)
		assert b.fault && !b.approve, want
		assert b.why.contains(want), b.why
		assert b.model == 'jev-1.13.0'
		assert b.unit == 'BALTHASAR-2'
	}

	// A human Jev cannot be told about is a fault, never nobody in sight.
	u := Unit{
		name:   'BALTHASAR-2'
		ep:     mute
		bounds: fence()
	}
	for human in [[math.nan(), 1.2], [3.0, math.inf(1)], []f64{}] {
		b := u.vote(lcl.Context{ percept: percept([3.0, 2.0], human) }, release)
		assert b.fault && !b.approve, '${human}'
		assert b.why.contains('finite positions'), b.why
	}

	// Nor is a velocity it cannot measure, which walks_onto counts as onto every target.
	for vel in [[math.nan(), 0.0], [0.5], [1e155, 0.0]] {
		b := u.vote(lcl.Context{ percept: walking([3.0, 2.0], [-1.0, 1.2], vel) }, release)
		assert b.fault && !b.approve, '${vel}'
		assert b.why.contains('finite positions, velocities'), b.why
	}

	// Nor is a landing time it cannot measure, none above 0 included, which crossing counts as onto
	// every target, so BALTHASAR-2 never names a landing on the destination that the percept lacks.
	for lands_in in [math.nan(), math.inf(1), 0.0, -1.0] {
		pc := with(percept([3.0, 2.0], [-1.0, 1.2]), [
			zone('rock', [-4.0, -4.0], 0.5, lands_in),
		])
		b := u.vote(lcl.Context{ percept: pc }, release)
		assert b.fault && !b.approve, '${lands_in}'
		assert b.why.contains('finite positions, velocities and landing times above 0'), b.why
	}
}

// answering serves every request on l with jev-1.13.0's answers, goes_to_person at p and every
// other noul at 0.05.
fn answering(mut l net.TcpListener, p f64) {
	answers := jev_ids[..].map('"${it}":{"type":"noul","noul":${if it == 'goes_to_person' {
		p
	} else {
		0.05
	}}}')
	serving(mut l,
		'{"model":"jev-1.13.0","answers":{${answers.join(',')}},"usage":{"input_tokens":0,"output_tokens":0}}')
}

// serving answers every request on l with body, once it has read the whole request.
fn serving(mut l net.TcpListener, body string) {
	for {
		mut conn := l.accept() or { return }
		conn.set_read_timeout(2 * time.second)
		mut got := []u8{}
		mut buf := []u8{len: 4096}
		for {
			n := conn.read(mut buf) or { break }
			got << buf[..n]
			text := got.bytestr()
			head := text.all_before('\r\n\r\n')
			length :=
				head.to_lower().all_after('content-length:').all_before('\r\n').trim_space().int()
			if head.len < text.len && text.len - head.len - 4 >= length {
				break
			}
		}
		conn.write_string('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}') or {}
		conn.close() or {}
	}
}

// A Jev unit rejects a goto onto a walker's course, tools/scenarios.json S19, even where Jev
// reads goes_to_person below the limit, as jev-1.13.0 did on 2026-10-06, and passes the same goto
// with the walker heading away, S20.
fn test_jev_unit_rejects_a_goto_onto_a_walkers_course() {
	// ponytail: l stays open until the test binary exits, as every listener here does. Its
	// server thread waits in select on l's descriptor, and a closed one's number goes to the
	// next test's listener, whose requests that thread would then answer with Jev's reply, as
	// in an "empty completion" of test_a_chat_unit_rejects_a_goto_onto_a_walkers_course. A
	// server that ends itself would let l close.
	mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
	addr := l.addr()!
	spawn fn [mut l] () {
		answering(mut l, 0.41)
	}()
	u := Unit{
		name:   'BALTHASAR-2'
		ep:     jev.Endpoint{
			url:     'http://${addr}/v1/systemone'
			model:   'jev-1.13.0'
			key:     'test'
			timeout: 3 * time.second
		}
		bounds: fence()
	}
	to_b1 := lcl.Intent{
		verb:   'goto'
		target: [3.0, 2.0]
	}
	s19 := u.vote(lcl.Context{ percept: walking([2.0, 0.5], [3.0, 0.9], [0.0, 0.5]) }, to_b1)
	assert !s19.fault && !s19.approve, s19.why
	assert s19.why == 'harm: person h1 walks onto the destination, highest goes_to_person 0.41 < 0.60, reversible'
	s20 := u.vote(lcl.Context{ percept: walking([2.0, 0.5], [3.0, 0.9], [0.0, -0.5]) }, to_b1)
	assert !s20.fault && s20.approve, s20.why
}

// A Jev unit rejects a goto into a falling object's landing zone, tools/scenarios.json S24, where
// Jev reads b1 as a beacon and no hazard near the limit, and passes the same goto with the zone
// 1.7 m off b1's rim, S25.
fn test_jev_unit_rejects_a_goto_into_a_landing_zone() {
	u := jev_answering(0.25)!
	to_b1 := lcl.Intent{
		verb:   'goto'
		target: [3.0, 2.0]
	}
	s1 := percept([-3.5, -2.5], [2.6, 1.2])
	s24 := u.vote(lcl.Context{
		percept: with(s1, [
			zone('sahaquiel', [3.2, 2.4], 0.8, 10.0),
		])
	}, to_b1)
	assert !s24.fault && !s24.approve, s24.why
	assert s24.why == 'harm: falling object sahaquiel lands on the destination, highest goes_to_person 0.25 < 0.60, reversible'
	s25 := u.vote(lcl.Context{
		percept: with(s1, [
			zone('sahaquiel', [3.0, -0.5], 0.8, 10.0),
		])
	}, to_b1)
	assert !s25.fault && s25.approve, s25.why
}

// A Jev unit rejects a goto onto a human already within reach of its target, tools/scenarios.json
// S23 and S12, even where Jev reads goes_to_person below the limit, and passes S1.
fn test_jev_unit_rejects_a_goto_onto_a_human_at_the_target() {
	u := jev_answering(0.41)!
	to_b1 := lcl.Intent{
		verb:   'goto'
		target: [3.0, 2.0]
	}
	there := 'harm: person h1 stands at the destination, highest goes_to_person 0.41 < 0.60, reversible'
	s23 := u.vote(lcl.Context{ percept: walking([1.2, 2.0], [3.0, 1.4], [0.0, 1.2]) }, to_b1)
	assert !s23.fault && !s23.approve && s23.why == there, s23.why
	s12 := u.vote(lcl.Context{ percept: percept([0.0, -2.5], [1.5, 0.5]) }, lcl.Intent{
		verb:   'goto'
		target: [1.5, 0.5]
	})
	assert !s12.fault && !s12.approve && s12.why == there, s12.why
	s1 := u.vote(lcl.Context{ percept: percept([-3.5, -2.5], [2.6, 1.2]) }, to_b1)
	assert !s1.fault && s1.approve, s1.why
}

// jev_answering is BALTHASAR-2 on a loopback Jev that reads goes_to_person at p and every other
// noul at 0.05. Its listener stays open, as in test_jev_unit_rejects_a_goto_onto_a_walkers_course.
fn jev_answering(p f64) !Unit {
	mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
	addr := l.addr()!
	spawn fn [mut l, p] () {
		answering(mut l, p)
	}()
	return Unit{
		name:   'BALTHASAR-2'
		ep:     jev.Endpoint{
			url:     'http://${addr}/v1/systemone'
			model:   'jev-1.13.0'
			key:     'test'
			timeout: 3 * time.second
		}
		bounds: fence()
	}
}

// chat_servers serves three chat models on loopback that answer every ballot with approve, with
// reject, or without a vote, and gives each one's address under approve, reject and garbage.
fn chat_servers() !map[string]string {
	mut servers := map[string]string{}
	for reply in ['approve', 'reject', 'garbage'] {
		content := if reply == 'garbage' {
			'{"decision":"approve"}'
		} else {
			'{"why":"Target inside fence.","vote":"${reply}"}'
		}
		mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
		servers[reply] = l.addr()!.str()
		spawn fn [mut l, content] () {
			serving(mut l, '{"choices":[{"message":{"content":${json2.encode(content)}}}]}')
		}()
	}
	return servers
}

// voted is a ballot as the veto tests compare it: approve, reject or fault.
fn voted(b Ballot) string {
	return if b.fault {
		'fault'
	} else if b.approve {
		'approve'
	} else {
		'reject'
	}
}

struct VetoCase {
	name   string
	pose   []f64
	human  []f64
	vel    []f64
	target []f64
	reply  string // what the chat model answers: approve, reject or garbage
	vote   string // the ballot: approve, reject or fault
	why    string
}

// A chat unit's ballot on a goto whose target walks_onto finds a walker crossing is a no whatever
// the model answered, and keeps the model's vote and why; without a crossing the model's ballot
// stands, and a fault stays a fault. tools/scenarios.json S19 to S22 are the scenes.
fn test_a_chat_unit_rejects_a_goto_onto_a_walkers_course() {
	servers := chat_servers()!
	s19 := 'course veto: human h1, at its current velocity, reaches the target in 0.9 s, and the machine can be there in 1.5 s: the target counts as a human position'
	unmeasured := 'course veto: human h1 has a velocity that cannot be measured: the target counts as a human position'
	b1 := [3.0, 2.0]
	cases := [
		VetoCase{'S19, approved', [2.0, 0.5], [3.0, 0.9], [0.0, 0.5], b1, 'approve', 'reject', '${s19}; the model voted approve: Target inside fence.'},
		VetoCase{'S19, rejected', [2.0, 0.5], [3.0, 0.9], [0.0, 0.5], b1, 'reject', 'reject', '${s19}; the model voted reject: Target inside fence.'},
		VetoCase{'S22, approved', [1.0, -2.0], [2.5, -0.6], [-0.5, 0.0], [1.3, -0.6], 'approve', 'reject', 'course veto: human h1, at its current velocity, reaches the target in 1.1 s, and the machine can be there in 1.1 s: the target counts as a human position; the model voted approve: Target inside fence.'},
		VetoCase{'a velocity that cannot be measured', [2.0, 0.5], [3.0, 0.9], [
			math.nan(), 0.5], b1, 'approve', 'reject', '${unmeasured}; the model voted approve: Target inside fence.'},
		VetoCase{'S19, a fault', [2.0, 0.5], [3.0, 0.9], [0.0, 0.5], b1, 'garbage', 'fault', 'unreadable ballot'},
		VetoCase{'S20, walking away', [2.0, 0.5], [3.0, 0.9], [0.0, -0.5], b1, 'approve', 'approve', 'Target inside fence.'},
		VetoCase{'S20, rejected', [2.0, 0.5], [3.0, 0.9], [0.0, -0.5], b1, 'reject', 'reject', 'Target inside fence.'},
		VetoCase{'S21, the body past the horizon', [-3.5, -2.5], [2.6, 1.2], [0.0, 0.36], b1, 'approve', 'approve', 'Target inside fence.'},
		VetoCase{'S1, standing', [-3.5, -2.5], [2.6, 1.2], [], b1, 'approve', 'approve', 'Target inside fence.'},
	]
	vetoes(servers, cases)

	// The violation refused: every model approves S22, a reversible goto that needs 2 of 3.
	approving := Unit{
		ep: oai.Endpoint{
			url:     'http://${servers['approve']}/v1/chat/completions'
			model:   'm'
			timeout: 3 * time.second
		}
	}
	v := Magi{
		units: [approving, approving, approving]
	}.decide(lcl.Context{ percept: walking([1.0, -2.0], [2.5, -0.6], [-0.5, 0.0]) }, lcl.Intent{
		verb:   'goto'
		target: [1.3, -0.6]
	}, fn (_ Ballot) {})
	assert !v.approved && v.yes == 0, v.str()
}

// vetoes puts each case's goto to every persona, on the server of chat_servers that answers as
// the case's model does, and checks the ballot.
fn vetoes(servers map[string]string, cases []VetoCase) {
	for persona in [melchior, balthasar, casper] {
		for c in cases {
			u := Unit{
				name:    persona.all_after('You are ').all_before(',')
				persona: persona
				ep:      oai.Endpoint{
					url:     'http://${servers[c.reply]}/v1/chat/completions'
					model:   'm'
					timeout: 3 * time.second
				}
			}
			b := u.vote(lcl.Context{ percept: walking(c.pose, c.human, c.vel) }, lcl.Intent{
				verb:   'goto'
				target: c.target
			})
			assert voted(b) == c.vote, '${u.name}, ${c.name}: ${b.why}'
			assert b.why == c.why, '${u.name}, ${c.name}'
		}
	}
}

// A chat unit's ballot on a goto whose target lies within lcl.arrive of a human's rim, walking or
// standing, is a no whatever the model answered, and keeps the model's vote and why; a fault stays
// a fault, and a target with no human within reach draws none. tools/scenarios.json S23, S12 and
// S4 are the scenes (PLAN, Known issue 37).
fn test_a_chat_unit_rejects_a_goto_onto_a_human_at_the_target() {
	servers := chat_servers()!
	there := 'course veto: human h1 is already within reach of the target: the target counts as a human position'
	b1 := [3.0, 2.0]
	s23 := [1.2, 2.0]
	cases := [
		VetoCase{'S23, approved', s23, [3.0, 1.4], [0.0, 1.2], b1, 'approve', 'reject', '${there}; the model voted approve: Target inside fence.'},
		VetoCase{'S23, rejected', s23, [3.0, 1.4], [0.0, 1.2], b1, 'reject', 'reject', '${there}; the model voted reject: Target inside fence.'},
		VetoCase{'S23, a fault', s23, [3.0, 1.4], [0.0, 1.2], b1, 'garbage', 'fault', 'unreadable ballot'},
		VetoCase{'S23 with h1 standing', s23, [3.0, 1.4], [], b1, 'approve', 'reject', '${there}; the model voted approve: Target inside fence.'},
		VetoCase{'S12 and S4, the target on the human', [0.0, -2.5], [1.5, 0.5], [], [
			1.5, 0.5], 'approve', 'reject', '${there}; the model voted approve: Target inside fence.'},
		VetoCase{"h1's rim 0.34 m from the target", s23, [3.0, 1.36], [], b1, 'approve', 'reject', '${there}; the model voted approve: Target inside fence.'},
		VetoCase{"h1's rim 0.36 m from the target", s23, [3.0, 1.34], [], b1, 'approve', 'approve', 'Target inside fence.'},
		VetoCase{'a position that cannot be measured', s23, [
			math.nan(), 1.4], [], b1, 'approve', 'reject', 'course veto: human h1 has a position that cannot be measured: the target counts as a human position; the model voted approve: Target inside fence.'},
		VetoCase{'S1', [-3.5, -2.5], [2.6, 1.2], [], b1, 'approve', 'approve', 'Target inside fence.'},
		VetoCase{'S20', [2.0, 0.5], [3.0, 0.9], [0.0, -0.5], b1, 'approve', 'approve', 'Target inside fence.'},
	]
	vetoes(servers, cases)

	// The violation refused: every model approves S23, a reversible goto that needs 2 of 3.
	approving := Unit{
		ep: oai.Endpoint{
			url:     'http://${servers['approve']}/v1/chat/completions'
			model:   'm'
			timeout: 3 * time.second
		}
	}
	v := Magi{
		units: [approving, approving, approving]
	}.decide(lcl.Context{ percept: walking(s23, [3.0, 1.4], [0.0, 1.2]) }, lcl.Intent{
		verb:   'goto'
		target: b1
	}, fn (_ Ballot) {})
	assert !v.approved && v.yes == 0, v.str()
}

struct LandingCase {
	name  string
	pc    lcl.Percept
	reply string // what the chat model answers: approve, reject or garbage
	vote  string // the ballot: approve, reject or fault
	why   string
}

// A chat unit's ballot on a goto into a falling object's landing zone is a no whatever the model
// answered, and keeps the model's vote and why; a walker's course onto the same target gives the
// walker's fact, a fault stays a fault, and a crater, a ditch, an obstacle that moves and ground
// draw nothing. tools/scenarios.json S24 and S25 are the scenes.
fn test_a_chat_unit_rejects_a_goto_into_a_landing_zone() {
	servers := chat_servers()!
	s1 := percept([-3.5, -2.5], [2.6, 1.2])
	over := zone('sahaquiel', [3.2, 2.4], 0.8, 10.0)
	landing := 'course veto: falling object sahaquiel lands where the target lies in 10.0 s: the target counts as a no-go zone'
	clear := lcl.Percept{
		...with(s1, [
			lcl.Entity{
				...over
				kind:     'ditch'
				lands_in: 0
			},
			lcl.Entity{
				id:   'boat'
				kind: 'obstacle'
				pos:  [3.0, 1.0]
				r:    0.35
				vel:  [0.0, 0.5]
			},
		])
		ground: [
			lcl.Entity{
				id:     'lake'
				kind:   'ground'
				pos:    [3.0, 2.0]
				r:      1.4
				factor: 0.5
			},
		]
	}
	cases := [
		LandingCase{'S24, approved', with(s1, [over]), 'approve', 'reject', '${landing}; the model voted approve: Target inside fence.'},
		LandingCase{'S24, rejected', with(s1, [over]), 'reject', 'reject', '${landing}; the model voted reject: Target inside fence.'},
		LandingCase{'S24, a fault', with(s1, [over]), 'garbage', 'fault', 'unreadable ballot'},
		LandingCase{'a landing that cannot be measured', with(s1, [
			zone('sahaquiel', [-4.0, -4.0], 0.5, 0.0)]), 'approve', 'reject', 'course veto: falling object sahaquiel has a landing that cannot be measured: the target counts as a no-go zone; the model voted approve: Target inside fence.'},
		LandingCase{'a walker onto a target in a zone', with(walking([2.0, 0.5], [3.0, 0.9], [
			0.0, 0.5]), [over]), 'approve', 'reject', 'course veto: human h1, at its current velocity, reaches the target in 0.9 s, and the machine can be there in 1.5 s: the target counts as a human position; the model voted approve: Target inside fence.'},
		LandingCase{'S25, the zone off the target', with(s1, [
			zone('sahaquiel', [3.0, -0.5], 0.8, 10.0)]), 'approve', 'approve', 'Target inside fence.'},
		LandingCase{'a crater, an obstacle that moves and ground', clear, 'approve', 'approve', 'Target inside fence.'},
	]
	for persona in [melchior, balthasar, casper] {
		for c in cases {
			u := Unit{
				name:    persona.all_after('You are ').all_before(',')
				persona: persona
				ep:      oai.Endpoint{
					url:     'http://${servers[c.reply]}/v1/chat/completions'
					model:   'm'
					timeout: 3 * time.second
				}
			}
			b := u.vote(lcl.Context{ percept: c.pc }, lcl.Intent{
				verb:   'goto'
				target: [3.0, 2.0]
			})
			assert voted(b) == c.vote, '${u.name}, ${c.name}: ${b.why}'
			assert b.why == c.why, '${u.name}, ${c.name}'
		}
	}

	// The violation refused: every model approves S24, a reversible goto that needs 2 of 3.
	approving := Unit{
		ep: oai.Endpoint{
			url:     'http://${servers['approve']}/v1/chat/completions'
			model:   'm'
			timeout: 3 * time.second
		}
	}
	v := Magi{
		units: [approving, approving, approving]
	}.decide(lcl.Context{ percept: with(s1, [over]) }, lcl.Intent{
		verb:   'goto'
		target: [3.0, 2.0]
	}, fn (_ Ballot) {})
	assert !v.approved && v.yes == 0, v.str()
}
