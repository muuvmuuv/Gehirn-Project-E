#!/usr/bin/env python3
"""Render a caption in capitals as a binary PPM image, for ffmpeg to overlay on a video.

`just demo-record` marks the stretch it speeds up with one, because ffmpeg builds without
drawtext, Homebrew's among them, cannot draw text:

    python3 tools/caption.py "40 S GRACE AT 8X" > caption.ppm
"""

import sys

# 5 by 7 pixel glyphs, one int per row, the leftmost pixel in bit 4.
# ponytail: only the characters of demo-record's caption; another caption adds its glyphs here.
GLYPHS = {
    " ": (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00),
    "0": (0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E),
    "4": (0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02),
    "8": (0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E),
    "A": (0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11),
    "C": (0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E),
    "E": (0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F),
    "G": (0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F),
    "R": (0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11),
    "S": (0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E),
    "T": (0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04),
    "X": (0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11),
}
INK = bytes((255, 140, 26))  # bridge/draw.v amber
GROUND = bytes((10, 10, 12))  # bridge/draw.v ink


def render(text: str, scale: int = 4, pad: int = 2) -> bytes:
    """Return text as a binary PPM, pad glyph pixels of ground around it, every pixel scale wide.

    Raises ValueError for a character without a glyph.
    """
    missing = sorted(set(text) - GLYPHS.keys())
    if missing:
        raise ValueError(f"caption: no glyph for {''.join(missing)!r}")
    w, h = len(text) * 6 - 1 + 2 * pad, 7 + 2 * pad
    on = [[False] * w for _ in range(h)]
    for i, c in enumerate(text):
        for y, row in enumerate(GLYPHS[c]):
            for x in range(5):
                on[pad + y][pad + i * 6 + x] = bool(row >> (4 - x) & 1)
    out = bytearray(f"P6\n{w * scale} {h * scale}\n255\n".encode())
    for row in on:
        out += b"".join((INK if px else GROUND) * scale for px in row) * scale
    return bytes(out)


def main() -> None:
    try:
        sys.stdout.buffer.write(render(" ".join(sys.argv[1:])))
    except ValueError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main()
