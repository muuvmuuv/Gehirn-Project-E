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

// fonts are where macOS keeps a font with both Latin and CJK glyphs, for 可決, 否決 and 故障.
// fontstash reads one face per file, so a .ttc collection such as Hiragino does not do.
// ponytail: macOS paths only; a Linux image sets VUI_FONT to a CJK font such as Noto Sans CJK.
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
		width:        1280
		height:       800
		window_title: 'gehirn bridge ${unit}'
		bg_color:     ink
		frame_fn:     frame
		user_data:    app
		font_path:    font()
	)
	app.gg.run()
}

fn env(key string, fallback string) string {
	val := os.getenv(key)
	return if val == '' { fallback } else { val }
}

// font is VUI_FONT, else the first of fonts this host has, else gg's own choice, which may lack
// CJK glyphs.
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
