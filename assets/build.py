# /// script
# requires-python = ">=3.11"
# dependencies = ["fonttools==4.66.0", "pillow==12.3.0"]
# ///
"""Renders gehirn's brand raster files from the SVG masters in assets/brand.

    just assets
    uv run --script assets/build.py

It writes the website's favicon set and manifest icons into website/, the bridge's window icons
into bridge/icons and the social card into assets/brand/social.png and website/social.png, by
the numbers of docs/brand.md, Rebuilding them, and needs rsvg-convert. It is a design time
generator, not a tool: nothing in the checks, the missions or the runtime runs it
(CONTRIBUTING.md, Python tools 2).
"""

import io
import re
import struct
import subprocess
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MARK = (ROOT / "assets/brand/mark.svg").read_text()
LOCKUP = (ROOT / "assets/brand/lockup-dark.svg").read_text()
BLACK = ROOT / "bridge/fonts/BarlowCondensed-Black.ttf"
SEMI = ROOT / "bridge/fonts/BarlowCondensed-SemiBold.ttf"

# mark.svg holds the ring's path, then the contacts', and its style sets them in ink and deep
# orange, then in paper and orange for a dark scheme. Every icon is the dark scheme's mark on ink.
RING, CONTACTS = re.findall(r' d="([^"]+)"', MARK)
INK, _, PAPER, ORANGE = re.findall(r"#[0-9a-f]{6}", MARK)

# Each icon: file, size, the ink square and its corner radius, the mark's box, and the colors it
# is quantized to. docs/brand.md's table of icons gives the same numbers, and
# bridge/icon_test.v finds the contacts on the bridge's two by their boxes.
ICONS = [
    ("website/favicon-96x96.png", 96, 96, 18, 96, 64),
    ("website/apple-touch-icon.png", 180, 180, 0, 128, 64),
    ("website/icon-192.png", 192, 192, 36, 144, 64),
    ("website/icon-512.png", 512, 512, 96, 384, 64),
    ("website/icon-maskable-512.png", 512, 512, 0, 400, 64),
    ("bridge/icons/icon-32.png", 32, 32, 6, 32, None),
    ("bridge/icons/icon-128.png", 128, 104, 23, 72, None),
]


def svg(w: float, h: float, body: str, x: float = 0, y: float = 0) -> str:
    """An SVG document of body with the view box x, y, w, h."""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x:g} {y:g} {w:g} {h:g}"><title>gehirn</title>{body}</svg>'


def render(doc: str, w: int, h: int, colors: int | None = None) -> bytes:
    """doc as a w by h PNG from rsvg-convert, re-saved by Pillow as small as it goes: quantized to
    colors without dithering when given, else optimized RGBA. Pillow writes no time or text chunk,
    so the same doc and rsvg-convert give the same bytes."""
    png = subprocess.run(
        ["rsvg-convert", "-w", str(w), "-h", str(h)], input=doc.encode(), capture_output=True, check=True
    ).stdout
    im = Image.open(io.BytesIO(png))
    if colors:
        im = im.convert("RGBA").quantize(colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    out = io.BytesIO()
    im.save(out, "PNG", optimize=True)
    return out.getvalue()


def tile(size: int, square: int, rx: float, box: int) -> str:
    """An icon size px wide: an ink square with corners rx centered on it, transparent around a
    square smaller than size as a macOS icon's plate is, under the mark scaled to box px."""
    o, m = (size - square) / 2, (size - box) / 2
    plate = f'<rect x="{o:g}" y="{o:g}" width="{square:g}" height="{square:g}" rx="{rx:g}" fill="{INK}"/>'
    mark = (
        f'<g transform="translate({m:g} {m:g}) scale({box / 16:g})">'
        f'<path fill="{PAPER}" fill-rule="evenodd" d="{RING}"/><path fill="{ORANGE}" d="{CONTACTS}"/></g>'
    )
    return svg(size, size, plate + mark)


def ico(pngs: list[bytes]) -> bytes:
    """A .ico holding each PNG as is, 32 bits a pixel, which every browser since IE 11 reads."""
    head = struct.pack("<HHH", 0, 1, len(pngs))
    off = 6 + 16 * len(pngs)
    entries = b""
    for d in pngs:
        w, h = Image.open(io.BytesIO(d)).size
        entries += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(d), off)
        off += len(d)
    return head + entries + b"".join(pngs)


_fonts: dict[Path, TTFont] = {}


