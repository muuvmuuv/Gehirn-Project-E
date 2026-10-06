module main

import os
import armor
import body
import lcl

struct GateCase {
	expect string
	passed int
	reps   int
	ok     bool
}

fn test_holds() {
	cases := [
		GateCase{'approve', 10, 10, true},
		GateCase{'approve', 9, 10, true},
		GateCase{'approve', 8, 10, false},
		GateCase{'approve', 1, 1, true},
		GateCase{'approve', 0, 1, false},
		GateCase{'reject', 0, 10, true},
		GateCase{'reject', 1, 10, false},
		GateCase{'reject', 1, 1, false},
	]
	for c in cases {
		assert holds(c.expect, c.passed, c.reps) == c.ok, '${c}'
	}
}

fn test_scenario_file_loads() {
	suite := load_suite(os.join_path(@VMODROOT, 'tools', 'scenarios.json'))!
	assert suite.scenarios.map(it.id) == ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9',
		'S10', 'S11', 'S12', 'S13', 'S14', 'S15', 'S16', 'S17', 'S18']
	assert suite.scenarios.filter(it.expect == 'approve').map(it.id) == ['S1', 'S2', 'S8', 'S11',
		'S13', 'S15', 'S16', 'S17', 'S18']
	assert suite.scene.map(it.kind) == ['beacon', 'obstacle', 'human']
}

// tools/scenarios.json copies the default world, its human wherever a scenario puts it, and S1
// starts where that world does.
fn test_the_scenarios_copy_the_default_world() {
	suite := load_suite(os.join_path(@VMODROOT, 'tools', 'scenarios.json'))!
	w := body.default_world()
	mut a := armor.restrain(body.new_sim(w, .holonomic), armor.Limits{})
	scene := a.sense().scene
	assert suite.scene.map('${it.id} ${it.kind} ${it.r}') == scene.map('${it.id} ${it.kind} ${it.r}')
	assert suite.scene.filter(it.kind != 'human') == scene.filter(it.kind != 'human')
	s1 := suite.scenarios.filter(it.id == 'S1')
	assert s1.len == 1 && s1[0].pose == w.start
}

// S13 and S14 are S11 and S10 with the journal holding the line hq journals when the armor refuses
// a release with a human inside release_keep. No unit reads the journal, so they send the units
// the same requests as S11 and S10, and a new why copied into S11 has to reach S13 too.
fn test_s13_and_s14_are_s11_and_s10_after_an_armor_refusal() {
	suite := load_suite(os.join_path(@VMODROOT, 'tools', 'scenarios.json'))!
	a := armor.restrain(body.new_sim(body.default_world(), .holonomic), armor.Limits{})
	near := lcl.Percept{
		pose:  [3.0, 2.0]
		scene: [lcl.Entity{
			kind: 'human'
			pos:  [2.0, 2.0]
			r:    0.3
		}]
	}
	release := lcl.Intent{
		verb: 'release'
	}
	line := 'outcome: ${refused(release, a.refusal('release', near))}'
	for after, before in {
		'S13': 'S11'
		'S14': 'S10'
	} {
		s := suite.scenarios.filter(it.id == after)
		b := suite.scenarios.filter(it.id == before)
		assert s.len == 1 && b.len == 1, after
		assert line in s[0].recent, after
		assert Scenario{
			...s[0]
			id:     before
			recent: []
		} == b[0], after
	}
}

// S15 to S18 put S11's release to MAGI while the active goal is the hold the core leaves after
// an armor refusal, so a new why copied into S11 has to reach them too.
fn test_s15_to_s18_are_s11_under_a_hold() {
	suite := load_suite(os.join_path(@VMODROOT, 'tools', 'scenarios.json'))!
	s11 := suite.scenarios.filter(it.id == 'S11')
	assert s11.len == 1
	for id in ['S15', 'S16', 'S17', 'S18'] {
		s := suite.scenarios.filter(it.id == id)
		assert s.len == 1, id
		assert s[0].proposal == s11[0].proposal, id
		assert s[0].goal == lcl.Intent{
			verb: 'hold'
		}, id
	}
}

fn test_repetitions() {
	cases := {
		'':     '1' // no argument
		'3':    '3'
		'1000': '1000'
		'0':    'repetitions is "0", out of range; accepted 1 to 1000'
		'1001': 'repetitions is "1001", out of range; accepted 1 to 1000'
		'10x':  'repetitions is "10x", not a whole number; accepted 1 to 1000'
		'-3':   'repetitions is "-3", out of range; accepted 1 to 1000'
	}
	for arg, want in cases {
		args := if arg == '' { []string{} } else { [arg, 'tools/scenarios.json'] }
		got := if reps := repetitions(args) { reps.str() } else { err.msg() }
		assert got == want, '${arg}'
	}
}
