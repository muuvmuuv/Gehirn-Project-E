module main

import gg
import math
import lcl

// The bridge's palette: amber frames and labels on near black, as NERV's screens, with one color
// per meaning. Every color is bright on ink, so text stays legible from across a room.
const ink = gg.Color{10, 10, 12, 255} // tools/caption.py GROUND
const amber = gg.Color{255, 140, 26, 255} // tools/caption.py INK
const paper = gg.Color{236, 232, 225, 255}
const dim = gg.Color{139, 134, 128, 255}
const grid = gg.Color{30, 30, 34, 255}
const green = gg.Color{47, 211, 107, 255} // 可決, connected
const red = gg.Color{255, 59, 48, 255} // 否決, humans, refusals, depleted
const yellow = gg.Color{255, 214, 10, 255} // 故障, internal power
const beacon = gg.Color{54, 197, 240, 255}
const rock = gg.Color{90, 90, 96, 255}

// world is how far the scene reaches from the origin, in meters, each way.
// ponytail: a fixed frame that holds the simulator's scene; fit it to the scene once a body
// roams further.
const world = 6.0

// fade is how long a new verdict takes to come up, in milliseconds.
const fade = 200

// draw paints s for unit at now, as frame calls it once per frame.
fn draw(ctx &gg.Context, s State, unit string, now i64) {
	label(ctx, 24, 18, 'GEHIRN BRIDGE', 22, amber)
	label(ctx, 230, 23, 'UNIT ${unit}', 15, dim)
	field := heard(s.view_at, now)
	label(ctx, 1256 - width(ctx, 'FIELD ${field}', 15), 23, 'FIELD ${field}', 15, if field == 'live' {
		green
	} else {
		red
	})
	draw_magi(ctx, s, now, 24, 64, 600, 330)
	draw_proposals(ctx, s, 24, 410, 600, 190)
	draw_fault(ctx, s, now, 24, 616, 600, 160)
	draw_scene(ctx, s, 660, 64, 596, 420)
	draw_seat(ctx, s, 660, 500, 290, 120)
	draw_umbilical(ctx, s, now, 966, 500, 290, 120)
	draw_lists(ctx, s, 660, 636, 596, 140)
}

fn label(ctx &gg.Context, x int, y int, text string, size int, color gg.Color) {
	ctx.draw_text(x, y, text, gg.TextCfg{
		color: color
		size:  size
	})
}

// width is how wide text draws at size. gg measures at the size set last, so set it first.
fn width(ctx &gg.Context, text string, size int) int {
	ctx.set_text_cfg(gg.TextCfg{
		size: size
	})
	return ctx.text_width(text)
}

fn frame_box(ctx &gg.Context, x int, y int, w int, h int, title string) {
	ctx.draw_rect_empty(x, y, w, h, amber)
	ctx.draw_rect_filled(x, y, width(ctx, title, 14) + 16, 20, amber)
	label(ctx, x + 8, y + 3, title, 14, ink)
}

fn with_alpha(c gg.Color, a f64) gg.Color {
	return gg.Color{c.r, c.g, c.b, u8(math.clamp(a, 0.0, 1.0) * 255)}
}

// ease_out is a strong ease out over t from 0 to 1, so a new verdict lands at once and settles.
fn ease_out(t f64) f64 {
	u := math.clamp(t, 0.0, 1.0)
	return 1.0 - math.pow(1.0 - u, 5)
}

fn mark_color(vote string) gg.Color {
	return match vote {
		'approve' { green }
		'reject' { red }
		else { yellow }
	}
}

