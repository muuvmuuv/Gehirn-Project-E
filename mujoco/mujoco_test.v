module mujoco

import math
import os

// Every test sits in a $if mujoco ? block, since the module's files build only with -d mujoco and
// `v test .` compiles this file without it (ADR-0008).

// ball is a ball dropped from 1 m onto a floor.
const ball = '<mujoco><worldbody><geom type="plane" size="5 5 0.1"/><body pos="0 0 1"><freejoint/><geom type="sphere" size="0.1"/></body></worldbody></mujoco>'

// base is a 20 kg planar base on slides along x and y and a hinge about z, with velocity
// actuators as body's MuJoCo body has them, west of a pillar of 0.8 m radius at the origin, and a
// mocap human of 0.3 m radius north of it.
const base = '<mujoco><option timestep="0.002"/><worldbody>
<body name="base" pos="-3 0 0.2"><joint name="x" type="slide" axis="1 0 0"/><joint name="y" type="slide" axis="0 1 0"/><joint name="yaw" type="hinge" axis="0 0 1"/><geom name="base" type="cylinder" size="0.25 0.2" mass="20"/></body>
<geom name="pillar" type="cylinder" pos="0 0 0.2" size="0.8 0.2"/>
<body mocap="true" pos="-3 3 0.2"><geom type="capsule" size="0.3 0.2"/></body>
</worldbody><actuator><velocity joint="x" kv="400" forcerange="-200 200"/><velocity joint="y" kv="400" forcerange="-200 200"/><velocity joint="yaw" kv="12.5" forcerange="-50 50"/></actuator></mujoco>'

// child is the case a copy of this test binary runs in testsuite_begin, when the test that starts
// it sets MUJOCO_TEST_CHILD: an infinite velocity, which ends the process in step.
fn testsuite_begin() {
	$if mujoco ? {
		if os.getenv('MUJOCO_TEST_CHILD') == 'unstable' {
			mut m := load(base) or { exit(3) }
			unsafe {
				m.d.qvel[0] = math.inf(1)
			}
			m.step()
			exit(0)
		}
	}
}

// A dropped ball comes to rest on the floor, its radius above it.
fn test_a_ball_comes_to_rest_on_the_floor() {
	$if mujoco ? {
		mut m := load(ball)!
		for _ in 0 .. 500 {
			m.step()
		}
		assert math.abs(m.qpos()[2] - 0.1) < 0.001, '${m.qpos()}'
		assert math.abs(m.time() - 1.0) < 1e-9
	}
}

// load returns MuJoCo's message for text that is no model, and switches off the compiler's
// threads and autoreset whatever the text says.
fn test_load() {
	$if mujoco ? {
		cases := {
			'<mujoco><nonsense/></mujoco>':                                                                 'mujoco: cannot parse the model: '
			'<mujoco><worldbody/><actuator><velocity joint="missing"/></actuator></mujoco>':                'mujoco: cannot compile the model: '
			'<mujoco><worldbody><body><joint type="slide"/><geom size="0.1"/></body></worldbody></mujoco>': ''
		}
		for xml, want in cases {
			got := if _ := load(xml) { '' } else { err.msg() }
			assert got.starts_with(want) && (got == '') == (want == ''), '${xml}: ${got}'
			assert !got.contains('\n'), got
		}
	}
}

fn test_load_switches_off_autoreset() {
	$if mujoco ? {
		m := load(base.replace('<option timestep="0.002"/>',
			'<compiler usethread="true"/><option timestep="0.002"><flag autoreset="enable"/></option>'))!
		assert m.m.opt.disableflags & C.mjDSBL_AUTORESET != 0
	}
}

// The base speeds up to its control within the actuators' lag, stops with its rim on the pillar's
// and touches it, while the pillar alone tells the touch apart from the human.
fn test_the_base_drives_into_the_pillar_and_stops_there() {
	$if mujoco ? {
		mut m := load(base)!
		m.set_ctrl(0, 1.0)
		for _ in 0 .. 500 {
			m.step()
		}
		assert math.abs(m.qvel()[0] - 1.0) < 0.001, '${m.qvel()}'
		assert !m.touching(m.geom('base'))
		for _ in 0 .. 2000 {
			m.step()
		}
		x := -3.0 + m.qpos()[0]
		assert math.abs(x - -1.05) < 0.005, '${x}'
		assert math.abs(m.qvel()[0]) < 0.001
		assert m.touching(m.geom('base'))
		assert m.touching(m.geom('pillar'))
		assert m.geom('nothing') == -1
	}
}

// The slides keep the world's axes whatever the hinge's angle, so a base turned to face north
// still moves east on the x slide.
fn test_the_slides_keep_the_worlds_axes() {
	$if mujoco ? {
		mut m := load(base)!
		m.set_ctrl(2, 2.0)
		for _ in 0 .. 400 {
			m.step()
		}
		m.set_ctrl(2, 0.0)
		for _ in 0 .. 200 {
			m.step()
		}
		assert m.qpos()[2] > math.pi / 4.0, '${m.qpos()}'
		before := m.qpos()
		m.set_ctrl(0, 0.5)
		for _ in 0 .. 500 {
			m.step()
		}
		after := m.qpos()
		assert after[0] - before[0] > 0.2
		assert math.abs(after[1] - before[1]) < 1e-9
	}
}

// A mocap human who walks through the base pushes it aside, and then walks through the pillar
// without a contact, since MuJoCo gives a mocap body none with a static geom.
fn test_a_mocap_human_pushes_the_base_and_passes_the_pillar() {
	$if mujoco ? {
		mut m := load(base)!
		for i in 0 .. 3000 {
			y := 3.0 - 6.0 * f64(i) / 3000.0
			m.set_mocap(0, -2.85, y)
			m.step()
		}
		moved := m.qpos()
		assert math.abs(moved[0]) > 0.2, '${moved}'
		for i in 0 .. 1000 {
			m.set_mocap(0, -0.5 + f64(i) / 1000.0, 0.0)
			m.step()
			assert !m.touching(m.geom('pillar')), '${i}'
		}
	}
}

// set_ctrl and set_mocap ignore an index the model has nothing for, rather than write past it.
fn test_setters_ignore_an_index_out_of_range() {
	$if mujoco ? {
		mut m := load(base)!
		m.set_ctrl(3, 1.0)
		m.set_ctrl(-1, 1.0)
		m.set_mocap(1, 1.0, 1.0)
		for _ in 0 .. 10 {
			m.step()
		}
		assert m.qvel() == [0.0, 0.0, 0.0]
	}
}

// A step that leaves the state unstable ends the process with one line, before step returns.
fn test_an_unstable_step_ends_the_process() {
	$if mujoco ? {
		res := os.execute('MUJOCO_TEST_CHILD=unstable ${os.quoted_path(os.executable())}')
		assert res.exit_code == 1, res.output

		// v test -stats has the copy print which file it tests first.
		last := res.output.trim_space().split_into_lines().last()
		assert last == 'field: mujoco: Nan, Inf or huge value in QVEL at DOF 0. The simulation is unstable. Time = 0.0020 s.'
		assert res.output.count('field: mujoco:') == 1, res.output
		assert !os.exists('MUJOCO_LOG.TXT')
	}
}
