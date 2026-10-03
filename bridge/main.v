// gehirn-bridge: the operator's view of one unit, in the look of NERV's command center
// (ADR-0005). It listens on BRIDGE_ENDPOINT for the watch streams that HQ and the field unit seal
// under WATCH_KEY, and draws MAGI, the core, the seat, the umbilical and the scene with gg. It
// declares no publisher and holds no key that approves or pulses, so closing it changes nothing.
module main

import gg
import os
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

// App is the bridge: its ports, its opener and what it shows. frame draws it 60 times a second.
@[heap]
struct App {
	unit string
mut:
	gg     &gg.Context = unsafe { nil }
	ports  wire.BridgePorts
	opener wire.Opener
	state  State
}

fn main() {
	unit := env('UNIT_ID', 'eva01')
	wire.check_unit(unit) or {
		eprintln('gehirn-bridge: UNIT_ID is ${err.msg()}')
		exit(2)
	}
	key := wire.decode_key(os.getenv('WATCH_KEY')) or {
		eprintln('gehirn-bridge: WATCH_KEY is ${err.msg()}')
		exit(2)
	}
	at := env('BRIDGE_ENDPOINT', 'tcp/127.0.0.1:7448')
	session := zenoh.open(zenoh.Config{ listen: [at] }) or {
		eprintln('gehirn-bridge: cannot listen on BRIDGE_ENDPOINT; ${err.msg()}')
		exit(1)
	}
	mut app := &App{
		unit:   unit
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
		width:             1280
		height:            800
		window_title:      'gehirn bridge ${unit}'
		bg_color:          ink
		init_fn:           init
		frame_fn:          frame
		user_data:         app
		font_bytes_normal: cond_ttf.to_bytes()
		font_bytes_bold:   black_ttf.to_bytes()
	)
	app.gg.run()
}

fn env(key string, fallback string) string {
	val := os.getenv(key)
	return if val == '' { fallback } else { val }
}

// init names the bundled faces for TextCfg.family and chains the mincho, then font(), behind each,
// so a glyph one face lacks comes from the next. It runs before the first frame, since fontstash
// caches a missing glyph as missing.
fn init(mut app App) {
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
	app.gg.begin()
	draw(app.gg, app.state, app.unit, now)
	app.gg.end()
}
