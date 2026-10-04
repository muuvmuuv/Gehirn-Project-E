module main

import gg
import math
import sokol.sgl
import lcl

// screen_w and screen_h are the window in logical pixels; main.v opens it this size and draw lays
// every panel out in it.
const screen_w = 1280
const screen_h = 800

// ink is the window's ground and opens the bridge's palette, after NERV's screens: orange frames
// and labels on black, MAGI's blue, green and red, and one color per meaning elsewhere.
const ink = gg.Color{4, 4, 6, 255} // tools/caption.py GROUND
const pitch = gg.Color{0, 0, 0, 255} // text on a lit panel
const ground = gg.Color{12, 9, 6, 255} // inside a panel
const orange = gg.Color{255, 141, 0, 255} // tools/caption.py INK
const hot = gg.Color{255, 176, 40, 255}
const ember = gg.Color{122, 67, 0, 255} // dim orange: frames, ghosts, secondary labels
const umber = gg.Color{38, 22, 6, 255} // grids
const rule = gg.Color{39, 117, 71, 255} // the double rules of 提訴 and 決議
const thinking = gg.Color{60, 174, 224, 255} // 審議中
const thinking_dim = gg.Color{22, 84, 116, 255}
const aye = gg.Color{82, 230, 145, 255} // 可決, a good outcome
const nay = gg.Color{164, 20, 19, 255} // a 否決 panel
const alert = gg.Color{255, 32, 48, 255} // 否決, humans, refusals, faults, a cut cable
const alert_deep = gg.Color{110, 0, 0, 255}
const caution = gg.Color{255, 200, 0, 255} // HQ silent, cable still connected
const paper = gg.Color{236, 232, 225, 255}
const dim = gg.Color{139, 134, 128, 255}
const cyan = gg.Color{54, 197, 240, 255} // the beacon, the core's authority
const rock = gg.Color{58, 56, 60, 255}
const timer = gg.Color{247, 147, 30, 255} // the 活動限界 clock
const power = gg.Color{231, 130, 0, 255} // a lit 内部 or 外部 box

// units are MAGI's units as main.v load_config names them, with the name each panel shows.
const units = ['MELCHIOR-1', 'BALTHASAR-2', 'CASPER-3']!
const shown_as = ['MELCHIOR • 1', 'BALTHASAR • 2', 'CASPER • 3']!

// human_stop and release_keep are the armor's distances around a human in meters, which the scene
// draws as rings; armor/armor.v Limits holds them and names this copy.
const human_stop = 0.7
const release_keep = 2.0

// threshold is the sync ratio at or below which the core only advises and a dummy plug loses the
// seat, drawn as the harmonics graph's 絶対境界線; main.v threshold, which names this copy.
const threshold = 0.3

// boot_ms is how long the boot sequence runs before the panels, in milliseconds. The Justfile's
// _fly recipe waits it out before it starts the field unit.
const boot_ms = 2800

// fan_line says on the boot screen and in the footer whose this is not.
const fan_line = 'FAN PROJECT. NOT AFFILIATED WITH KHARA OR GEHIRN INC.'

// Txt is how draw sets one string: its size, color and face, how far it is stretched
// horizontally, below 1 squeezed as Eva's title cards are, and where x anchors it.
@[params]
struct Txt {
	size   int      = 16
	color  gg.Color = paper
	family string
	sx     f32                = 1.0
	align  gg.HorizontalAlign = .left
}

// Rect is a box on screen, for keeping the scene's labels apart.
struct Rect {
	x f32
	y f32
	w f32
	h f32
}

