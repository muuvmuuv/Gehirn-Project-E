module wire

import net
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

// loopback is a TCP locator on 127.0.0.1 at a port the OS has just found free, for a session to
// listen on, as zenoh/zenoh_test.v `loopback` gives, which says why.
fn loopback() !string {
	mut l := net.listen_tcp(.ip, '127.0.0.1:0')!
	port := l.addr()!.port()!
	l.close()!
	return 'tcp/127.0.0.1:${port}'
}

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
			scene:   [
				lcl.Entity{
					id:   'h1'
					kind: 'human'
					pos:  [2.6, 1.2]
					r:    0.3
				},
			]
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

// A context whose pose, or the position of a scene entity or a patch of ground, is not one x and one
// y is dropped as unreadable, though sealed under the link, since HQ's readers index both, and the
// next sound one opens.
fn test_a_context_of_another_shape_is_dropped() {
	mut s := new_sealer(link, 'eva01')!
	mut o := new_opener(link, 'eva01')!
	entity := lcl.Entity{
		id:   'o1'
		kind: 'obstacle'
		pos:  [1.0, 1.0]
		r:    0.5
	}
	patch := lcl.Entity{
		id:     'lake'
		kind:   'ground'
		pos:    [1.0, 1.0]
		r:      1.4
		factor: 0.5
	}
	sound := lcl.Percept{
		pose:   [0.0, 0.0]
		scene:  [entity]
		ground: [patch]
	}
	cases := {
		'a pose of no number':              lcl.Percept{
			...sound
			pose: []
		}
		'a pose of three numbers':          lcl.Percept{
			...sound
			pose: [0.0, 0.0, 0.0]
		}
		'a scene entity at one number':     lcl.Percept{
			...sound
			scene: [lcl.Entity{
				...entity
				pos: [1.0]
			}]
		}
		'a patch of ground at no position': lcl.Percept{
			...sound
			ground: [lcl.Entity{
				...patch
				pos: []
			}]
		}
	}
	for name, p in cases {
		if got := o.context(sample(s.context(lcl.Context{ percept: p }))) {
			assert false, '${name} opened as ${got.percept}'
		} else {
			assert err.msg() == 'wire: unreadable context', name
		}
	}
	assert o.context(sample(s.context(lcl.Context{ percept: sound })))!.percept == sound
}

// A holonomic body's percept has no heading, so a context and a view seal to the bytes they sealed
// to before the percept carried one; a differential body's heading travels to HQ and the bridge.
fn test_a_heading_travels_only_from_a_differential_body() {
	mut s := new_sealer(link, 'eva01')!
	s.seq = 41
	c := lcl.Context{
		percept: lcl.Percept{
			t_ms:    1700000000000
			pose:    [-3.5, -2.5]
			vel:     [0.1, 0.0]
			scene:   [
				lcl.Entity{
					id:   'h1'
					kind: 'human'
					pos:  [2.6, 1.2]
					r:    0.3
				},
			]
			payload: true
		}
		goal:    lcl.Intent{
			verb:   'goto'
			target: [3.0, 2.0]
		}
		seat:    'pilot'
		sync:    0.42
	}
	percept := '{"t_ms":1700000000000,"pose":[-3.5,-2.5],"vel":[0.1,0],"scene":[{"id":"h1","kind":"human","pos":[2.6,1.2],"r":0.3}],"payload":true,"contact":false}'
	goal := '{"verb":"goto","target":[3,2],"why":"","origin":""}'
	assert s.context(c).payload.bytestr() == '{"v":1,"seq":42,"percept":${percept},"goal":${goal},"seat":"pilot","sync":0.42}'
	assert s.view(lcl.FieldView{ percept: c.percept, goal: c.goal, seat: 'pilot' }).payload.bytestr() == '{"v":1,"seq":43,"view":{"percept":${percept},"goal":${goal},"seat":"pilot","benched":false,"sync":0,"authority":0,"umbilical":"","internal_ms":0,"silent_ms":0,"grace_ms":0,"awaiting":false,"outcomes":[]}}'

	turned := lcl.Context{
		...c
		percept: lcl.Percept{
			...c.percept
			heading: -0.5
		}
	}
	mut o := new_opener(link, 'eva01')!
	f := s.context(turned)
	assert f.payload.bytestr().contains('"contact":false,"heading":-0.5}')
	assert o.context(sample(f))!.percept == turned.percept
	assert o.view(sample(s.view(lcl.FieldView{ percept: turned.percept })))!.percept == turned.percept
}

// A standing human has no velocity, so the percept above seals to the bytes it sealed to before
// the scene carried one; a walking human's velocity travels to HQ and the bridge.
fn test_a_walking_humans_velocity_travels_to_hq_and_the_bridge() {
	mut s := new_sealer(link, 'eva01')!
	mut o := new_opener(link, 'eva01')!
	p := lcl.Percept{
		t_ms:  lcl.now_ms()
		pose:  [-3.5, -2.5]
		scene: [
			lcl.Entity{
				id:   'h1'
				kind: 'human'
				pos:  [2.6, 1.2]
				r:    0.3
				vel:  [-0.5, 0.36]
			},
		]
	}
	f := s.context(lcl.Context{ percept: p })
	assert f.payload.bytestr().contains('"r":0.3,"vel":[-0.5,0.36]}')
	assert o.context(sample(f))!.percept == p
	assert o.view(sample(s.view(lcl.FieldView{ percept: p })))!.percept == p
}

