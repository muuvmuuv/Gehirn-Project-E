module main

import gg
import math

// at is the color of px's pixel x, y on a size wide icon.
fn at(px []u8, size int, x int, y int) gg.Color {
	i := (y * size + x) * 4
	return gg.Color{px[i], px[i + 1], px[i + 2], px[i + 3]}
}

// IconCase is one of the bridge's icons with the place of the mark's grid on it, which follows
// from the mark's box in docs/brand.md's table of icons.
struct IconCase {
	px   []u8
	size int
	at   f32 // where the mark's 16 unit grid starts on the icon, in px
	u    f32 // px a unit
}

fn test_recolor() {
	icons := load_icons()
	assert icons.small.len == 32 * 32 * 4
	assert icons.dock.len == 128 * 128 * 4
	for c in [IconCase{icons.small, 32, 0, 2}, IconCase{icons.dock, 128, 28, 4.5}] {
		same := recolor(c.px, c.size, [orange, orange, orange]!)
		mut drift := 0
		for i, v in c.px {
			drift = math.max(drift, math.abs(int(v) - int(same[i])))
		}
		assert drift <= 1, '${c.size} px: orange contacts come back as they were'

		// Each contact's center lies at its corner plus one unit, the ring's top runs from 1 to
		// 3 units down and the mark's center is ink.
		grid := fn [c] (gx f32, gy f32) (int, int) {
			return int(c.at + gx * c.u), int(c.at + gy * c.u)
		}
		out := recolor(c.px, c.size, [aye, alert, alert_deep]!)
		for k, want in [aye, alert, alert_deep] {
			x, y := grid(contacts[k][0] + 1, contacts[k][1] + 1)
			assert at(c.px, c.size, x, y) == orange, '${c.size} px: ${units[k]}'
			assert at(out, c.size, x, y) == want, '${c.size} px: ${units[k]}'
		}
		rx, ry := grid(8, 2)
		assert at(out, c.size, rx, ry) == at(c.px, c.size, rx, ry), '${c.size} px: the ring stays'
		cx, cy := grid(8, 8)
		assert at(out, c.size, cx, cy) == at(c.px, c.size, cx, cy), '${c.size} px: the center stays'
	}
}