fn draw_magi(ctx &gg.Context, s State, now i64, x int, y int, w int, h int) {
	frame_box(ctx, x, y, w, h, 'MAGI')
	if s.verdict_at == 0 {
		label(ctx, x + 16, y + 40, 'NO VERDICT YET', 18, dim)
		return
	}
	v := s.verdict
	label(ctx, x + 16, y + 34, v.proposal.label(), 20, paper)
	tally := '${v.yes}/${v.votes.len}, need ${v.needed}: ${seal(v.approved)}'
	label(ctx, x + w - 16 - width(ctx, tally, 20), y + 34, tally, 20, if v.approved {
		green
	} else {
		red
	})
	t := ease_out(f64(now - s.verdict_at) / fade)
	bw := (w - 32 - 2 * 12) / 3
	for i, vote in v.votes {
		if i >= 3 {
			break
		}
		bx := x + 16 + i * (bw + 12)
		by := y + 72
		bh := h - 88
		c := mark_color(vote.vote)
		ctx.draw_rect_filled(bx, by, bw, bh, with_alpha(c, 0.18 * t))
		ctx.draw_rect_empty(bx, by, bw, bh, with_alpha(c, 0.4 + 0.6 * t))
		label(ctx, bx + 10, by + 8, vote.unit, 15, paper)
		label(ctx, bx + 10, by + 30, mark(vote.vote), 40, with_alpha(c, 0.35 + 0.65 * t))
		label(ctx, bx + 10, by + 80, '${vote.model}, ${vote.latency_ms} ms', 12, dim)
		for j, line in wrap(vote.why, 24) {
			if j >= 5 {
				break
			}
			label(ctx, bx + 10, by + 102 + j * 17, line, 13, paper)
		}
	}
}

fn draw_proposals(ctx &gg.Context, s State, x int, y int, w int, h int) {
	frame_box(ctx, x, y, w, h, 'PROPOSALS')
	if s.proposals.len == 0 {
		label(ctx, x + 16, y + 34, 'none yet', 15, dim)
	}
	for i, p in s.proposals {
		label(ctx, x + 16, y + 34 + i * 24, p, 16, if i == 0 { paper } else { dim })
	}
}

fn draw_fault(ctx &gg.Context, s State, now i64, x int, y int, w int, h int) {
	frame_box(ctx, x, y, w, h, 'CORE')
	if s.fault_at == 0 {
		label(ctx, x + 16, y + 34, 'no fault', 15, dim)
	} else {
		label(ctx, x + 16, y + 34, 'FAULT ${(now - s.fault_at) / 1000} s ago', 16, red)
		for j, line in wrap(s.fault, 70) {
			if j >= 3 {
				break
			}
			label(ctx, x + 16, y + 60 + j * 20, line, 14, paper)
		}
	}
	if s.dropped != '' {
		label(ctx, x + 16, y + h - 26, 'dropped: ${s.dropped}', 13, dim)
	}
}

