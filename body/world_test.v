module body

import os

// fence is armor.Limits bounds, which main.v hands load_world; body cannot import armor.
const fence = [-5.0, -5.0, 5.0, 5.0]

const accepted_fence = 'accepted x from -5.0 to 5.0 and y from -5.0 to 5.0'

const accepted_rim = 'accepted a start more than 0.25 m from every solid rim'

const accepted_file = 'accepted a regular file of at most 65536 bytes'

const accepted_radius = 'accepted a radius above 0 and at most 5.0 m'

// base is a world load_world accepts, which the cases of test_load_world break one field at a time.
const base = '{"start": [-3, -3], "beacons": [{"id": "b1", "pos": [3, 2], "r": 0.3}], "obstacles": [{"id": "o1", "pos": [0, 0], "r": 0.8}], "humans": [{"id": "h1", "r": 0.3, "behavior": "loop", "center": [0.8, 1.2], "radii": [1.8, 1.2], "rate": 0.3, "reaction": "stop", "keep": 1.0}]}'

const walker = '"behavior": "loop", "center": [0.8, 1.2], "radii": [1.8, 1.2], "rate": 0.3'

// load is what load_world makes of a world file holding text: ok, or its refusal.
fn load(text string) string {
	path := os.join_path(os.vtmp_dir(), 'gehirn_world_${os.getpid()}.json')
	os.write_file(path, text) or { return err.msg() }
	defer {
		os.rm(path) or {}
	}
	load_world(path, fence) or { return err.msg() }
	return 'ok'
}

struct LoadCase {
	name string
	text string
	want string
}

