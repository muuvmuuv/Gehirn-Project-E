module plug

import x.json2
import math
import os
import lcl

// Dummy is the dummy plug, which main.v's field loop seats while no pilot is present. It imitates
// the pilot's driving style: it never learns where the pilot wanted to go, only how they drive
// toward a goal MAGI approved. Every command it learns or gives is in the goal's own frame, as
// speed along the way to the goal and across it, so an imitation that overshoots turns back
// instead of holding a heading it memorized. load_dummy gives it a Policy that
// tools/train_dummy.py trained offline on the scene the pilot saw, or else the pilot's ticks in the
// recorder's log for k nearest neighbor behavior cloning, which sees only the pose.
// ponytail: the nearest neighbor fallback scans every sample on every tick, fine at 20000
// samples; a pilot who needs more trains a policy.
pub struct Dummy {
	k     int = 7
	limit int = 20000 // pilot ticks kept; tools/eval_dummy.py KNN_LIMIT copies it
	min   int = 500   // ticks; scripts/stage.sh sets pilot_s to fly them
mut:
	xs     [][]f64
	ys     [][]f64
	next   int
	policy Policy
}

// load_dummy builds the dummy plug: the policy in the weights file when one exists, else the
// nearest neighbor dummy from every tick a pilot flew in the recorder's log. A weights file that
// load_policy refuses is an error, so main.v refuses to start rather than seat another dummy than
// the one trained.
pub fn load_dummy(recorder string, weights string) !Dummy {
	if os.exists(weights) {
		return Dummy{
			policy: load_policy(weights)!
		}
	}
	mut d := Dummy{}
	lines := os.read_lines(recorder) or { return d }
	for line in lines {
		if !complete(line) {
			continue
		}
		r := json2.decode[Record](line) or { continue }
		if r.seat == 'pilot' {
			d.learn(r.pose, r.target, r.u_seat)
		}
	}
	return d
}

// size is the number of samples on file for the nearest neighbor dummy.
pub fn (d Dummy) size() int {
	return d.xs.len
}

// trained reports whether the dummy flies a trained policy rather than its samples.
pub fn (d Dummy) trained() bool {
	return d.policy.w1.len > 0
}

// ready reports whether the dummy has a policy, or enough of the pilot on file to imitate.
pub fn (d Dummy) ready() bool {
	return d.trained() || d.xs.len >= d.min
}

// learn stores one pilot tick for the nearest neighbor dummy. Ticks without a goal carry no style
// and are skipped.
pub fn (mut d Dummy) learn(pose []f64, target []f64, u []f64) {
	along, across := frame(pose, target) or { return }
	if u.len != 2 {
		return
	}
	x := features(pose, target)
	y := [lcl.dot(u, along), lcl.dot(u, across)]
	if d.xs.len < d.limit {
		d.xs << x
		d.ys << y
		return
	}
	d.xs[d.next] = x
	d.ys[d.next] = y
	d.next = (d.next + 1) % d.limit
}

// act drives toward the goal the way the pilot would, and lets go on arrival.
pub fn (d Dummy) act(p lcl.Percept, target []f64) []f64 {
	idle := []f64{len: p.pose.len}
	along, across := frame(p.pose, target) or { return idle }
	if lcl.dist(p.pose, target) < lcl.arrive {
		return idle
	}
	if d.trained() {
		y := d.policy.act(observe(p, target) or { return idle })
		n := math.hypot(y[0], y[1])
		if n < 1e-6 || y[2] <= 0.0 {
			return idle
		}
		return lcl.add(lcl.scale(along, y[0] * y[2] / n), lcl.scale(across, y[1] * y[2] / n))
	}
	if d.xs.len == 0 {
		return idle
	}
	q := features(p.pose, target)
	mut idx := []int{}
	mut dst := []f64{}
	for i, x in d.xs {
		dd := lcl.dist(q, x)
		if idx.len < d.k {
			idx << i
			dst << dd
			continue
		}
		mut worst := 0
		for j in 1 .. dst.len {
			if dst[j] > dst[worst] {
				worst = j
			}
		}
		if dd < dst[worst] {
			idx[worst] = i
			dst[worst] = dd
		}
	}
	mut y := [0.0, 0.0]
	mut wsum := 0.0
	for j, i in idx {
		w := 1.0 / (dst[j] + 1e-6)
		y[0] += w * d.ys[i][0]
		y[1] += w * d.ys[i][1]
		wsum += w
	}
	return lcl.add(lcl.scale(along, y[0] / wsum), lcl.scale(across, y[1] / wsum))
}

// frame is the unit vector toward the goal and its left normal; none without a goal or at it.
fn frame(pose []f64, target []f64) ?([]f64, []f64) {
	if pose.len != 2 || target.len != 2 {
		return none
	}
	to := lcl.sub(target, pose)
	n := lcl.norm(to)
	if n < 1e-6 {
		return none
	}
	g := lcl.scale(to, 1.0 / n)
	return g, [-g[1], g[0]]
}

// features are what the nearest neighbor dummy compares: how far away the goal is and where the
// body is.
fn features(pose []f64, target []f64) []f64 {
	mut f := [lcl.dist(pose, target)]
	f << pose
	return f
}

// sight is how far past an entity's rim, in meters, the policy sees it. tools/export_dummy.py
// SIGHT copies it.
const sight = 3.0

// inputs is the length of observe's features, the policy's inputs. tools/train_dummy.py INPUTS
// copies it.
const inputs = 9

