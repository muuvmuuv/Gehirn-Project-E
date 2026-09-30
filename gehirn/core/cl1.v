// Biological backend for a Cortical Labs CL1. The culture runs in the vendor's closed loop
// (Python CL API) on the device. sidecar/cl1_sidecar.py streams spikes out in the format of
// their UDP example (u64 LE timestamp, then one byte per spiking channel) and turns our stim
// packets (u16 LE duration in ms, then channel and rate pairs) into neurons.stim() calls.
module core

import math
import net
import rand
import time
import lcl

pub struct Cl1Config {
pub:
	listen    string = '0.0.0.0:12345'   // spikes arrive here
	sidecar   string = '127.0.0.1:12346' // stim packets go here
	sensory   []int  = [1, 2, 3, 4]      // place code for the goal direction: +x, -x, +y, -y
	motor     []int  = [33, 34, 35, 36]  // read out as drive: +x, -x, +y, -y
	window_ms int    = 200
	rate_max  f64    = 40.0 // Hz at full stimulus
	hop       f64    = 1.0  // meters per proposal
}

pub struct Cl1Core {
	cfg Cl1Config
mut:
	spikes &net.UdpConn
	stim   &net.UdpConn
}

// new_cl1 binds the spike port and dials the sidecar.
pub fn new_cl1(cfg Cl1Config) !Cl1Core {
	spikes := net.listen_udp(cfg.listen)!
	stim := net.dial_udp(cfg.sidecar)!
	return Cl1Core{
		cfg:    cfg
		spikes: spikes
		stim:   stim
	}
}

// name identifies the backend in logs and in the journal.
pub fn (c Cl1Core) name() string {
	return 'cl1:${c.cfg.sidecar}'
}

// propose encodes where the beacon lies as stimulation rates on the sensory channels, listens
// for one window, and turns the imbalance between opposing motor channels into a short hop.
pub fn (mut c Cl1Core) propose(ctx lcl.Context) !lcl.Intent {
	p := ctx.percept
	target := first(p.scene, 'beacon') or { return error('cl1: nothing to seek') }
	rel := lcl.clamp_norm(lcl.sub(target.pos, p.pose), 1.0)
	signed := [rel[0], -rel[0], rel[1], -rel[1]]
	mut pairs := [][]int{}
	for i, ch in c.cfg.sensory {
		pairs << [ch, int(math.max(0.0, signed[i]) * c.cfg.rate_max)]
	}
	c.drain()
	c.send(c.cfg.window_ms, pairs)
	counts := c.collect(c.cfg.window_ms)
	drive := [f64(counts[0] - counts[1]), f64(counts[2] - counts[3])]
	n := lcl.norm(drive)
	if n == 0.0 {
		return lcl.Intent{
			verb:   'hold'
			why:    'culture silent'
			origin: c.name()
		}
	}
	return lcl.Intent{
		verb:   'goto'
		target: lcl.add(p.pose, lcl.scale(drive, c.cfg.hop / n))
		why:    'motor drive ${counts}'
		origin: c.name()
	}
}

// feedback follows DishBrain (Kagan et al., Neuron 2022): after a success the culture gets a
// predictable burst, after a failure seconds of unpredictable stimulation. A culture takes no
// reward scalar; it learns to act so that its input becomes predictable.
pub fn (mut c Cl1Core) feedback(o lcl.Outcome) {
	if o.good {
		c.send(100, c.cfg.sensory.map([it, 100]))
		return
	}
	for _ in 0 .. 20 {
		mut pairs := [][]int{}
		for ch in c.cfg.sensory {
			if rand.f64() < 0.5 {
				r := rand.intn(145) or { 0 }
				pairs << [ch, 5 + r]
			}
		}
		c.send(200, pairs)
		time.sleep(200 * time.millisecond)
	}
}

fn (mut c Cl1Core) send(duration_ms int, pairs [][]int) {
	mut buf := [u8(duration_ms & 0xff), u8((duration_ms >> 8) & 0xff)]
	for pr in pairs {
		buf << u8(pr[0])
		buf << u8(math.min(pr[1], 255))
	}
	c.stim.write(buf) or {}
}

// drain discards spikes that arrived before the stimulus, so the window only sees the answer.
fn (mut c Cl1Core) drain() {
	mut buf := []u8{len: 1500}
	c.spikes.set_read_timeout(time.millisecond)
	for {
		c.spikes.read(mut buf) or { break }
	}
}

// collect counts spikes per motor channel over one window.
fn (mut c Cl1Core) collect(window_ms int) []int {
	mut counts := []int{len: c.cfg.motor.len}
	mut buf := []u8{len: 1500}
	deadline := lcl.now_ms() + window_ms
	for {
		left := deadline - lcl.now_ms()
		if left <= 0 {
			break
		}
		c.spikes.set_read_timeout(time.Duration(left) * time.millisecond)
		n, _ := c.spikes.read(mut buf) or { break }
		if n < 9 {
			continue
		}
		for ch in buf[8..n] {
			idx := c.cfg.motor.index(int(ch))
			if idx >= 0 {
				counts[idx]++
			}
		}
	}
	return counts
}

fn first(scene []lcl.Entity, kind string) ?lcl.Entity {
	for e in scene {
		if e.kind == kind {
			return e
		}
	}
	return none
}