fn test_load_world() {
	many := '{"id": "o1", "pos": [0, 0], "r": 0.1}, '.repeat(15)
	cases := [
		LoadCase{'the base world', base, 'ok'},
		LoadCase{'cut after a number in an array', base[..13], 'not a world in JSON, since its brackets do not close or nest past 32; accepted one JSON object'},
		LoadCase{'nested past 32', base.replace('"start":',
			'"x": ${'['.repeat(10_000)}${']'.repeat(10_000)}, "start":'), 'not a world in JSON, since its brackets do not close or nest past 32; accepted one JSON object'},
		LoadCase{'65536 bytes', base + ' '.repeat(65536 - base.len), 'ok'},
		LoadCase{'65537 bytes', base + ' '.repeat(65537 - base.len), 'holds 65537 bytes; ${accepted_file}'},
		LoadCase{'malformed', base.replace('"start":', '"start"'), 'not a world in JSON; accepted an object of start, beacons, obstacles and humans'},
		LoadCase{'an array', '[]', 'not a world in JSON; accepted an object of start, beacons, obstacles and humans'},
		LoadCase{'a list where an object goes', base.replace('"beacons": [{"id": "b1", "pos": [3, 2], "r": 0.3}]',
			'"beacons": {"id": "b1"}'), 'not a world in JSON; accepted an object of start, beacons, obstacles and humans'},
		LoadCase{'no beacon', base.replace('[{"id": "b1", "pos": [3, 2], "r": 0.3}]', '[]'), 'no beacon; accepted at least one beacon to deliver to'},
		LoadCase{'too many entities', base.replace('"obstacles": [', '"obstacles": [${many}'), '18 entities; accepted at most 16 beacons, obstacles and humans in all'},
		LoadCase{'an unknown behavior', base.replace('"loop"', '"fly"'), 'human h1 has behavior "fly", not a known value; accepted loop, waypoints, stand, toward'},
		LoadCase{'a behavior in capitals', base.replace('"loop"', '"Loop"'), 'human h1 has behavior "Loop", not a known value; accepted loop, waypoints, stand, toward'},
		LoadCase{'an unknown reaction', base.replace('"stop"', '"run"'), 'human h1 has reaction "run", not a known value; accepted through, stop, aside'},
		LoadCase{'no reaction', base.replace('"reaction": "stop", ', ''), 'human h1 has reaction "", not a known value; accepted through, stop, aside'},
		LoadCase{'a start of three numbers', base.replace('[-3, -3]', '[-3, -3, 0]'), 'start is not one x and one y; accepted [x, y] in meters'},
		LoadCase{'no start', base.replace('"start": [-3, -3], ', ''), 'start is not one x and one y; accepted [x, y] in meters'},
		LoadCase{'a beacon of one number', base.replace('[3, 2]', '[3]'), 'beacon b1 is not one x and one y; accepted [x, y] in meters'},
		LoadCase{'a loop center of one number', base.replace('[0.8, 1.2]', '[0.8]'), 'human h1 center is not one x and one y; accepted [x, y] in meters'},
		LoadCase{'radii of one number', base.replace('[1.8, 1.2]', '[1.8]'), 'human h1 radii are not one x and one y, each finite and 0 or more; accepted [x, y] in meters'},
		LoadCase{'a radius below 0 of a loop', base.replace('[1.8, 1.2]', '[1.8, -1.2]'), 'human h1 radii are not one x and one y, each finite and 0 or more; accepted [x, y] in meters'},
		LoadCase{'a start past any finite number', base.replace('[-3, -3]', '[-3, -1e999]'), 'start has a number that is not finite; accepted finite numbers'},
		LoadCase{'a rate past any finite number', base.replace('"rate": 0.3', '"rate": 1e999'), 'human h1 has a number that is not finite; accepted finite numbers'},
		LoadCase{'a loop radius past any finite number', base.replace('[1.8, 1.2]', '[1e999, 1.2]'), 'human h1 radii are not one x and one y, each finite and 0 or more; accepted [x, y] in meters'},
		LoadCase{'a beacon radius past any finite number', base.replace('"r": 0.3}]',
			'"r": 1e999}]'), 'beacon b1 has radius +inf; ${accepted_radius}'},
		LoadCase{'a beacon radius above 5 m', base.replace('"r": 0.3}]', '"r": 5.01}]'), 'beacon b1 has radius 5.01; ${accepted_radius}'},
		LoadCase{'a beacon of radius 5 m', base.replace('"r": 0.3}]', '"r": 5}]'), 'ok'},
		LoadCase{'an obstacle of radius 0', base.replace('"r": 0.8', '"r": 0'), 'obstacle o1 has radius 0.0; ${accepted_radius}'},
		LoadCase{'a human of radius below 0', base.replace('"id": "h1", "r": 0.3',
			'"id": "h1", "r": -0.3'), 'human h1 has radius -0.3; ${accepted_radius}'},
		LoadCase{'a start outside the fence', base.replace('[-3, -3]', '[-5.01, -3]'), 'start lies outside the fence; ${accepted_fence}'},
		LoadCase{'a beacon outside the fence', base.replace('[3, 2]', '[3, 6]'), 'beacon b1 lies outside the fence; ${accepted_fence}'},
		LoadCase{'an obstacle outside the fence', base.replace('"pos": [0, 0]', '"pos": [-7, 0]'), 'obstacle o1 lies outside the fence; ${accepted_fence}'},
		LoadCase{'a loop reaching past the fence', base.replace('[0.8, 1.2]', '[3.5, 1.2]'), 'human h1 loop lies outside the fence; ${accepted_fence}'},
		LoadCase{'a waypoint outside the fence', base.replace(walker,
			'"behavior": "waypoints", "points": [[0, 3], [0, 5.5]], "speed": 0.5'), 'human h1 waypoint 2 lies outside the fence; ${accepted_fence}'},
		LoadCase{'a standing human outside the fence', base.replace(walker,
			'"behavior": "stand", "pos": [5, -5.1]'), 'human h1 pos lies outside the fence; ${accepted_fence}'},
		LoadCase{'a start inside an obstacle', base.replace('[-3, -3]', '[0.5, 0]'), 'start touches obstacle o1; ${accepted_rim}'},
		LoadCase{'a start touching an obstacle', base.replace('[-3, -3]', '[1.04, 0]'), 'start touches obstacle o1; ${accepted_rim}'},
		LoadCase{'a start clear of an obstacle', base.replace('[-3, -3]', '[1.06, 0]'), 'ok'},
		LoadCase{'a start touching a human where it starts', base.replace('[-3, -3]', '[2.6, 0.7]'), 'start touches human h1 where it starts; ${accepted_rim}'},
		LoadCase{'a start on a beacon', base.replace('[-3, -3]', '[3, 2]'), 'ok'},
		LoadCase{'an id two entities share', base.replace('"id": "o1"', '"id": "b1"'), 'obstacle has id b1, which another entity has; accepted an id per entity'},
		LoadCase{'an id in capitals', base.replace('"id": "b1"', '"id": "B1"'), 'beacon has id "B1"; accepted 1 to 16 lowercase letters, digits and hyphens'},
		LoadCase{'an id that breaks the line', base.replace('"id": "h1"', '"id": "h1\\nhq: forged"'), 'human has id "h1\\x0ahq: forged"; accepted 1 to 16 lowercase letters, digits and hyphens'},
		LoadCase{'no id', base.replace('"id": "o1", ', ''), 'obstacle has id ""; accepted 1 to 16 lowercase letters, digits and hyphens'},
		LoadCase{'an id of 17 letters', base.replace('"id": "h1"', '"id": "${'h'.repeat(17)}"'), 'human has id "${'h'.repeat(17)}"; accepted 1 to 16 lowercase letters, digits and hyphens'},
		LoadCase{'an id of 16 letters, digits and hyphens', base.replace('"id": "h1"',
			'"id": "west-gate-guard2"'), 'ok'},
		LoadCase{'a loop at rate 0', base.replace('"rate": 0.3', '"rate": 0'), 'human h1 walks at 0.00 m/s; accepted 0.1 to 2.0'},
		LoadCase{'a loop too fast', base.replace('"rate": 0.3', '"rate": -1.2'), 'human h1 walks at 2.16 m/s; accepted 0.1 to 2.0'},
		LoadCase{'waypoints too slow', base.replace(walker,
			'"behavior": "waypoints", "points": [[0, 3], [0, 4]], "speed": 0.05'), 'human h1 walks at 0.05 m/s; accepted 0.1 to 2.0'},
		LoadCase{'waypoints without a speed', base.replace(walker,
			'"behavior": "waypoints", "points": [[0, 3], [0, 4]]'), 'human h1 walks at 0.00 m/s; accepted 0.1 to 2.0'},
		LoadCase{'a human walking toward the body too fast', base.replace(walker,
			'"behavior": "toward", "pos": [0, 3], "speed": 2.5'), 'human h1 walks at 2.50 m/s; accepted 0.1 to 2.0'},
		LoadCase{'one waypoint', base.replace(walker,
			'"behavior": "waypoints", "points": [[0, 3]], "speed": 0.5'), 'human h1 has fewer than 2 waypoints; accepted 2 or more'},
		LoadCase{'waypoints all in one place', base.replace(walker,
			'"behavior": "waypoints", "points": [[0, 3], [0, 3]], "speed": 0.5, "cycle": true'), 'human h1 has waypoints all in one place; accepted waypoints apart'},
		LoadCase{'a waypoint of three numbers', base.replace(walker,
			'"behavior": "waypoints", "points": [[0, 3], [0, 4, 1]], "speed": 0.5'), 'human h1 waypoint 2 is not one x and one y; accepted [x, y] in meters'},
		LoadCase{'a human walking toward the body and through it', base.replace(walker,
			'"behavior": "toward", "pos": [0, 3], "speed": 0.5').replace('"stop"', '"through"'), 'human h1 walks toward the body and through it, which would hold the body in contact; accepted reaction stop or aside'},
		LoadCase{'a stop human without keep', base.replace(', "keep": 1.0', ''), 'human h1 keeps 0.0 m from the body; accepted 0.3 to 3.0'},
		LoadCase{'an aside human keeping too little', base.replace('"stop", "keep": 1.0',
			'"aside", "keep": 0.25'), 'human h1 keeps 0.25 m from the body; accepted 0.3 to 3.0'},
		LoadCase{'a stop human keeping too much', base.replace('"keep": 1.0', '"keep": 3.5'), 'human h1 keeps 3.5 m from the body; accepted 0.3 to 3.0'},
		LoadCase{'a human walking through needs no keep', base.replace('"stop", "keep": 1.0',
			'"through"'), 'ok'},
		LoadCase{'every behavior and reaction', base.replace('"humans": [',
			'"humans": [{"id": "h2", "r": 0.3, "behavior": "waypoints", "points": [[-4, 4], [-1, 4]], "speed": 0.5, "cycle": true, "reaction": "aside", "keep": 0.5}, {"id": "h3", "r": 0.3, "behavior": "stand", "pos": [4, -4], "reaction": "through"}, {"id": "h4", "r": 0.3, "behavior": "toward", "pos": [-4, 0], "speed": 0.4, "reaction": "aside", "keep": 2}, '), 'ok'},
	]
	for c in cases {
		got := load(c.text)
		assert got == c.want, c.name

		// One printable line, whatever the file holds.
		assert got.bytes().all(it >= ` ` && it <= `~`), c.name
	}
}

