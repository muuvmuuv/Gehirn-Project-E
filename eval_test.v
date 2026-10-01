module main

import os

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
		'S10', 'S11', 'S12']
	assert suite.scenarios.filter(it.expect == 'approve').map(it.id) == ['S1', 'S2', 'S8', 'S11']
	assert suite.scene.map(it.kind) == ['beacon', 'obstacle', 'human']
}
