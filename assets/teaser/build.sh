#!/usr/bin/env bash
# Builds the teaser 否決は、覆らない from gehirn's own recordings into assets/media/social/: both
# cuts, their PNG covers and the Reel's JPEG cover. Usage: assets/teaser/build.sh [WORK]
# WORK (default $TMPDIR/gehirn-teaser) holds the frames, fonts and playwright-core between runs.
# Needs ffmpeg, node, bun (once, for playwright-core), Playwright's cached chrome-headless-shell,
# and uv for the glyph check.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=${1:-${TMPDIR:-/tmp}/gehirn-teaser}
out=$repo/assets/media/social
mkdir -p "$work" "$out"
cp "$here/scene.html" "$here/render.mjs" "$work/"
cd "$work"

[ -d node_modules/playwright-core ] || PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 bun add playwright-core@1.63.0

# Fonts: Barlow from the bridge, the full Zen Old Mincho Black from google/fonts ofl/zenoldmincho,
# since the bridge's subset lacks most of the captions' kanji.
mkdir -p fonts src/gif src/y6x src/y6r
cp "$repo"/bridge/fonts/BarlowCondensed-{Black,SemiBold}.ttf fonts/
[ -f fonts/ZenOldMincho-Black.ttf ] ||
    curl -fsSL -o fonts/ZenOldMincho-Black.ttf https://github.com/google/fonts/raw/main/ofl/zenoldmincho/ZenOldMincho-Black.ttf
cp "$repo"/assets/brand/lockup-dark.svg src/

# Every character the page sets must be in its font, or Chromium falls back to a system face.
uv run -q --no-project --with fonttools python -I - <<'PY'
from fontTools.ttLib import TTFont

text = open("scene.html", encoding="utf-8").read()
for path, pick in [
    ("fonts/ZenOldMincho-Black.ttf", lambda c: ord(c) > 0x7F),
    ("fonts/BarlowCondensed-Black.ttf", lambda c: 0x20 <= ord(c) < 0x3000),
    ("fonts/BarlowCondensed-SemiBold.ttf", lambda c: 0x20 <= ord(c) < 0x3000),
]:
    cmap = TTFont(path).getBestCmap()
    missing = sorted({c for c in text if pick(c) and not c.isspace() and ord(c) not in cmap})
    print(path, "missing:", "".join(missing) or "none")
PY

# The GIF's frames as they are (12 fps); scene.html picks one per output frame.
ffmpeg -v error -y -i "$repo"/assets/media/magi.gif -fps_mode passthrough src/gif/%03d.png
# Operation Yashima's second shot: the MAGI block (bridge/draw.v lays it out at 16, 58, 736 by
# 412) from frame 975 to the last, 1139, at each cut's footage size, and the last frame whole for
# the pull back.
y6=$repo/assets/media/scenes/ep06-yashima.mp4
ffmpeg -v error -y -i "$y6" -vf "select='gte(n\,975)',crop=736:412:16:58,scale=1480:827:flags=lanczos,unsharp=5:5:0.6" \
    -fps_mode passthrough -start_number 975 src/y6x/%04d.png
ffmpeg -v error -y -i "$y6" -vf "select='gte(n\,975)',crop=736:412:16:58,scale=1000:559:flags=lanczos,unsharp=5:5:0.4" \
    -fps_mode passthrough -start_number 975 src/y6r/%04d.png
ffmpeg -v error -y -i "$y6" -vf "select='eq(n\,1139)',scale=2560:1600:flags=lanczos,unsharp=5:5:0.5" -frames:v 1 src/y6full2x.png
ffmpeg -v error -y -i "$repo"/assets/media/bridge/scene.png -vf scale=2016:1424:flags=neighbor src/scene4x.png

node render.mjs x video "$out/gehirn-teaser-16x9.mp4"
node render.mjs reel video "$out/gehirn-teaser-9x16.mp4"

# Covers: frame 40 (1.333 s), the refusal 否決 1/3 with the chip. The PNGs are cut to 256 colors
# as the website's posters are; Instagram takes a cover only as JPEG.
node render.mjs x stills 1.3333333 .
node render.mjs reel stills 1.3333333 .
ffmpeg -v error -y -i reel-1.3333333.png -q:v 2 "$out/gehirn-teaser-9x16.jpg"
for c in x:16x9 reel:9x16; do
    ffmpeg -v error -y -i "${c%%:*}-1.3333333.png" \
        -vf "split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=none" \
        "$out/gehirn-teaser-${c##*:}.png"
done
ls -l "$out"
