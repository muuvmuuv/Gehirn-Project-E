#!/usr/bin/env python3
"""Self check for caption.render: python3 tools/test_caption.py"""

from pathlib import Path

from caption import GROUND, INK, render

img = render("X4", scale=2, pad=1)
head, _, px = img.partition(b"255\n")
assert head == b"P6\n26 18\n", head
assert len(px) == 26 * 18 * 3, len(px)


def at(x: int, y: int) -> bytes:
    return px[(y * 26 + x) * 3:(y * 26 + x) * 3 + 3]


assert at(0, 0) == GROUND  # the pad
assert at(2, 2) == INK and at(3, 3) == INK  # X's top left pixel, two by two
assert at(4, 2) == GROUND  # X's second pixel in its top row is off
assert at(2 + 6 * 2, 2) == GROUND and at(2 + 9 * 2, 2) == INK  # 4's top row: only bit 1

try:
    render("x")
    raise AssertionError("a lowercase x has no glyph")
except ValueError as e:
    assert "'x'" in str(e), e

draw = (Path(__file__).parent.parent / "bridge" / "draw.v").read_text()
for name, rgb in (("orange", INK), ("ink", GROUND)):
    assert f"const {name} = gg.Color{{{', '.join(map(str, rgb))}, 255}}" in draw, f"bridge/draw.v {name}"

print("caption: ok")