// A percept without ground seals to the bytes it sealed to before ground existed; a patch of ground
// travels to HQ and the bridge with its factor, and a landing zone with its time to land.
fn test_ground_travels_to_hq_and_the_bridge() {
	mut s := new_sealer(link, 'eva01')!
	mut o := new_opener(link, 'eva01')!
	plain := lcl.Percept{
		t_ms:  lcl.now_ms()
		pose:  [-3.5, -2.5]
		scene: [
			lcl.Entity{
				id:   'b1'
				kind: 'beacon'
				pos:  [3.0, 2.0]
				r:    0.3
			},
		]
	}
	assert s.context(lcl.Context{ percept: plain }).payload.bytestr().contains('"r":0.3}],"payload":false,')
	p := lcl.Percept{
		...plain
		ground: [
			lcl.Entity{
				id:     'lake'
				kind:   'ground'
				pos:    [1.8, 0.9]
				r:      1.4
				factor: 0.5
			},
		]
	}
	f := s.context(lcl.Context{ percept: p })
	assert f.payload.bytestr().contains('"ground":[{"id":"lake","kind":"ground","pos":[1.8,0.9],"r":1.4,"factor":0.5}],"payload"')
	assert o.context(sample(f))!.percept == p
	assert o.view(sample(s.view(lcl.FieldView{ percept: p })))!.percept == p
	q := lcl.Percept{
		...plain
		scene: [
			lcl.Entity{
				id:       'rock'
				kind:     'impact'
				pos:      [-2.2, -0.6]
				r:        0.5
				lands_in: 12.5
			},
		]
	}
	g := s.context(lcl.Context{ percept: q })
	assert g.payload.bytestr().contains('"r":0.5,"lands_in":12.5}],"payload"')
	assert o.context(sample(g))!.percept == q
	assert o.view(sample(s.view(lcl.FieldView{ percept: q })))!.percept == q
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
	at := loopback()!
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

fn test_the_watch_streams_reach_the_bridge_and_nothing_else_opens_them() {
	watch_key := []u8{len: 32, init: u8(index * 3)}
	at := loopback()!
	bridge_session := zenoh.open(zenoh.Config{ listen: [at] })!
	ports := bridge_ports(bridge_session, 'eva01')!
	mut f := field_watch(zenoh.open(zenoh.Config{ connect: [at] })!, 'eva01', watch_key)!
	mut h := hq_watch(zenoh.open(zenoh.Config{ connect: [at] })!, 'eva01', watch_key)!
	views := chan lcl.FieldView{cap: 1}
	events := chan lcl.HqEvent{cap: 16}
	spawn f.run_field(views)
	spawn h.run_hq(events)
	mut o := new_opener(watch_key, 'eva01')!

	// Puts before the bridge's subscriptions reach a tier go nowhere, so keep putting.
	view := lcl.FieldView{
		seat:        'empty'
		benched:     true
		umbilical:   'internal'
		internal_ms: 299000
		silent_ms:   46000
		grace_ms:    45000
		outcomes:    [lcl.Outcome{
			kind: 'armor refused release'
		}]
	}
	event := lcl.HqEvent{
		stage:    'ballot'
		proposal: lcl.Intent{
			verb: 'release'
		}
		votes:    [
			lcl.Vote{
				unit: 'BALTHASAR-2'
				vote: 'reject'
				why:  'harm: drops_near_person 0.90 >= 0.35'
			},
		]
	}
	mut got_view := ?lcl.FieldView(none)
	mut got_event := ?lcl.HqEvent(none)
	deadline := time.now().add(patience)
	for time.now() < deadline && (got_view == none || got_event == none) {
		_ = views.try_push(view)
		_ = events.try_push(event)
		time.sleep(20 * time.millisecond)
		if s := ports.field.try_recv() {
			got_view = o.view(s)!
		}
		if s := ports.hq.try_recv() {
			got_event = o.event(s)!
		}
	}
	assert got_view or { panic('no view reached the bridge') } == view
	assert got_event or { panic('no event reached the bridge') } == event

	// A view sealed under the link key is no view, and a view is no context.
	mut control := new_sealer(link, 'eva01')!
	if _ := o.view(sample(control.view(view))) {
		assert false, 'a view sealed under the link key opened'
	} else {
		assert err.msg() == 'wire: watch/field fails its mac'
	}
	mut watch := new_sealer(watch_key, 'eva01')!
	mut hq_side := new_opener(link, 'eva01')!
	hq_side.context(zenoh.Sample{
		...sample(watch.view(view))
		key: key('eva01', 'context')
	}) or {
		assert err.msg() == 'wire: context fails its mac'
		return
	}
	assert false, 'a view opened as a context'
}
