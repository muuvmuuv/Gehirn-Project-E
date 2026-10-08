// gehirn-bridge: the operator's view of one unit, in the look of NERV's command center
// (ADR-0005). It listens on BRIDGE_ENDPOINT for the watch streams that HQ and the field unit seal
// under WATCH_KEY, and draws MAGI, the core, the seat, the umbilical and the scene with gg. It
// declares no publisher and holds no key that approves or pulses, so closing it changes nothing.
module main

import gg
import os
import stbi
import strconv
import lcl
import wire
import zenoh

// cond_ttf, black_ttf, mincho_ttf and seg_ttf are the bridge's own fonts, built into the binary so
// no machine needs one installed, all under the SIL Open Font License beside them in bridge/fonts:
// Barlow Condensed for Latin, Zen Old Mincho Black cut to ASCII and the Japanese that bridge/*.v
// draws (bridge/fonts/README.md), and DSEG7 for the umbilical's clock. Static faces only, since
// fontstash draws a variable font at its default weight, and one face per file, since it reads no
// .ttc collection.
const cond_ttf = $embed_file('fonts/BarlowCondensed-SemiBold.ttf')
const black_ttf = $embed_file('fonts/BarlowCondensed-Black.ttf')
const mincho_ttf = $embed_file('fonts/ZenOldMincho-Black-subset.ttf')
const seg_ttf = $embed_file('fonts/DSEG7Classic-BoldItalic.ttf')

// black, mincho and seg are the names under which init registers the bundled faces, for
// TextCfg.family. The base face, Barlow Condensed SemiBold, needs no name.
const black = 'barlow-black'
const mincho = 'zen-old-mincho'
const seg = 'dseg7'

// fonts are where macOS keeps Arial Unicode, the last fallback for glyphs the bundled fonts lack,
// such as Japanese in a model's why.
// ponytail: macOS paths only; elsewhere VUI_FONT names such a font, for example Noto Sans CJK.
const fonts = ['/Library/Fonts/Arial Unicode.ttf',
	'/System/Library/Fonts/Supplemental/Arial Unicode.ttf']!

// App is the bridge: the unit it shows and where it listens, its ports, its opener, what it
// shows, and its icons with the contacts the Dock icon shows. frame draws it 60 times a second.
@[heap]
struct App {
	unit  string
	at    string
	icons Icons
mut:
	gg     &gg.Context = unsafe { nil }
	ports  wire.BridgePorts
	opener wire.Opener
	state  State
	docked [3]gg.Color = [orange, orange, orange]!
	script []Step // BRIDGE_MOUSE, in a gg_record build only
}

// Step is one step of BRIDGE_MOUSE: the event on_event gets once at milliseconds have passed since
// the bridge started.
struct Step {
	at i64
	e  gg.Event
}

fn main() {
	unit := env('UNIT_ID', 'eva01') // main.v unit_id has the same default
	wire.check_unit(unit) or {
		eprintln('gehirn-bridge: UNIT_ID is ${err.msg()}')
		exit(2)
	}
	key := wire.decode_key(os.getenv('WATCH_KEY')) or {
		eprintln('gehirn-bridge: WATCH_KEY is ${err.msg()}')
		exit(2)
	}
	at := env('BRIDGE_ENDPOINT', 'tcp/127.0.0.1:7448') // main.v load_config has the same default
	session := zenoh.open(zenoh.Config{ listen: [at] }) or {
		eprintln('gehirn-bridge: cannot listen on BRIDGE_ENDPOINT; ${err.msg()}')
		exit(1)
	}
	mut app := &App{
		unit:   unit
		at:     at
		icons:  load_icons()
		state:  State{
			born: lcl.now_ms()
		}
		ports:  wire.bridge_ports(session, unit) or {
			eprintln('gehirn-bridge: ${err.msg()}')
			exit(1)
		}
		opener: wire.new_opener(key, unit) or {
			eprintln('gehirn-bridge: ${err.msg()}')
			exit(1)
		}
	}
	app.gg = gg.new_context(
		width:             screen_w
		height:            screen_h
		window_title:      'gehirn bridge ${unit}'
		icon:              window_icon(app.icons)
		bg_color:          ink
		borderless_window: true
		resizable:         false
		init_fn:           init
		frame_fn:          frame
		event_fn:          on_event
		user_data:         app
		font_bytes_normal: cond_ttf.to_bytes()
		font_bytes_bold:   black_ttf.to_bytes()
	)

	// scripts/record.sh has gg_record write every frame as a PNG inside the frame loop, which on a
	// Retina screen took 120 ms at 2560 by 1600 against 28 ms at 1280 by 800, and 18 ms without
	// stbi's search for the best filter of each row, so it passes bridge_1x to draw at 1x and
	// filter no row (PLAN, Known issue 24). A build without it keeps the display's scale, so its
	// frames show the 2x path, such as text's anchor. gg.new_context always asks sokol for high
	// DPI.
	$if bridge_1x ? {
		app.gg.window.high_dpi = false
		stbi.write_force_png_filter(0)
	}
	$if gg_record ? {
		app.script = mouse_script(os.getenv('BRIDGE_MOUSE')) or {
			eprintln('gehirn-bridge: BRIDGE_MOUSE has ${err.msg()}')
			exit(2)
		}
	}
	app.gg.run()
}