// observe is what the policy sees of a percept, in the goal's frame: the distance to the goal up
// to sight, then for the nearest solid entity and the nearest human the direction to it, along and
// across, scaled by how close its rim is, that closeness, 1 at the rim and 0 at sight or beyond,
// and the closeness again, positive when it lies left of the way to the goal and negative when
// right. none without a goal frame. tools/export_dummy.py features computes the same. A pilot
// passes an entity on one side or the other, and which flips where it lies dead ahead; from the
// smooth direction alone a tanh layer learns that flip only where the training flights met things
// dead ahead from both sides, so the signed closeness hands it over.
fn observe(p lcl.Percept, target []f64) ?[]f64 {
	along, across := frame(p.pose, target) or { return none }
	mut f := [math.min(lcl.dist(p.pose, target), sight)]
	for human in [false, true] {
		mut near := [0.0, 0.0, 0.0]
		for e in p.scene {
			if e.kind == 'beacon' || (e.kind == 'human') != human || e.pos.len != 2 {
				continue
			}
			rel := lcl.sub(e.pos, p.pose)
			n := lcl.norm(rel)
			w := math.min(1.0, 1.0 - (n - e.r) / sight)
			if w > near[2] && n > 1e-6 {
				near = [w * lcl.dot(rel, along) / n, w * lcl.dot(rel, across) / n, w]
			}
		}
		f << near
		f << if near[1] > 0.0 {
			near[2]
		} else if near[1] < 0.0 {
			-near[2]
		} else {
			0.0
		}
	}
	return f
}

// policy_version is the weights format, and the features of observe, that load_policy accepts.
// tools/train_dummy.py VERSION copies it.
const policy_version = 2

// max_units bounds a policy's tanh units, so no weights file can slow the field loop: at the
// bound one tick costs about 3100 multiplications. tools/train_dummy.py MAX_UNITS copies it.
const max_units = 256

// max_weight bounds the magnitude of every weight and bias load_policy accepts. A finite output
// past about 1e154 overflows lcl.norm, so Sync would skip every tick and never bench the dummy
// plug; at the bound an output stays under (1 + max_units) * max_weight.
const max_weight = 1e6

// Policy is the dummy plug's trained policy, a multilayer perceptron from observe's features
// through one layer of tanh units to the command in the goal's frame and its speed, which
// Dummy.act flies the command's direction at. Where the pilot passed things on both sides, a
// regression averages the two commands into a short one, and a dummy plug much slower than the
// core's reflex loses sync and is benched. tools/train_dummy.py writes its weights and
// load_policy reads them.
struct Policy {
	v  int
	w1 [][]f64 // per unit, one weight per input
	b1 []f64
	w2 [][]f64 // along, across, then speed: one weight per unit
	b2 []f64
}

// load_policy reads the weights at path and refuses them unless their version, shape and numbers
// are what act needs, so act never indexes past a row and every output and its norm stay finite.
fn load_policy(path string) !Policy {
	text := os.read_file(path) or { return error('plug: cannot read the weights') }
	if !complete(text) {
		return error('plug: weights are no policy in JSON')
	}
	p := json2.decode[Policy](text) or { return error('plug: weights are no policy in JSON') }
	if p.v != policy_version {
		return error('plug: weights of version ${p.v}, not ${policy_version}')
	}
	units := p.b1.len
	if units < 1 || units > max_units {
		return error('plug: weights with ${units} units; accepted 1 to ${max_units}')
	}
	if p.w1.len != units || p.w1.any(it.len != inputs) || p.w2.len != 3 || p.w2.any(it.len != units)
		|| p.b2.len != 3 {
		return error('plug: weights of another shape than ${inputs} inputs, ${units} units and 3 outputs')
	}
	if !bounded([p.b1, p.b2], max_weight) || !bounded(p.w1, max_weight)
		|| !bounded(p.w2, max_weight) {
		return error('plug: weights hold a number that is not finite or beyond 1e6')
	}
	return p
}

// bounded reports whether every number in rows is at most bound in magnitude; NaN never is.
fn bounded(rows [][]f64, bound f64) bool {
	for row in rows {
		for x in row {
			if !(math.abs(x) <= bound) {
				return false
			}
		}
	}
	return true
}

// act is the policy's outputs for observe's features x: the command in the goal's frame, along
// and across, then its speed. tools/train_dummy.py predict computes the same.
fn (p Policy) act(x []f64) []f64 {
	mut y := p.b2.clone()
	for j, row in p.w1 {
		mut a := p.b1[j]
		for i, w in row {
			a += w * x[i]
		}
		h := math.tanh(a)
		for k, out in p.w2 {
			y[k] += out[j] * h
		}
	}
	return y
}

// complete reports whether s holds a JSON object or array whose every bracket closes, brackets in
// strings aside, with nothing after it. V 0.5.2's x.json2 never returns from decoding a text that
// ends right after a number inside an array, and a recorder line ends that way about every other
// time a kill cuts it, so load_dummy decodes complete lines only, read_datagram complete
// datagrams, open_feel complete replies and load_policy a complete file. Drop this check once a V
// release returns an error for such a text.
fn complete(s string) bool {
	mut depth := 0
	mut quoted := false
	mut escaped := false
	for i, c in s {
		if quoted {
			if escaped {
				escaped = false
			} else if c == `\\` {
				escaped = true
			} else if c == `"` {
				quoted = false
			}
			continue
		}
		match c {
			`"` {
				quoted = true
			}
			`{`, `[` {
				depth++
			}
			`}`, `]` {
				depth--
				if depth <= 0 {
					return depth == 0 && s[i + 1..].trim_space() == ''
				}
			}
			else {}
		}
	}
	return false
}