fn draw_scene(ctx &gg.Context, s State, x int, y int, w int, h int) {
	frame_box(ctx, x, y, w, h, 'SCENE')
	// The map sits between the title and the goal line.
	scale := f32(math.min(w - 24, h - 56)) / f32(2 * world)
	cx := f32(x) + f32(w) / 2
	cy := f32(y + 26) + f32(h - 56) / 2
	px := fn [cx, scale] (m f64) f32 {
		return cx + f32(m) * scale
	}
	py := fn [cy, scale] (m f64) f32 {
		return cy - f32(m) * scale
	}
	for m := -int(world); m <= int(world); m++ {
		ctx.draw_line(px(m), py(world), px(m), py(-world), grid)
		ctx.draw_line(px(-world), py(m), px(world), py(m), grid)
	}
	if s.view_at == 0 {
		return
	}
	p := s.view.percept
	for e in p.scene {
		if e.pos.len < 2 {
			continue
		}
		ex, ey := px(e.pos[0]), py(e.pos[1])
		r := f32(e.r) * scale
		match e.kind {
			'obstacle' {
				ctx.draw_circle_filled(ex, ey, r, rock)
			}
			'beacon' {
				ctx.draw_circle_empty(ex, ey, r, beacon)
				ctx.draw_circle_empty(ex, ey, f32(lcl.beacon_reach) * scale,
					with_alpha(beacon, 0.4))
			}
			'human' {
				ctx.draw_circle_filled(ex, ey, r, red)

				// The armor keeps an irreversible act 2 m from a human.
				ctx.draw_circle_empty(ex, ey, 2 * scale, with_alpha(red, 0.35))
			}
			else {
				ctx.draw_circle_empty(ex, ey, r, dim)
			}
		}

		label(ctx, int(ex + r + 4), int(ey - 8), e.id, 12, dim)
	}
	g := s.view.goal
	if g.verb == 'goto' && g.target.len >= 2 {
		gx, gy := px(g.target[0]), py(g.target[1])
		ctx.draw_line(gx - 8, gy - 8, gx + 8, gy + 8, amber)
		ctx.draw_line(gx - 8, gy + 8, gx + 8, gy - 8, amber)
	}
	if p.pose.len >= 2 {
		bx, by := px(p.pose[0]), py(p.pose[1])
		ctx.draw_circle_filled(bx, by, 0.25 * scale, amber)
		if p.vel.len >= 2 {
			ctx.draw_line(bx, by, px(p.pose[0] + p.vel[0]), py(p.pose[1] + p.vel[1]), paper)
		}
	}
	label(ctx, x + 16, y + h - 24, 'GOAL ${g.label()}${if p.payload {
		'   PAYLOAD ABOARD'
	} else {
		''
	}}', 14, paper)
}

fn bar(ctx &gg.Context, x int, y int, w int, value f64, color gg.Color) {
	ctx.draw_rect_empty(x, y, w, 10, dim)
	ctx.draw_rect_filled(x, y, f32(w) * f32(math.clamp(value, 0.0, 1.0)), 10, color)
}

fn draw_seat(ctx &gg.Context, s State, x int, y int, w int, h int) {
	frame_box(ctx, x, y, w, h, 'SEAT')
	if s.view_at == 0 {
		return
	}
	v := s.view
	label(ctx, x + 16, y + 30, v.seat.to_upper(), 20, if v.seat == 'empty' { dim } else { paper })
	label(ctx, x + 16, y + 60, 'SYNC ${v.sync * 100:.0f}%', 14, paper)
	bar(ctx, x + 120, y + 64, w - 136, v.sync, amber)

	// At or below 30% the core only advises and a dummy plug loses the seat; main.v threshold.
	tx := f32(x + 120) + f32(w - 136) * 0.3
	ctx.draw_line(tx, y + 60, tx, y + 78, red)
	label(ctx, x + 16, y + 88, 'CORE ${v.authority:.2f}', 14, paper)
	bar(ctx, x + 120, y + 92, w - 136, v.authority, beacon)
}

fn draw_umbilical(ctx &gg.Context, s State, now i64, x int, y int, w int, h int) {
	frame_box(ctx, x, y, w, h, 'UMBILICAL')
	if s.view_at == 0 {
		label(ctx, x + 16, y + 40, '-:--', 44, dim)
		return
	}
	state := s.view.umbilical
	color := match state {
		'connected' { green }
		'internal' { yellow }
		else { red }
	}

	label(ctx, x + 16, y + 30, state.to_upper(), 16, color)
	label(ctx, x + 16, y + 52, clock(s.left_ms(now)), 48, color)
}

fn draw_lists(ctx &gg.Context, s State, x int, y int, w int, h int) {
	half := (w - 16) / 2
	frame_box(ctx, x, y, half, h, 'ARMOR REFUSALS')
	for i, r in s.refusals {
		label(ctx, x + 12, y + 30 + i * 18, r, 13, red)
	}
	frame_box(ctx, x + half + 16, y, half, h, 'OUTCOMES')
	for i, o in s.outcomes {
		label(ctx, x + half + 28, y + 30 + i * 18, o, 13, paper)
	}
}