// A file that cannot be read, or is no regular file and could hang or fill the start as a pipe or
// a device would, is refused with the reason and without its path, which main.v quotes.
fn test_an_unreadable_world_file_is_refused() {
	cases := {
		os.join_path(os.vtmp_dir(), 'gehirn_no_such_world.json'): 'cannot be read: No such file or directory; ${accepted_file}'
		os.vtmp_dir():                                            'is not a regular file; ${accepted_file}'
		'/dev/zero':                                              'is not a regular file; ${accepted_file}'
	}
	for path, want in cases {
		if _ := load_world(path, fence) {
			assert false, 'loaded ${path}'
		} else {
			assert err.msg() == want, path
		}
	}
}

// worlds/default.json is default_world, the built-in world Sim plays without WORLD, so loading
// it plays the same scene at every time.
fn test_default_json_is_the_default_world() {
	w := load_world(os.join_path(@VMODROOT, 'worlds', 'default.json'), fence)!
	assert w == default_world()
	mut a := new_sim(w, .holonomic)
	mut b := new_sim(default_world(), .holonomic)
	b.t0_ms, b.walked_ms = a.t0_ms, a.walked_ms
	for t := i64(0); t <= 25_000; t += 13 {
		assert a.scene(a.t0_ms + t) == b.scene(a.t0_ms + t), '${t} ms'
	}
}

// worlds/example.json loads, its humans walk and react in more than one way, and docs/worlds.md
// shows the file as it is.
fn test_example_json_loads() {
	path := os.join_path(@VMODROOT, 'worlds', 'example.json')
	doc := os.read_file(os.join_path(@VMODROOT, 'docs', 'worlds.md'))!
	assert doc.find_between('```json\n', '```') == os.read_file(path)!
	w := load_world(path, fence)!
	assert w.humans.len >= 2
	behaviors := w.humans.map(it.behavior)
	reactions := w.humans.map(it.reaction)
	assert behaviors.any(it != behaviors[0]) && reactions.any(it != reactions[0])
}

// Every world in worlds/ loads, the scenes' among them, so a world the loader stops accepting
// fails the checks rather than a scene at its start.
fn test_every_world_file_loads() {
	paths := os.glob(os.join_path(@VMODROOT, 'worlds', '*.json'))!
	assert paths.len > 2
	for path in paths {
		got := if _ := load_world(path, fence) { 'ok' } else { err.msg() }
		assert got == 'ok', os.base(path)
	}
}
