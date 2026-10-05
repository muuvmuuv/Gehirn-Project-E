module main

import gg
import math
import stbi

// small_png and dock_png are the bridge's icons, gehirn's mark (docs/brand.md): 32 px on an ink
// tile for a window manager's title bar and task bar on Linux, and 128 px on an ink plate with a
// macOS icon's margins for the Dock, where sokol picks the image closest to the Dock tile's 128
// points. docs/brand.md gives the tile, the plate and the mark's box each is rendered with.
const small_png = $embed_file('icons/icon-32.png')
const dock_png = $embed_file('icons/icon-128.png')

// Icons are the bridge's icons as RGBA pixels, which sokol takes as they are: the small one and
// the Dock's, whose contacts show_votes recolors.
struct Icons {
	small []u8
	dock  []u8
}

// load_icons decodes the embedded icons, or returns none, which leaves sokol's default icon.
fn load_icons() Icons {
	return Icons{
		small: rgba(small_png.data(), small_png.len, 32) or { return Icons{} }
		dock:  rgba(dock_png.data(), dock_png.len, 128) or { return Icons{} }
	}
}

// rgba decodes a size by size PNG of len bytes at data into RGBA pixels.
fn rgba(data &u8, len int, size int) ![]u8 {
	img := stbi.load_from_memory(data, len, desired_channels: 4)!
	defer {
		img.free()
	}
	if img.width != size || img.height != size {
		return error('icon: ${img.width} by ${img.height} px, not ${size}')
	}
	return unsafe { img.data.vbytes(size * size * 4) }.clone()
}

// show_votes puts each contact's state (State.contact) on both window icons when one changes:
// steady rather than flickering while a unit deliberates or faults, and back to orange as soon as
// a ballot starts to fade, so the icons change only as votes open, ballots land and their hold
// after the verdict ends.
fn (mut a App) show_votes(now i64) {
	if a.icons.dock.len == 0 {
		return
	}
	mut colors := [3]gg.Color{}
	for i, unit in units {
		state, faded := a.state.contact(unit, now)
		colors[i] = if faded > 0 { orange } else { vote_color(state) }
	}
	if colors == a.docked {
		return
	}
	a.docked = colors
	show_icon(Icons{
		small: recolor(a.icons.small, 32, colors)
		dock:  recolor(a.icons.dock, 128, colors)
	})
}

// recolor is the size by size RGBA icon px with the orange of each contact turned to its color in
// colors, in the order of units. The mark is centered on the icon, and a pixel belongs to the
// contact whose direction from the center is nearest its own. A pixel keeps as much of the new
// color as it held of orange over ink, so the contacts' edges stay smooth; the ring and the
// plate hold almost none and stay as they are.
fn recolor(px []u8, size int, colors [3]gg.Color) []u8 {
	mut out := px.clone()
	c := f64(size) / 2
	for y in 0 .. size {
		for x in 0 .. size {
			i := (y * size + x) * 4

			// Orange is 255, 141, 0 and ink 4, 4, 6, so red minus blue runs from -2 on ink to 255
			// on orange; paper, 236, 232, 225, gives 11.
			t := (f64(px[i]) - f64(px[i + 2]) + 2) / 257
			if t < 0.2 {
				continue
			}
			mut best, mut near := 0, -math.max_f64
			for k, p in contacts {
				d := (f64(x) + 0.5 - c) * (p[0] - 7) + (f64(y) + 0.5 - c) * (p[1] - 7)
				if d > near {
					best, near = k, d
				}
			}
			to := colors[best]
			out[i] = u8(math.round(f64(ink.r) + (f64(to.r) - f64(ink.r)) * t))
			out[i + 1] = u8(math.round(f64(ink.g) + (f64(to.g) - f64(ink.g)) * t))
			out[i + 2] = u8(math.round(f64(ink.b) + (f64(to.b) - f64(ink.b)) * t))
		}
	}
	return out
}
