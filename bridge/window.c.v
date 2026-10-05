module main

import sokol.sapp

$if macos {
	#include "@VMODROOT/bridge/window_darwin.m"

	fn C.bridge_dress_window(window voidptr)
}

// dress readies the borderless window once it exists. On macOS it lets it take the keyboard and
// move when dragged anywhere (window_darwin.m). On Linux X11 sokol already asked the window manager,
// through Motif hints, for no decorations; the window manager decides about focus and moving, which
// most offer as Alt and drag.
fn dress() {
	$if macos {
		C.bridge_dress_window(sapp.macos_get_window())
	}
}
