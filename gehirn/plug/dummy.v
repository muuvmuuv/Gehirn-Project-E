// Dummy plug: the pilot's driving style, imitated. It never learns where the pilot wanted
// to go, only how they drive toward a goal MAGI approved: k nearest neighbor behavior
// cloning over the recorder's log. Every command is stored in the goal's own frame, as speed
// along the way to the goal and speed across it, so an imitation that overshoots turns back
// instead of holding a heading it memorized. Planar like the simulator, and crude on
// purpose; a trained policy drops in behind the same methods.
module plug

import x.json2
import os
import lcl

pub struct Dummy {
	k     int = 7
	limit int = 20000
	min   int = 500
mut:
	xs   [][]f64
	ys   [][]f64
	next int
}

// load_dummy replays every tick a pilot flew, from the recorder's log.
pub fn load_dummy(path string) Dummy {
	mut d := Dummy{}
	lines := os.read_lines(path) or { return d }
	for line in lines {
		r := json2.decode[Record](line) or { continue }
		if r.seat == 'pilot' {
			d.learn(r.pose, r.target, r.u_seat)
		}
	}
	return d
}

// size is the number of samples on file.
pub fn (d Dummy) size() int {
	return d.xs.len
}

// ready reports whether enough of the pilot is on file to imitate.
pub fn (d Dummy) ready() bool {
	return d.xs.len >= d.min
}

// learn stores one pilot tick. Ticks without a goal carry no style and are skipped.
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
pub fn (d Dummy) act(pose []f64, target []f64) []f64 {
	idle := []f64{len: pose.len}
	along, across := frame(pose, target) or { return idle }
	if d.xs.len == 0 || lcl.dist(pose, target) < lcl.arrive {
		return idle
	}
	q := features(pose, target)
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

// features are how far away the goal is and where the body is.
fn features(pose []f64, target []f64) []f64 {
	mut f := [lcl.dist(pose, target)]
	f << pose
	return f
}