fn (a Rect) overlaps(b Rect) bool {
	return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

// draw paints s for unit at now, with at where the bridge listens: the boot sequence for
// boot_ms, then the panels.
fn draw(ctx &gg.Context, s State, unit string, at string, now i64) {
	if now - s.born < boot_ms {
		draw_boot(ctx, s, unit, at, now)
		scanlines(ctx)
		return
	}
	ctx.draw_rect_filled(0, 0, screen_w, screen_h, ink)
	draw_header(ctx, s, unit, now)
	draw_magi(ctx, s, now, 16, 58, 736, 412) // the Justfile's demo-record crops its GIF to this block
	draw_harmonics(ctx, s, 16, 480, 736, 160)
	draw_core(ctx, s, now, 16, 650, 736, 124)
	draw_limit(ctx, s, now, 768, 58, 496, 210)
	draw_scene(ctx, s, unit, 768, 278, 496, 348)
	draw_logs(ctx, s, 768, 636, 496, 138)
	draw_footer(ctx, s)
	if s.emergency(now) {
		draw_emergency(ctx, s, now)
	}
	scanlines(ctx)
}

// text draws s at x, y as t sets it.
fn text(ctx &gg.Context, x f32, y f32, s string, t Txt) {
	mut ox := x
	if t.align != .left {
		w := measure(ctx, s, t)
		ox = if t.align == .right { x - w } else { x - w / 2 }
	}
	cfg := gg.TextCfg{
		color:  t.color
		size:   t.size
		family: t.family
	}
	if t.sx == 1.0 {
		ctx.draw_text(int(ox), int(y), s, cfg)
		return
	}
	k := ctx.scale
	sgl.matrix_mode_modelview()
	sgl.push_matrix()
	sgl.translate(ox * k, y * k, 0)
	sgl.scale(t.sx, 1, 1)
	sgl.translate(-ox * k, -y * k, 0)
	ctx.draw_text(int(ox), int(y), s, cfg)
	sgl.pop_matrix()
}

// glow draws s with a faint halo, for the figures that matter most.
fn glow(ctx &gg.Context, x f32, y f32, s string, t Txt) {
	halo := Txt{
		...t
		color: fade(t.color, 0.22)
	}
	for d in [[f32(-2), 0], [f32(2), 0], [f32(0), -2], [f32(0), 2]] {
		text(ctx, x + d[0], y + d[1], s, halo)
	}
	text(ctx, x, y, s, t)
}

// measure is how wide s draws as t sets it. gg measures with the face and size set last.
fn measure(ctx &gg.Context, s string, t Txt) f32 {
	ctx.set_text_cfg(gg.TextCfg{
		size:   t.size
		family: t.family
	})
	return ctx.text_width_f(s) * t.sx
}

fn fade(c gg.Color, a f64) gg.Color {
	return gg.Color{c.r, c.g, c.b, u8(math.clamp(a, 0.0, 1.0) * f64(c.a))}
}

// blink is c for the first duty of every period ms, and off for the rest.
fn blink(now i64, period i64, duty f64, c gg.Color, off gg.Color) gg.Color {
	return if on(now, period, duty) { c } else { off }
}

// on is a blink: true for the first duty of every period ms.
fn on(now i64, period i64, duty f64) bool {
	return f64(now % period) < f64(period) * duty
}

// stroke draws a line w pixels wide as two triangles, which sokol_gl merges with its neighbors
// into one draw call. gg's draw_line_with_config turns the matrix for every line, which stops the
// merge, and the harmonics graph and the trail then cost a draw call per segment.
fn stroke(ctx &gg.Context, x1 f32, y1 f32, x2 f32, y2 f32, w f32, c gg.Color) {
	dx, dy := x2 - x1, y2 - y1
	l := math.sqrtf(dx * dx + dy * dy)
	if l == 0 {
		return
	}
	nx, ny := -dy / l * w / 2, dx / l * w / 2
	ctx.draw_triangle_filled(x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, c)
	ctx.draw_triangle_filled(x1 + nx, y1 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny, c)
}

// hexagon fills a hexagon with a corner at the top and bottom, as six triangles for the same
// reason as stroke; gg's draw_polygon_filled draws a strip, which never merges.
fn hexagon(ctx &gg.Context, cx f32, cy f32, r f32, c gg.Color) {
	for i in 0 .. 6 {
		a1, a2 := math.pi / 3 * f64(i) + math.pi / 6, math.pi / 3 * f64(i + 1) + math.pi / 6
		ctx.draw_triangle_filled(cx, cy, cx + r * f32(math.cos(a1)), cy + r * f32(math.sin(a1)),

			cx + r * f32(math.cos(a2)), cy + r * f32(math.sin(a2)), c)
	}
}

// poly fills the shape pts, given as fractions of a w by h box at x, y.
fn poly(ctx &gg.Context, x f32, y f32, w f32, h f32, pts [][2]f32, c gg.Color) {
	mut a := []f32{cap: pts.len * 2}
	for p in pts {
		a << x + p[0] * w
		a << y + p[1] * h
	}
	ctx.draw_convex_poly(a, c)
}

// hazard fills a band with diagonal stripes of c on back, moved along by shift pixels.
fn hazard(ctx &gg.Context, x f32, y f32, w f32, h f32, c gg.Color, back gg.Color, shift f32) {
	ctx.draw_rect_filled(x, y, w, h, back)
	ctx.scissor_rect(int(x), int(y), int(w), int(h))
	mut i := -2 * h + f32(math.fmod(shift, 2 * h))
	for i < w + h {
		ctx.draw_convex_poly([x + i, y, x + i + h, y, x + i, y + h, x + i - h, y + h], c)
		i += 2 * h
	}
	ctx.scissor_rect(0, 0, screen_w, screen_h)
}

fn scanlines(ctx &gg.Context) {
	for y := 0; y < screen_h; y += 3 {
		ctx.draw_rect_filled(0, y, screen_w, 1, gg.Color{0, 0, 0, 60})
	}
}

// corners marks a box's corners with short bright brackets.
fn corners(ctx &gg.Context, x f32, y f32, w f32, h f32, l f32, c gg.Color) {
	for cx in [x, x + w - l] {
		for cy in [y, y + h - 2] {
			ctx.draw_rect_filled(cx, cy, l, 2, c)
		}
	}
	for cx in [x, x + w - 2] {
		for cy in [y, y + h - l] {
			ctx.draw_rect_filled(cx, cy, 2, l, c)
		}
	}
}

// frame_box draws a panel: its ground, a dim frame with bright corners, and a tab with its name
// and the name in Japanese beside it.
fn frame_box(ctx &gg.Context, x f32, y f32, w f32, h f32, en string, jp string) {
	ctx.draw_rect_filled(x, y, w, h, ground)
	ctx.draw_rect_empty(x, y, w, h, ember)
	corners(ctx, x, y, w, h, 12, orange)
	tw := measure(ctx, en, size: 15, family: black) + 14
	ctx.draw_rect_filled(x, y, tw, 20, orange)
	text(ctx, x + 7, y + 1, en, size: 15, color: pitch, family: black)
	if jp != '' {
		text(ctx, x + tw + 8, y + 1, jp, size: 15, color: orange, family: mincho)
	}
}

fn lamp(ctx &gg.Context, x f32, y f32, name string, state string, c gg.Color) f32 {
	ctx.draw_rect_filled(x, y + 5, 10, 10, c)
	ctx.draw_rect_filled(x - 2, y + 3, 14, 14, fade(c, 0.25))
	text(ctx, x + 18, y + 1, name, size: 15, color: ember, family: black)
	nw := measure(ctx, name, size: 15, family: black)
	text(ctx, x + 24 + nw, y + 1, state, size: 15, color: c, family: black)
	return 24 + nw + measure(ctx, state, size: 15, family: black)
}

fn draw_header(ctx &gg.Context, s State, unit string, now i64) {
	hazard(ctx, 0, 0, screen_w, 8, orange, gg.Color{20, 11, 2, 255}, f32(now / 40))
	glow(ctx, 16, 12, 'GEHIRN', size: 32, color: orange, family: mincho, sx: 0.82)
	tw := measure(ctx, 'GEHIRN', size: 32, family: mincho, sx: 0.82)
	text(ctx, 28 + tw, 14, '発令所', size: 16, color: orange, family: mincho)
	text(ctx, 28 + tw, 32, 'OPERATIONS BRIDGE', size: 11, color: ember, family: black)
	text(ctx, 330, 18, 'UNIT', size: 13, color: ember, family: black)
	text(ctx, 362, 12, unit.to_upper(), size: 24, color: orange, family: black)
	text(ctx, 470, 18, 'MISSION', size: 13, color: ember, family: black)
	clock_text := s.mission(now)
	text(ctx, 530, 12, clock_text[..2], size: 24, color: timer, family: black)
	text(ctx, 556, 14, '88:88', size: 20, color: gg.Color{52, 26, 0, 255}, family: seg)
	glow(ctx, 556, 14, clock_text[2..], size: 20, color: timer, family: seg)

	field := heard(s.view_at, now)
	field_c, field_s := match true {
		s.view_at == 0 { dim, 'NO DATA' }
		field == 'live' { aye, 'LIVE' }
		else { alert, field.to_upper() }
	}

	link := s.link(now)
	silence := f64(s.silence(now)) / 1000
	hq_c, hq_s := match link {
		'live' {
			aye, 'LINK'
		}
		'lost' {
			blink(now, 330, 0.8, caution, ember), 'SILENT ${silence:.1f} S'
		}
		'cut', 'depleted' {
			alert, 'CUT'
		}
		'awaiting' {
			dim, 'AWAITING'
		}
		else {
			dim, 'NO DATA'
		}
	}

	magi_c, magi_s := if s.deliberating {
		blink(now, 250, 0.5, thinking, thinking_dim), '審議中'
	} else if s.code > 0 && link == 'live' {
		aye, 'STANDBY'
	} else if s.code > 0 {
		dim, 'OFFLINE'
	} else {
		dim, 'NO DATA'
	}
	mut x := f32(760)
	x += lamp(ctx, x, 14, 'FIELD', field_s, field_c) + 26
	x += lamp(ctx, x, 14, 'HQ', hq_s, hq_c) + 26
	lamp(ctx, x, 14, 'MAGI', magi_s, magi_c)
	ctx.draw_rect_filled(0, 48, screen_w, 1, ember)
}

fn draw_footer(ctx &gg.Context, s State) {
	text(ctx, 16, 781, fan_line, size: 13, color: dim, family: black)
	if s.dropped != '' {
		text(ctx, screen_w - 16, 781, 'DROPPED: ${s.dropped}'.to_upper(),
			size:   13
			color:  alert
			family: black
			align:  .right
		)
	} else {
		text(ctx, screen_w - 16, 781, 'WATCH ONLY · NO CONTROL PATH (ADR-0005)',
			size:   13
			color:  ember
			family: black
			align:  .right
		)
	}
}

// balthasar_shape, casper_shape and melchior_shape are the MAGI units' outlines as fractions of
// each unit's box, after the canon's three angled blocks.
const balthasar_shape = [[f32(0), 0]!, [f32(1), 0]!, [f32(1), 0.8]!,
	[f32(0.75), 1]!, [f32(0.25), 1]!, [f32(0), 0.8]!]!
const casper_shape = [[f32(0), 0]!, [f32(0.65), 0]!, [f32(1), 0.44]!,
	[f32(1), 1]!, [f32(0), 1]!]!
const melchior_shape = [[f32(0.35), 0]!, [f32(1), 0]!, [f32(1), 1]!,
	[f32(0), 1]!, [f32(0), 0.44]!]!

fn draw_magi(ctx &gg.Context, s State, now i64, x f32, y f32, w f32, h f32) {
	ctx.draw_rect_filled(x, y, w, h, ground)
	ctx.draw_rect_empty(x, y, w, h, ember)
	corners(ctx, x, y, w, h, 12, orange)
	rejected := s.verdict_at > 0 && !s.deliberating && !s.verdict.approved
	if rejected && now - s.verdict_at < 1600 && on(now, 320, 0.6) {
		hazard(ctx, x, y, w, 8, alert, alert_deep, f32(now / 20))
		hazard(ctx, x, y + h - 8, w, 8, alert, alert_deep, f32(now / 20))
	}
	header(ctx, x + 12, y + 14, '提 訴')
	header(ctx, x + w - 222, y + 14, '決 議')

	// The status block, after the canon's, with the misspelled EXTENTION kept; each line shows
	// the stack's own state.
	p := s.proposal
	longest := s.ballots.values().map(it.latency_ms)
	file := if s.code == 0 { '---' } else { p.verb.to_upper() }
	extention := if longest.len == 0 { '----' } else { '${arrays_max(longest):04}' }
	mode := if s.view_at == 0 { '---' } else { ex_mode(s.view) }
	for i, line in [
		['CODE:', if s.code == 0 {
			'---'
		} else {
			'${s.code:03}'
		}],
		['FILE:', file],
		['EXTENTION:', extention],
		['EX_MODE:', mode],
		['PRIORITY:', if s.code == 0 {
			'---'
		} else {
			priority(p)
		}],
	] {
		ly := y + 84 + i * 22
		text(ctx, x + 16, ly, line[0], size: 19, color: orange, family: black, sx: 1.1)
		lw := measure(ctx, line[0], size: 19, family: black, sx: 1.1)
		hit := line[0] == 'EX_MODE:' && mode in ['DUMMY', 'BENCHED'] && on(now, 500, 0.6)
		text(ctx, x + 18 + lw, ly, line[1],
			size:   19
			color:  if hit { alert } else { hot }
			family: black
			sx:     1.1
		)
	}
	if s.code > 0 {
		text(ctx, x + 16, y + 198, p.label().to_upper(), size: 17, color: paper, family: black)
		for j, l in wrap('${p.origin}: ${p.why}', 40) {
			if j >= 2 {
				break
			}
			text(ctx, x + 16, y + 218 + j * 15, l, size: 14, color: dim)
		}
	}

	// Connectors, then the units over them.
	cx := x + w / 2
	stroke(ctx, cx - 150, y + 372, cx + 150, y + 372, 9, orange)
	stroke(ctx, cx - 136, y + 300, cx - 76, y + 220, 9, orange)
	stroke(ctx, cx + 76, y + 220, cx + 136, y + 300, 9, orange)
	text(ctx, cx, y + 300, 'MAGI', size: 40, color: orange, family: black, align: .center)
	unit_panel(ctx, s, now, 1, cx - 110, y + 80, 220, 166, balthasar_shape[..], .center)
	unit_panel(ctx, s, now, 2, cx - 334, y + 256, 252, 148, casper_shape[..], .left)
	unit_panel(ctx, s, now, 0, cx + 82, y + 256, 252, 148, melchior_shape[..], .right)

	// 決議: the verdict, or 審議中 while MAGI deliberates.
	vx, vy := x + w - 222, y + 80
	mut c, mut word, mut tally := ember, '---', ''
	if s.deliberating {
		c = blink(now, 250, 0.5, thinking, thinking_dim)
		word = '審議中'
		tally = '${s.ballots.len}/${units.len} · NEED ${s.needed}'
	} else if s.verdict_at > 0 {
		v := s.verdict
		c = if v.approved { aye } else { alert }
		word = if v.approved { '可 決' } else { '否 決' }
		tally = '${v.yes}/${v.votes.len} · NEED ${v.needed}'
	} else if s.code > 0 {
		c = dim
		tally = 'NO VERDICT'
	}
	ctx.draw_rect_empty(vx, vy, 210, 74, c)
	ctx.draw_rect_empty(vx + 4, vy + 4, 202, 66, c)
	stamp := if s.deliberating || s.verdict_at == 0 {
		1.0
	} else {
		f64(now - s.verdict_at) / 140
	}
	if stamp < 1 {
		ctx.draw_rect_filled(vx, vy, 210, 74, fade(paper, 0.7 * (1 - stamp)))
	}
	glow(ctx, vx + 105, vy + 12, word,
		size:   44
		color:  fade(c, 0.3 + 0.7 * stamp)
		family: mincho
		sx:     0.92
		align:  .center
	)
	text(ctx, vx + 105, vy + 82, tally, size: 20, color: c, family: black, align: .center)
	for i, e in s.verdicts {
		// The box shows the newest verdict unless MAGI deliberates anew or the vote ended without
		// one, so the list starts below it.
		row := if s.deliberating || s.verdict_at == 0 { i } else { i - 1 }
		if row < 0 || row >= 3 {
			continue
		}
		ly := vy + 112 + row * 17
		text(ctx, vx, ly, '${s.mission(e.at)} ${e.text.to_upper()}', size: 14, color: dim)
		text(ctx, vx + 210, ly, seal(e.good),
			size:   14
			color:  if e.good { aye } else { alert }
			family: mincho
			align:  .right
		)
	}
}

fn arrays_max(a []i64) i64 {
	mut m := a[0]
	for v in a {
		if v > m {
			m = v
		}
	}
	return m
}

// header draws 提訴 or 決議 between double rules, 210 pixels wide.
fn header(ctx &gg.Context, x f32, y f32, title string) {
	for dy in [f32(0), 6, 50, 56] {
		ctx.draw_rect_filled(x, y + dy, 210, 3, rule)
	}
	glow(ctx, x + 105, y + 12, title,
		size:   34
		color:  orange
		family: mincho
		sx:     1.5
		align:  .center
	)
}

// unit_panel draws MAGI unit i in its shape: blue and flickering while it deliberates, green on
// 可決, red on 否決, black with a blinking 故障 on a fault, and a white flash as its ballot lands.
fn unit_panel(ctx &gg.Context, s State, now i64, i int, x f32, y f32, w f32, h f32, shape [][2]f32, align gg.HorizontalAlign) {
	state, vote := s.panel(units[i])
	fill, ink_c := match state {
		'deliberating' {
			blink(now, 250, 0.5, thinking, thinking_dim), pitch
		}
		'approve' {
			aye, pitch
		}
		'reject' {
			nay, paper
		}
		'fault' {
			pitch, blink(now, 1000, 0.5, alert, alert_deep)
		}
		else {
			gg.Color{18, 18, 22, 255}, ember
		}
	}

	poly(ctx, x, y, w, h, shape, orange)
	poly(ctx, x + 4, y + 4, w - 8, h - 8, shape, fill)
	if at := s.landed[units[i]] {
		t := f64(now - at) / 160
		if t < 1 {
			poly(ctx, x + 4, y + 4, w - 8, h - 8, shape, fade(paper, 0.85 * (1 - t)))
		}
	}
	tx := match align {
		.left { x + 14 }
		.right { x + w - 14 }
		.center { x + w / 2 }
	}

	text(ctx, tx, y + 10, shown_as[i], size: 22, color: ink_c, family: black, align: align)
	word := match state {
		'deliberating' { '審議中' }
		'idle' { '待機' }
		else { mark(state) }
	}

	text(ctx, tx, y + 36, word, size: 34, color: ink_c, family: mincho, align: align)
	if state in ['idle', 'deliberating'] {
		return
	}
	text(ctx, tx, y + 82, '${vote.model} · ${vote.latency_ms} MS'.to_upper(),
		size:   13
		color:  ink_c
		family: black
		align:  align
	)
	for j, line in wrap(vote.why, if w < 240 { 34 } else { 38 }) {
		if j >= 3 {
			break
		}
		text(ctx, tx, y + 100 + j * 15, line, size: 13, color: ink_c, align: align)
	}
}

fn draw_harmonics(ctx &gg.Context, s State, x f32, y f32, w f32, h f32) {
	frame_box(ctx, x, y, w, h, 'HARMONICS', 'シンクロ率')
	if s.view_at == 0 {
		text(ctx, x + w / 2, y + h / 2 - 10, 'NO SIGNAL',
			size:   20
			color:  dim
			family: black
			align:  .center
		)
		return
	}
	v := s.view
	sync_c := if v.sync <= threshold { alert } else { hot }
	glow(ctx, x + 14, y + 26, '${v.sync * 100:.1f}%', size: 46, color: sync_c, family: black)
	seat, jp := match v.seat {
		'pilot' { 'PILOT', '操縦者' }
		'dummy' { 'DUMMY PLUG', 'ダミープラグ' }
		else { 'EMPTY', '空席' }
	}

	text(ctx, x + 14, y + 80, seat,
		size:   22
		color:  if v.seat == 'empty' { dim } else { paper }
		family: black
	)
	text(ctx, x + 18 + measure(ctx, seat, size: 22, family: black), y + 84, jp,
		size:   15
		color:  orange
		family: mincho
	)
	if v.benched {
		ctx.draw_rect_filled(x + 14, y + 108, 74, 18, alert)
		text(ctx, x + 51, y + 109, 'BENCHED',
			size:   14
			color:  pitch
			family: black
			align:  .center
		)
	}
	text(ctx, x + 14, y + 132, 'CORE AUTHORITY ${v.authority:.2f}',
		size:   14
		color:  cyan
		family: black
	)

	gx, gy, gw, gh := x + 204, y + 28, w - 216, h - 40
	for i in 0 .. 5 {
		ctx.draw_rect_filled(gx, gy + gh * f32(i) / 4, gw, 1, umber)
	}
	for i in 0 .. 7 {
		ctx.draw_rect_filled(gx + gw * f32(i) / 6, gy, 1, gh, umber)
	}
	ty := gy + gh * f32(1 - threshold)
	ctx.draw_line_with_config(gx, ty, gx + gw, ty, color: alert, thickness: 1, line_type: .dashed)
	text(ctx, gx + 4, gy - 16, 'SYNC', size: 12, color: hot, family: black)
	text(ctx, gx + 40, gy - 16, 'AUTHORITY', size: 12, color: cyan, family: black)
	text(ctx, gx + gw, gy - 16, '-30 S', size: 12, color: ember, family: black, align: .right)
	step := gw / f32(history - 1)
	n := s.samples.len
	px := fn [gx, gw, step, n] (i int) f32 {
		return gx + gw - f32(n - 1 - i) * step
	}
	py := fn [gy, gh] (v f64) f32 {
		return gy + gh * f32(1 - math.clamp(v, 0.0, 1.0))
	}
	for i in 1 .. n {
		a, b := s.samples[i - 1], s.samples[i]
		stroke(ctx, px(i - 1), py(a.authority), px(i), py(b.authority), 1.5, fade(cyan, 0.8))
	}
	for i in 1 .. n {
		a, b := s.samples[i - 1], s.samples[i]
		stroke(ctx, px(i - 1), py(a.sync), px(i), py(b.sync), 6, fade(hot, 0.22))
		stroke(ctx, px(i - 1), py(a.sync), px(i), py(b.sync), 2, hot)
	}

	// The threshold's label goes over the traces, so the sync trace never runs through it.
	limit := Txt{
		size:   13
		color:  alert
		family: mincho
	}
	line := '絶対境界線 ${threshold * 100:.0f}%'
	lw := measure(ctx, line, limit) + 4
	ctx.draw_rect_filled(gx + gw - 2 - lw, ty - 19, lw, 16, fade(pitch, 0.7))
	text(ctx, gx + gw - 4, ty - 18, line, Txt{
		...limit
		align: .right
	})
}

fn draw_core(ctx &gg.Context, s State, now i64, x f32, y f32, w f32, h f32) {
	frame_box(ctx, x, y, w, h, 'CORE', '')
	if s.view_at > 0 {
		g := s.view.goal
		text(ctx, x + 14, y + 28, 'ACTIVE GOAL', size: 13, color: ember, family: black)
		text(ctx, x + 14, y + 44, g.label().to_upper(), size: 22, color: paper, family: black)
		for j, l in wrap(if g.origin == '' { g.why } else { '${g.origin}: ${g.why}' }, 44) {
			if j >= 2 {
				break
			}
			text(ctx, x + 14, y + 74 + j * 16, l, size: 14, color: dim)
		}
	}

	// The fault strip: one hex per fault the bridge has seen, newest first.
	hx := x + 316
	text(ctx, hx, y + 26, 'FAULTS', size: 13, color: ember, family: black)
	text(ctx, hx + 50, y + 24, '故障',
		size:   15
		color:  if s.faults.len > 0 { alert } else { ember }
		family: mincho
	)
	for i in 0 .. keep {
		cx := hx + 22 + f32(i) * 46
		cy := y + 74
		if i < s.faults.len {
			fresh := now - s.faults[i].at < 2000 && i == 0
			c := if fresh && !on(now, 250, 0.5) { alert_deep } else { alert }
			hexagon(ctx, cx, cy, 23, c)
			hexagon(ctx, cx, cy, 19, pitch)
			hexagon(ctx, cx, cy, 17, c)
			text(ctx, cx, cy - 9, '故障', size: 14, color: pitch, family: mincho, align: .center)
		} else {
			hexagon(ctx, cx, cy, 23, umber)
			hexagon(ctx, cx, cy, 21, ground)
		}
	}
	tx := hx + f32(keep) * 46 + 8
	if s.faults.len == 0 {
		text(ctx, tx, y + 50, 'NOMINAL', size: 20, color: aye, family: black)
		text(ctx, tx, y + 74, 'NO CORE FAULT', size: 13, color: dim, family: black)
	} else {
		f := s.faults[0]
		text(ctx, tx, y + 28, s.mission(f.at), size: 15, color: alert, family: black)
		for j, l in wrap(f.text, 20) {
			if j >= 4 {
				break
			}
			text(ctx, tx, y + 46 + j * 15, l, size: 13, color: paper)
		}
	}
}

fn draw_limit(ctx &gg.Context, s State, now i64, x f32, y f32, w f32, h f32) {
	link := s.link(now)
	left := s.left_ms(now)
	urgent := link == 'depleted' || (link == 'cut' && left < 30000)
	ctx.draw_rect_filled(x, y, w, h, gg.Color{20, 10, 0, 255})
	ctx.draw_rect_empty(x, y, w, h, ember)
	stripe := match true {
		urgent { alert }
		link == 'cut' { orange }
		link == 'lost' { caution }
		else { gg.Color{70, 36, 0, 255} }
	}

	hazard(ctx, x, y, w, 12, stripe, gg.Color{20, 11, 2, 255}, f32(now / 40))
	text(ctx, x + 14, y + 24, '活動限界まで', size: 26, color: timer, family: mincho, sx: 0.85)
	text(ctx, x + 14, y + 58, 'あと', size: 26, color: timer, family: mincho, sx: 0.85)
	text(ctx, x + 14, y + 98, 'ACTIVE TIME', size: 15, color: timer, family: black)
	text(ctx, x + 14, y + 114, 'REMAINING:', size: 15, color: timer, family: black)

	// The clock: ghost segments, then the figure, minutes and seconds large and centiseconds
	// small, as the canon's; red and blinking in the last 30 s of internal power.
	big, small := clock(left)
	dx, dy := x + 142, y + 26
	ghost := gg.Color{52, 26, 0, 255}
	text(ctx, dx, dy, '8:88', size: 88, color: ghost, family: seg)
	bw := measure(ctx, '8:88', size: 88, family: seg)
	text(ctx, dx + bw + 4, dy + 44, ':88', size: 40, color: ghost, family: seg)
	if link !in ['never', 'stale'] && !(urgent && link == 'cut' && !on(now, 330, 0.8)) {
		c := if urgent { alert } else { timer }
		glow(ctx, dx + bw, dy, big, size: 88, color: c, family: seg, align: .right)
		glow(ctx, dx + bw + 4, dy + 44, ':${small}', size: 40, color: c, family: seg)
	}

	// 内部 lights on internal power, 外部 while the cable counts as connected.
	by := y + 152
	for i, name in ['内部', '外部'] {
		lit := (i == 0 && link in ['cut', 'depleted'])
			|| (i == 1 && link in ['live', 'lost', 'awaiting'])
		bx := x + 14 + f32(i) * 96
		if lit {
			ctx.draw_rect_filled(bx, by, 88, 42, if urgent { alert } else { power })
		}
		ctx.draw_rect_empty(bx, by, 88, 42, if lit { power } else { ember })
		text(ctx, bx + 44, by + 6, name,
			size:   28
			color:  if lit { pitch } else { ember }
			family: mincho
			sx:     0.9
			align:  .center
		)
	}
	sx := x + 214
	silence := f64(s.silence(now)) / 1000
	grace := f64(s.view.grace_ms) / 1000
	match link {
		'live' {
			text(ctx, sx, by - 2, 'MAIN ENERGY SUPPLY SYSTEM', size: 16, color: timer, family: black)
			text(ctx, sx, by + 18, 'UMBILICAL CONNECTED · LAST PULSE ${silence:.1f} S',
				size:   13
				color:  dim
				family: black
			)
		}
		'lost' {
			ctx.draw_rect_filled(sx - 4, by - 4, w - 214 - 10, 26,
				blink(now, 330, 0.8, caution, gg.Color{120, 90, 0, 255}))
			text(ctx, sx, by - 2, 'UMBILICAL SIGNAL LOST', size: 19, color: pitch, family: black)
			text(ctx, x + w - 18, by - 3, '警告',
				size:   19
				color:  pitch
				family: mincho
				align:  .right
			)
			text(ctx, sx, by + 26, 'NO PULSE ${silence:.1f} S · CUT AT ${grace:.0f} S',
				size:   14
				color:  caution
				family: black
			)
			if grace > 0 {
				bw2 := w - 214 - 10
				ctx.draw_rect_empty(sx - 4, by + 42, bw2, 6, caution)
				ctx.draw_rect_filled(sx - 4, by + 42, bw2 * f32(math.min(silence / grace, 1.0)), 6,
					caution)
			}
		}
		'awaiting' {
			text(ctx, sx, by - 2, 'AWAITING HQ', size: 18, color: dim, family: black)
			text(ctx, sx, by + 20, 'NO PULSE YET ${silence:.1f} S · CUT AT ${grace:.0f} S',
				size:   13
				color:  dim
				family: black
			)
		}
		'cut' {
			text(ctx, sx, by - 2, 'INTERNAL BATTERY',
				size:   18
				color:  if urgent { alert } else { timer }
				family: black
			)
			text(ctx, sx, by + 20, 'UMBILICAL CABLE CUT · NO QUORUM',
				size:   13
				color:  alert
				family: black
			)
			text(ctx, sx, by + 36, 'NOTHING IRREVERSIBLE WITHOUT HQ',
				size:   13
				color:  dim
				family: black
			)
		}
		'depleted' {
			text(ctx, sx, by - 2, 'ACTIVITY LIMIT REACHED', size: 18, color: alert, family: black)
			text(ctx, sx, by + 20, 'INTERNAL POWER SPENT · UNIT HOLDS',
				size:   13
				color:  alert
				family: black
			)
		}
		else {
			text(ctx, sx, by - 2, 'NO FIELD DATA', size: 18, color: dim, family: black)
		}
	}
}

// Map turns meters in the scene into pixels: k pixels per meter, with the meter point mx, my at
// the pixel ox, oy.
struct Map {
	ox f32
	oy f32
	mx f64
	my f64
	k  f32
}

fn (m Map) px(x f64) f32 {
	return m.ox + f32(x - m.mx) * m.k
}

fn (m Map) py(y f64) f32 {
	return m.oy - f32(y - m.my) * m.k
}

fn draw_scene(ctx &gg.Context, s State, unit string, x f32, y f32, w f32, h f32) {
	frame_box(ctx, x, y, w, h, 'SCENE', '周辺状況')
	ax, ay, aw, ah := x + 8, y + 24, w - 16, h - 24 - 30
	if s.view_at == 0 || s.span.len < 4 {
		text(ctx, x + w / 2, ay + ah / 2 - 10, 'NO SIGNAL',
			size:   20
			color:  dim
			family: black
			align:  .center
		)
		return
	}

	// The scale fits everything the scene has shown, plus a meter around it.
	sw, sh := s.span[2] - s.span[0] + 2, s.span[3] - s.span[1] + 2
	m := Map{
		ox: ax + aw / 2
		oy: ay + ah / 2
		mx: (s.span[0] + s.span[2]) / 2
		my: (s.span[1] + s.span[3]) / 2
		k:  f32(math.min(f64(aw) / sw, f64(ah) / sh))
	}
	ctx.scissor_rect(int(ax), int(ay), int(aw), int(ah))
	x0, x1 := math.floor(m.mx - f64(aw / 2 / m.k)), math.ceil(m.mx + f64(aw / 2 / m.k))
	y0, y1 := math.floor(m.my - f64(ah / 2 / m.k)), math.ceil(m.my + f64(ah / 2 / m.k))
	for gx := x0; gx <= x1; gx += 1 {
		ctx.draw_rect_filled(m.px(gx), ay, 1, ah, umber)
	}
	for gy := y0; gy <= y1; gy += 1 {
		ctx.draw_rect_filled(ax, m.py(gy), aw, 1, umber)
	}
	p := s.view.percept
	mut taken := []Rect{}
	if p.pose.len < 2 {
		ctx.scissor_rect(0, 0, screen_w, screen_h)
		return
	}
	bx, by := m.px(p.pose[0]), m.py(p.pose[1])

	// Range rings around the body, a meter apart, ticked every 30 degrees.
	for r in 1 .. 9 {
		rr := f32(r) * m.k
		ctx.draw_circle_empty(bx, by, rr, fade(ember, if r % 2 == 0 { 0.8 } else { 0.4 }))
		for t in 0 .. 12 {
			a := f64(t) * math.pi / 6
			cs, sn := f32(math.cos(a)), f32(math.sin(a))
			ctx.draw_line(bx + cs * (rr - 4), by + sn * (rr - 4), bx + cs * (rr + 4), by +
				sn * (rr + 4), ember)
		}
		if r % 2 == 0 {
			text(ctx, bx + rr * 0.7071 + 3, by - rr * 0.7071 - 14, '${r} M',
				size:   11
				color:  ember
				family: black
			)
		}
	}
	ctx.draw_rect_filled(bx, ay, 1, ah, fade(ember, 0.5))
	ctx.draw_rect_filled(ax, by, aw, 1, fade(ember, 0.5))

	// The trail, fading with age.
	for i in 1 .. s.trail.len {
		a, b := s.trail[i - 1], s.trail[i]
		stroke(ctx, m.px(a[0]), m.py(a[1]), m.px(b[0]), m.py(b[1]), 2, fade(orange, 0.08 +
			0.6 * f64(i) / f64(s.trail.len)))
	}

	mut nearest := -1.0
	mut human := []f64{}
	for e in p.scene {
		if e.pos.len < 2 {
			continue
		}
		ex, ey := m.px(e.pos[0]), m.py(e.pos[1])
		r := f32(e.r) * m.k
		match e.kind {
			'obstacle' {
				ctx.draw_circle_filled(ex, ey, r, rock)
				ctx.draw_circle_empty(ex, ey, r, ember)
			}
			'beacon' {
				ctx.draw_circle_filled(ex, ey, r, fade(cyan, 0.25))
				ctx.draw_circle_empty(ex, ey, r, cyan)
				ctx.draw_circle_empty(ex, ey, f32(lcl.beacon_reach) * m.k, fade(cyan, 0.5))
			}
			'human' {
				ctx.draw_circle_empty(ex, ey, f32(release_keep) * m.k, fade(alert, 0.45))
				ctx.draw_circle_filled(ex, ey, f32(human_stop) * m.k, fade(alert, 0.12))
				ctx.draw_circle_empty(ex, ey, f32(human_stop) * m.k, fade(alert, 0.8))
				ctx.draw_circle_filled(ex, ey, r, alert)
				d := lcl.dist(p.pose[..2], e.pos[..2])
				if nearest < 0 || d < nearest {
					nearest = d
					human = e.pos[..2].clone()
				}
			}
			else {
				ctx.draw_circle_empty(ex, ey, r, dim)
			}
		}
	}

	g := s.view.goal
	if g.verb == 'goto' && g.target.len >= 2 {
		tx, ty := m.px(g.target[0]), m.py(g.target[1])
		l, gap := f32(7), f32(13)
		for d in [[f32(-1), -1], [f32(1), -1], [f32(-1), 1], [f32(1), 1]] {
			cx, cy := tx + d[0] * gap, ty + d[1] * gap
			ctx.draw_rect_filled(math.min(cx, cx - d[0] * l), cy - 1, l, 2, hot)
			ctx.draw_rect_filled(cx - 1, math.min(cy, cy - d[1] * l), 2, l, hot)
		}
		ctx.draw_rect_filled(tx - 1, ty - 1, 3, 3, hot)
	}

	// The body: a diamond, with its velocity.
	ctx.draw_convex_poly([bx, by - 8, bx + 8, by, bx, by + 8, bx - 8, by], orange)
	if p.vel.len >= 2 {
		stroke(ctx, bx, by, m.px(p.pose[0] + p.vel[0]), m.py(p.pose[1] + p.vel[1]), 2, paper)
	}
	if human.len == 2 {
		hx, hy := m.px(human[0]), m.py(human[1])
		close := nearest < release_keep
		ctx.draw_line_with_config(bx, by, hx, hy,
			color:     if close { alert } else { fade(dim, 0.7) }
			thickness: 1
			line_type: .dotted
		)
	}
	taken << label(ctx, taken, bx, by, 10, unit.to_upper(), orange)
	for e in p.scene {
		if e.pos.len >= 2 {
			taken << label(ctx, taken, m.px(e.pos[0]), m.py(e.pos[1]), f32(e.r) * m.k + 4,
				'${e.kind} ${e.id}'.to_upper(), match e.kind {
				'human' { alert }
				'beacon' { cyan }
				else { dim }
			})
		}
	}

	// A target on a beacon has the beacon's label, and the brackets mark it.
	if g.verb == 'goto' && g.target.len >= 2 && !p.scene.any(it.kind == 'beacon' && it.pos.len >= 2
		&& lcl.dist(it.pos[..2], g.target[..2]) <= it.r) {
		taken << label(ctx, taken, m.px(g.target[0]), m.py(g.target[1]), 16, 'TARGET', hot)
	}
	ctx.scissor_rect(0, 0, screen_w, screen_h)

	mut parts := ['GOAL ${g.label().to_upper()}']
	if g.target.len >= 2 {
		parts << 'TO TARGET ${lcl.dist(p.pose[..2], g.target[..2]):.2f} M'
	}
	if p.payload {
		parts << 'PAYLOAD ABOARD'
	}
	text(ctx, x + 12, y + h - 24, parts.join('  ·  '), size: 14, color: paper, family: black)
	if nearest >= 0 {
		text(ctx, x + w - 12, y + h - 24, 'HUMAN ${nearest:.2f} M',
			size:   14
			color:  if nearest < release_keep { alert } else { paper }
			family: black
			align:  .right
		)
	}
}

// label sets s near the point x, y, off by gap, on the first side where it overlaps nothing in
// taken: right, left, above, below. It returns the box it took.
fn label(ctx &gg.Context, taken []Rect, x f32, y f32, gap f32, s string, c gg.Color) Rect {
	t := Txt{
		size:   12
		color:  c
		family: black
	}
	w, h := measure(ctx, s, t) + 4, f32(14)
	mut spots := [Rect{x + gap, y - h / 2, w, h}, Rect{x - gap - w, y - h / 2, w, h},
		Rect{x - w / 2, y - gap - h, w, h}, Rect{x - w / 2, y + gap, w, h}]
	mut pick := spots[0]
	for r in spots {
		if !taken.any(it.overlaps(r)) {
			pick = r
			break
		}
	}
	ctx.draw_rect_filled(pick.x, pick.y, pick.w, pick.h, fade(pitch, 0.7))
	text(ctx, pick.x + 2, pick.y, s, t)
	return pick
}

fn draw_logs(ctx &gg.Context, s State, x f32, y f32, w f32, h f32) {
	half := (w - 12) / 2
	frame_box(ctx, x, y, half, h, 'ARMOR', '拒否')
	frame_box(ctx, x + half + 12, y, half, h, 'OUTCOMES', '結果')
	if s.refusals.len == 0 {
		text(ctx, x + 12, y + 30, 'NO REFUSAL', size: 14, color: dim, family: black)
	}
	for i, e in s.refusals {
		if i >= 5 {
			break
		}
		ly := y + 28 + f32(i) * 21
		text(ctx, x + 12, ly, s.mission(e.at), size: 13, color: dim, family: black)
		text(ctx, x + 66, ly - 1, '拒否', size: 14, color: alert, family: mincho)
		text(ctx, x + 98, ly, e.text.to_upper(), size: 14, color: alert, family: black)
	}
	ox := x + half + 24
	if s.outcomes.len == 0 {
		text(ctx, ox, y + 30, 'NONE YET', size: 14, color: dim, family: black)
	}
	for i, e in s.outcomes {
		if i >= 5 {
			break
		}
		ly := y + 28 + f32(i) * 21
		text(ctx, ox, ly, s.mission(e.at), size: 13, color: dim, family: black)
		text(ctx, ox + 54, ly, e.text.to_upper(),
			size:   14
			color:  if e.good { aye } else { paper }
			family: black
		)
	}
}

// draw_boot is the boot sequence: the bridge's own facts, then three lines from the show, one
// after another, over a bar that fills for boot_ms.
fn draw_boot(ctx &gg.Context, s State, unit string, at string, now i64) {
	t := now - s.born
	ctx.draw_rect_filled(0, 0, screen_w, screen_h, pitch)
	hazard(ctx, 0, 0, screen_w, 10, orange, gg.Color{20, 11, 2, 255}, f32(t / 30))
	hazard(ctx, 0, screen_h - 10, screen_w, 10, orange, gg.Color{20, 11, 2, 255}, f32(t / 30))
	cx := f32(screen_w / 2)
	glow(ctx, cx, 150, 'GEHIRN', size: 96, color: orange, family: mincho, sx: 0.8, align: .center)
	text(ctx, cx, 270, '発令所  OPERATIONS BRIDGE',
		size:   24
		color:  orange
		family: black
		align:  .center
	)
	lines := [
		['WATCH STREAMS', 'LISTENING ${at}'.to_upper()],
		['UNIT', unit.to_upper()],
		['A10神経接続', '異常なし'],
		['ハーモニクス', '全て正常値'],
		['ボーダーライン', 'クリアー'],
	]
	for i, l in lines {
		if t < 300 + i64(i) * 380 {
			break
		}
		ly := f32(350 + i * 40)
		text(ctx, 380, ly, l[0], size: 22, color: hot, family: mincho)
		lw := measure(ctx, l[0], size: 22, family: mincho)
		vw := measure(ctx, l[1], size: 22, family: mincho)
		ctx.draw_line_with_config(380 + lw + 12, ly + 18, 900 - vw - 12, ly + 18,
			color:     ember
			thickness: 2
			line_type: .dotted
		)
		text(ctx, 900, ly, l[1], size: 22, color: aye, family: mincho, align: .right)
	}
	ctx.draw_rect_empty(380, 580, 520, 10, ember)
	ctx.draw_rect_filled(380, 580, 520 * f32(math.min(f64(t) / boot_ms, 1.0)), 10, orange)
	text(ctx, cx, 680, fan_line, size: 18, color: paper, family: black, align: .center)
	text(ctx, cx, 706, 'THE BRIDGE ONLY WATCHES. IT HOLDS NO KEY THAT APPROVES OR PULSES.',
		size:   14
		color:  dim
		family: black
		align:  .center
	)
}

// draw_emergency is the EMERGENCY overlay for the moment the cable is cut: hexagons spreading
// from the center ring by ring, then fading, with the cut spelled out across the middle.
fn draw_emergency(ctx &gg.Context, s State, now i64) {
	t := now - s.cut_at
	a := if t > emergency_ms - 400 { f64(emergency_ms - t) / 400 } else { 1.0 }
	r := f32(52)
	dx := r * f32(math.sqrt(3))
	cols, rows := int(screen_w / dx) + 2, int(screen_h / (r * 1.5)) + 2
	mut cells := [][]f32{}
	for row in 0 .. rows {
		for col in 0 .. cols {
			ring := math.max(math.abs(col - cols / 2), math.abs(row - rows / 2))
			if t >= i64(ring) * 30 {
				cells << [f32(col) * dx + if row % 2 == 1 { dx / 2 } else { 0 }, f32(row) * r * 1.5,
					f32((now / 130 + i64(row * 3 + col * 5)) % 7)]
			}
		}
	}

	// Every hexagon first and every label after, so each kind merges into one draw call.
	for c in cells {
		lit := fade(if c[2] != 0 { alert } else { alert_deep }, 0.85 * a)
		hexagon(ctx, c[0], c[1], r - 2, lit)
		hexagon(ctx, c[0], c[1], r - 7, fade(pitch, 0.85 * a))
		hexagon(ctx, c[0], c[1], r - 10, lit)
	}
	for c in cells {
		text(ctx, c[0], c[1] - 8, 'EMERGENCY',
			size:   14
			color:  fade(pitch, a)
			family: black
			align:  .center
		)
	}
	ctx.draw_rect_filled(0, 318, screen_w, 164, fade(pitch, 0.9 * a))
	hazard(ctx, 0, 318, screen_w, 10, fade(alert, a), fade(alert_deep, a), f32(now / 20))
	hazard(ctx, 0, 472, screen_w, 10, fade(alert, a), fade(alert_deep, a), f32(now / 20))
	glow(ctx, screen_w / 2, 334, 'EMERGENCY',
		size:   64
		color:  fade(alert, a)
		family: black
		align:  .center
	)
	text(ctx, screen_w / 2, 404, '外部電源切断  内部電源に切り替え',
		size:   28
		color:  fade(paper, a)
		family: mincho
		align:  .center
	)
	text(ctx, screen_w / 2, 442, 'UMBILICAL CABLE CUT · RUNNING ON INTERNAL POWER',
		size:   18
		color:  fade(timer, a)
		family: black
		align:  .center
	)
}
