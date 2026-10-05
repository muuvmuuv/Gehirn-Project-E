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

// window_icon is the icon sokol sets as the window opens: both of icons, from which macOS takes
// the one nearest the Dock tile's size and X11 hands both to the window manager. Without icons
// sokol keeps its default.
fn window_icon(icons Icons) sapp.IconDesc {
	if icons.dock.len == 0 {
		return sapp.IconDesc{}
	}
	return icon_desc([image(icons.small, 32), image(icons.dock, 128)])
}

// show_icon makes icons the window's icons at once, both of them, as window_icon describes them:
// the Dock tile on macOS, the window manager's icons on Linux, where sokol replaces every image it
// set before. sokol copies the pixels before it returns.
fn show_icon(icons Icons) {
	desc := window_icon(icons)
	C.sapp_set_icon(&desc)
}

// icon_desc is sokol's icon description holding images, at most the 8 it takes.
fn icon_desc(images []sapp.ImageDesc) sapp.IconDesc {
	mut all := [8]sapp.ImageDesc{}
	for i, im in images {
		all[i] = im
	}
	return sapp.IconDesc{
		images: all
	}
}

// image describes px, size by size RGBA, to sokol, which reads the pixels where they lie.
fn image(px []u8, size int) sapp.ImageDesc {
	return sapp.ImageDesc{
		width:  size
		height: size
		pixels: sapp.Range{
			ptr:  px.data
			size: usize(px.len)
		}
	}
}
