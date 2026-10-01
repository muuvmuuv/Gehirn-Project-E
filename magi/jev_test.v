module magi

import math
import net
import time
import x.json2
import jev
import lcl

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
		approve, why := jev_judge(r, c.verb) or {
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
}
