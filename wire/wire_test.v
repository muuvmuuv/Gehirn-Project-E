module wire

import rand
import time
import lcl
import zenoh

// link is the key both test tiers share; other is a key nobody shares with them.
const link = []u8{len: 32, init: u8(index)}
const other = []u8{len: 32, init: u8(255 - index)}

// grace is a test umbilical grace, in milliseconds.
const grace = i64(45000)

// patience bounds how long a test waits for a value to cross the link.
const patience = 3 * time.second

fn sample(f Frame) zenoh.Sample {
	return zenoh.Sample{
		key:        f.key
		payload:    f.payload
		attachment: f.mac
	}
}

// forged is a sample on stream whose HMAC is right for payload, as if made by a holder of link.
fn forged(stream string, payload string) zenoh.Sample {
	k := key('eva01', stream)
	return zenoh.Sample{
		key:        k
		payload:    payload.bytes()
		attachment: mac(link, k, payload.bytes())
	}
}

struct GoalCase {
	name   string
	sample zenoh.Sample
	want   string // the error, or empty when the goal opens
}

fn test_goal() {
	now := lcl.now_ms()
	g := lcl.Intent{
		verb:   'goto'
		target: [1.0, 2.0]
		why:    'beacon'
		origin: 'llm'
	}
	mut s := new_sealer(link, 'eva01')!
	mut stranger := new_sealer(other, 'eva01')!
	mut elsewhere := new_sealer(link, 'eva02')!
	first := sample(s.goal(g, now - 100))
	mut tampered := sample(s.goal(g, now - 100))
	tampered = zenoh.Sample{
		...tampered
		payload: tampered.payload.map(if it == u8(`1`) { u8(`9`) } else { it })
	}
	cases := [
		GoalCase{'a goal sealed under the link', first, ''},
		GoalCase{'the same goal again', first, 'wire: goal repeats or precedes the last one accepted'},
		GoalCase{'a goal sealed under another key', sample(stranger.goal(g, now - 100)), 'wire: goal fails its mac'},
		GoalCase{'a goal sealed for another unit', sample(elsewhere.goal(g, now - 100)), 'wire: goal fails its mac'},
		GoalCase{'a pulse presented as a goal', zenoh.Sample{
			...sample(s.pulse(now - 100))
			key: key('eva01', 'goal')
		}, 'wire: goal fails its mac'},
		GoalCase{'a goal with its payload changed', tampered, 'wire: goal fails its mac'},
		GoalCase{'a goal without its mac', zenoh.Sample{
			...sample(s.goal(g, now - 100))
			attachment: []u8{}
		}, 'wire: goal fails its mac'},
		GoalCase{'a goal over 64 KiB', zenoh.Sample{
			...sample(s.goal(g, now - 100))
			payload: []u8{len: 65537, init: `a`}
		}, 'wire: goal over 65536 bytes'},
		GoalCase{'a goal of version 2', forged('goal',
			'{"v":2,"seq":${s.seq + 1},"echo_ms":${now}}'), 'wire: goal of another version than 1'},
		GoalCase{'a goal without a version', forged('goal', '{"seq":${s.seq + 1},"echo_ms":${now}}'), 'wire: goal of another version than 1'},
		GoalCase{'a goal that is no JSON object', forged('goal', '[1]'), 'wire: unreadable goal'},
		GoalCase{'a goal echoing a percept older than the grace', sample(s.goal(g, now - grace - 1)), 'wire: goal echoes a percept outside the grace'},
		GoalCase{'a goal echoing a percept from the future', sample(s.goal(g, now + 1000)), 'wire: goal echoes a percept outside the grace'},
		GoalCase{'a later goal sealed under the link', sample(s.goal(g, now - grace)), ''},
	]
	mut o := new_opener(link, 'eva01')!
	for c in cases {
		got := o.goal(c.sample, now, grace) or {
			assert err.msg() == c.want, c.name
			continue
		}
		assert c.want == '', c.name
		assert got == g, c.name
	}
}

fn test_pulse() {
	now := lcl.now_ms()
	mut s := new_sealer(link, 'eva01')!
	mut o := new_opener(link, 'eva01')!
	o.pulse(sample(s.pulse(now)), now, grace)!
	stale := s.pulse(now - grace - 1)
	o.pulse(sample(stale), now, grace) or {
		assert err.msg() == 'wire: pulse echoes a percept outside the grace'
		return
	}
	assert false, 'a stale pulse opened'
}