fn env(key string, fallback string) string {
	val := os.getenv(key)
	return if val == '' { fallback } else { val }
}

// init readies the borderless window (window.c.v), then names the bundled faces for
// TextCfg.family and chains the mincho, then font(), behind each, so a glyph one face lacks comes
// from the next. It runs before the first frame, since fontstash caches a missing glyph as missing.
fn init(mut app App) {
	dress()
	mut ft := app.gg.ft
	for name, data in {
		black:  black_ttf
		mincho: mincho_ttf
		seg:    seg_ttf
	} {
		ft.fonts_map[name] = ft.fons.add_font_mem(name, data.to_bytes().clone(), true)
	}
	mut chain := [ft.fonts_map[mincho]]
	extra := font()
	if extra != '' {
		bytes := os.read_bytes(extra) or { []u8{} }
		if bytes.len > 0 {
			chain << ft.fons.add_font_mem('extra', bytes, true)
		}
	}
	for base in [ft.font_normal, ft.font_bold, ft.fonts_map[black], ft.fonts_map[mincho]] {
		for fallback in chain {
			if fallback != base {
				ft.fons.add_fallback_font(base, fallback)
			}
		}
	}
}

// on_event quits on Esc, as Cmd-Q does, since the borderless window has no close button. It exits
// instead of calling gg's quit, which on macOS asks the window to close as its close button would,
// and AppKit only beeps at a window without one. The bridge only watches, so quitting changes
// nothing. It also keeps the cursor for State.hover and hands a left click to State.click, which
// change only what the bridge shows.
fn on_event(e &gg.Event, mut app App) {
	match e.typ {
		.key_down {
			if e.key_code == .escape {
				exit(0)
			}
		}
		.mouse_move {
			app.state.cursor = [e.mouse_x, e.mouse_y]
		}
		.mouse_leave {
			app.state.cursor = []
		}
		.mouse_down {
			if e.mouse_button == .left {
				app.state.click(e.mouse_x, e.mouse_y)
			}
		}
		else {}
	}
}

// mouse_script reads BRIDGE_MOUSE, the mouse a gg_record build replays through on_event, since a
// frame saved without a hand on the mouse would show no hover (CONTRIBUTING.md, V 0.5.2 rule 6):
// steps apart by spaces, each x,y to move there in window pixels, click to click where it last
// moved, or out to leave the window, then @ and the milliseconds since the bridge started, as in
// `900,420@9000 click@9500 out@12000`.
fn mouse_script(spec string) ![]Step {
	mut steps := []Step{}
	mut x, mut y := f32(0), f32(0)
	for word in spec.fields() {
		at := strconv.atoi(word.all_after('@')) or {
			return error('no time in ${lcl.quoted(word)}')
		}
		what := word.all_before('@')
		xy := what.split(',')
		if what == 'click' {
			steps << Step{at, gg.Event{
				typ:          .mouse_down
				mouse_button: .left
				mouse_x:      x
				mouse_y:      y
			}}
		} else if what == 'out' {
			steps << Step{at, gg.Event{
				typ: .mouse_leave
			}}
		} else if xy.len == 2 {
			x = f32(strconv.atoi(xy[0]) or { return error('no x in ${lcl.quoted(word)}') })
			y = f32(strconv.atoi(xy[1]) or { return error('no y in ${lcl.quoted(word)}') })
			steps << Step{at, gg.Event{
				typ:     .mouse_move
				mouse_x: x
				mouse_y: y
			}}
		} else {
			return error('no step in ${lcl.quoted(word)}')
		}
	}
	return steps
}

// font is VUI_FONT, else the first of fonts this host has, else nothing.
fn font() string {
	set := os.getenv('VUI_FONT')
	if set != '' {
		return set
	}
	for f in fonts {
		if os.is_file(f) {
			return f
		}
	}
	return ''
}

// frame takes every message that arrived since the last frame, then draws.
fn frame(mut app App) {
	now := lcl.now_ms()
	for {
		s := app.ports.field.try_recv() or { break }
		v := app.opener.view(s) or {
			app.state.dropped = err.msg()
			continue
		}
		app.state.take_view(v, now)
	}
	for {
		s := app.ports.hq.try_recv() or { break }
		e := app.opener.event(s) or {
			app.state.dropped = err.msg()
			continue
		}
		app.state.take_event(e, now)
	}
	$if gg_record ? {
		for app.script.len > 0 && now - app.state.born >= app.script[0].at {
			e := app.script[0].e
			app.script.delete(0)
			on_event(&e, mut app)
		}
	}
	app.show_votes(now)
	app.gg.begin()
	draw(app.gg, app.state, app.unit, app.at, now)

	// gg uploads glyphs new to fontstash's atlas only as the next frame begins, so a string drawn
	// for the first time would show blanks for a frame; the EMERGENCY overlay is nearly all new.
	app.gg.ft.flush()
	app.gg.end()
}