def outline(font: Path, text: str, size: float, x: float, base: float, track: float = 0.0) -> tuple[str, tuple]:
    """text set in font at size px from x on the base line base, track em after each glyph with
    ink, as path data and its ink box (x0, y0, x1, y1)."""
    f = _fonts.setdefault(font, TTFont(font))
    gs, cmap, hmtx = f.getGlyphSet(), f.getBestCmap(), f["hmtx"]
    k = size / f["head"].unitsPerEm
    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
    box = BoundsPen(gs)
    for ch in text:
        g = cmap[ord(ch)]
        ink = BoundsPen(gs)
        gs[g].draw(ink)
        t = (k, 0, 0, -k, x, base)
        gs[g].draw(TransformPen(pen, t))
        gs[g].draw(TransformPen(box, t))
        x += hmtx[g][0] * k + (track * size if ink.bounds else 0)
    return pen.getCommands(), box.bounds


def wrap(text: str, font: Path, size: float, width: float) -> list[str]:
    """text broken into lines whose ink fits width px."""
    lines, line = [], ""
    for w in text.split():
        t = (line + " " + w).strip()
        if outline(font, t, size, 0, 0)[1][2] > width and line:
            lines.append(line)
            line = w
        else:
            line = t
    return lines + [line]


def hazard(y: float, w: float, h: float, clip: str) -> str:
    """A band h px high across w px at y, striped at 45 degrees with stripes as wide as it is high."""
    stripes = "".join(f"M{i:g} {y:g}h{h:g}l{-h:g} {h:g}h{-h:g}z" for i in range(-2 * h, w + h, 2 * h))
    return (
        f'<clipPath id="{clip}"><rect x="0" y="{y}" width="{w}" height="{h}"/></clipPath>'
        f'<rect x="0" y="{y}" width="{w}" height="{h}" fill="#140B02"/>'
        f'<path clip-path="url(#{clip})" fill="#3D2200" d="{stripes}"/>'
    )


def social() -> str:
    """The 1280 by 640 card: the fan project line under the top band, then lockup-dark.svg at three
    times its size and the README's first sentence, centered between that line and the bottom band,
    which leaves the bottom left corner, where X lays its domain label, plain."""
    W, H, X, band = 1280, 640, 96, 12
    k, size, lead = 3.0, 40, 52
    # bridge/draw.v's fan_line and the paragraph under README.md's title, which the card copies.
    fan = re.search(r"^const fan_line = '(.+)'$", (ROOT / "bridge/draw.v").read_text(), re.M).group(1)
    sentence = (ROOT / "README.md").read_text().split("\n# gehirn\n\n", 1)[1].split("\n", 1)[0]
    lx, ly, _, lh = map(float, re.search(r'viewBox="([^"]+)"', LOCKUP).group(1).split())
    inner = LOCKUP.split("</title>", 1)[1].rsplit("</svg>", 1)[0]
    body = f'<rect width="{W}" height="{H}" fill="{INK}"/>' + hazard(0, W, band, "b") + hazard(H - band, W, band, "c")
    body += f'<path fill="{PAPER}" d="{outline(BLACK, fan, 34, X, 72, 0.06)[0]}"/>'
    lines = wrap(sentence, SEMI, size, W - 2 * X)
    block = lh * k + 72 + (len(lines) - 1) * lead + 8
    top = 96 + (H - band - 56 - 96 - block) / 2
    body += f'<g transform="translate({X - lx * k:g} {top - ly * k:g}) scale({k})">{inner}</g>'
    y = top + lh * k + 72
    for line in lines:
        body += f'<path fill="{PAPER}" d="{outline(SEMI, line, size, X, y)[0]}"/>'
        y += lead
    return svg(W, H, body)


def main() -> None:
    (ROOT / "website/favicon.svg").write_text(MARK)
    favicon = ROOT / "website/favicon.ico"
    favicon.write_bytes(ico([render(tile(s, s, 3 * s / 16, s), s, s) for s in (16, 32, 48)]))
    if sorted(Image.open(favicon).ico.sizes()) != [(16, 16), (32, 32), (48, 48)]:
        sys.exit("favicon.ico does not read back as 16, 32 and 48 px")
    for name, size, square, rx, box, colors in ICONS:
        (ROOT / name).write_bytes(render(tile(size, square, rx, box), size, size, colors))
    card = render(social(), 1280, 640, 128)
    for name in ("assets/brand/social.png", "website/social.png"):
        (ROOT / name).write_bytes(card)


if __name__ == "__main__":
    main()