fn test_context_and_outcome_open_to_what_was_sealed() {
	mut s := new_sealer(link, 'eva01')!
	mut o := new_opener(link, 'eva01')!
	c := lcl.Context{
		mission: 'stays on the field'
		percept: lcl.Percept{
			t_ms:    lcl.now_ms()
			pose:    [-3.5, -2.5]
			vel:     [0.1, 0.0]
			scene:   [lcl.Entity{'h1', 'human', [2.6, 1.2], 0.3}]
			payload: true
		}
		goal:    lcl.Intent{
			verb:   'goto'
			target: [3.0, 2.0]
		}
		seat:    'pilot'
		sync:    0.42
		memory:  ['stays on HQ']
	}
	got := o.context(sample(s.context(c)))!
	assert got == lcl.Context{
		...c
		mission: ''
		memory:  []
	}
	out := lcl.Outcome{
		t_ms: 7
		kind: 'reached'
		good: true
	}
	assert o.outcome(sample(s.outcome(out)))! == out
}

fn test_new_sealer() {
	for n in [0, 16, 31, 33] {
		new_sealer([]u8{len: n}, 'eva01') or {
			assert err.msg() == 'wire: a link key is 32 bytes, not ${n}'
			new_opener([]u8{len: n}, 'eva01') or { continue }
			assert false, 'an opener took a key of ${n} bytes'
		}
		assert false, 'a sealer took a key of ${n} bytes'
	}
}

fn test_a_sealer_numbers_from_its_start_time_upwards() {
	before := time.now().unix_micro()
	mut s := new_sealer(link, 'eva01')!
	a := s.seq
	s.pulse(0)
	assert a >= before
	assert s.seq == a + 1
}

// recv waits for a value on ch until patience runs out.
fn recv[T](ch chan T) ?T {
	deadline := time.now().add(patience)
	for time.now() < deadline {
		mut v := T{}
		if ch.try_pop(mut v) == .success {
			return v
		}
		time.sleep(5 * time.millisecond)
	}
	return none
}

fn test_the_pumps_carry_lcl_between_the_tiers() {
	at := 'tcp/127.0.0.1:${rand.int_in_range(20000, 60000)!}'
	hq_session := zenoh.open(zenoh.Config{ listen: [at] })!
	field_session := zenoh.open(zenoh.Config{ connect: [at] })!
	mut h := new_hq(hq_ports(hq_session, 'eva01')!, link, 'eva01')!
	mut f := new_field(field_ports(field_session, 'eva01')!, link, 'eva01', grace)!

	inbox := chan lcl.Context{cap: 1}
	hq_outcomes := chan lcl.Outcome{cap: 32}
	outbox := chan lcl.HqMsg{cap: 8}
	notes := chan string{cap: 16}
	to_hq := chan lcl.Context{cap: 1}
	field_outcomes := chan lcl.Outcome{cap: 32}
	from_hq := chan lcl.HqMsg{cap: 8}
	spawn h.run(inbox, hq_outcomes, outbox, notes)
	spawn f.run(to_hq, field_outcomes, from_hq)

	// The field publishes before HQ's subscription reaches it, so it keeps sending snapshots.
	snapshot := lcl.Context{
		percept: lcl.Percept{
			t_ms: lcl.now_ms()
			pose: [0.0, 0.0]
		}
		seat:    'empty'
	}
	mut got := ?lcl.Context(none)
	deadline := time.now().add(patience)
	for time.now() < deadline && got == none {
		_ = to_hq.try_push(snapshot)
		time.sleep(20 * time.millisecond)
		mut c := lcl.Context{}
		if inbox.try_pop(mut c) == .success {
			got = c
		}
	}
	assert got or { panic('no snapshot reached HQ') } == snapshot

	field_outcomes <- lcl.Outcome{
		kind: 'contact'
	}
	assert recv(hq_outcomes) or { panic('no outcome reached HQ') }.kind == 'contact'

	goal := lcl.Intent{
		verb:   'goto'
		target: [3.0, 2.0]
	}
	outbox <- lcl.HqMsg{
		goal:     goal
		approved: true
		alive:    true
		note:     'hq: goto(3.00, 2.00)'
	}
	assert recv(notes) or { panic('no note') } == 'hq: goto(3.00, 2.00)'
	mut approved := false
	mut alive := false
	for !(approved && alive) {
		m := recv(from_hq) or { panic('approved ${approved}, alive ${alive}') }
		approved = approved || (m.approved && m.goal == goal)
		alive = alive || m.alive
	}

	// A goal from a session without the link key never reaches the field loop.
	intruder := field_session.publisher(key('eva01', 'goal'), zenoh.Qos{})!
	mut forger := new_sealer(other, 'eva01')!
	fake := forger.goal(goal, lcl.now_ms())
	intruder.put(fake.payload, fake.mac)!
	m := recv(from_hq) or { panic('no note on the forged goal') }
	assert m.note == 'wire: goal fails its mac'
	assert !m.approved
}
