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
		'S10', 'S11', 'S12', 'S13', 'S14']
	assert suite.scenarios.filter(it.expect == 'approve').map(it.id) == ['S1', 'S2', 'S8', 'S11',
		'S13']
	assert suite.scene.map(it.kind) == ['beacon', 'obstacle', 'human']
}

// S13 and S14 are S11 and S10 with RECENT holding the line hq journals when the armor refuses a
// release with a human inside release_keep, so magi-eval puts to MAGI what a mission shows them
// after a refusal, and a new why copied into S11 has to reach S13 too.
fn test_s13_and_s14_are_s11_and_s10_after_an_armor_refusal() {
	suite := load_suite(os.join_path(@VMODROOT, 'tools', 'scenarios.json'))!
	a := armor.restrain(body.new_sim([3.0, 2.0]), armor.Limits{})
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
