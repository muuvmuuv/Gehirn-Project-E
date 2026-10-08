#!/usr/bin/env bash
# Records a scene from the bridge's frames into an MP4 and a looping GIF; needs ffmpeg. The
# justfile's demo-record recipe runs it for the scene its scene variable names. Its arguments
# are SCENE, the name of a script in scripts/scenes, demo unless given, then that scene's own
# MOCK_PORT UMBILICAL_PORT WATCH_PORT PLUG_PORT, DIR for the recording, an empty or new
# directory, and LINEUP; the scene defaults the ones left empty, and a relative DIR starts at
# the repository root. By hand, run `just build` first: the scene flies ./gehirn as it is.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
root=$PWD
scene=${1:-demo} mock=${2:-} umbilical=${3:-} watch=${4:-} plug=${5:-} out=${6:-} lineup=${7:-}

# V 0.5.2 uploads the failing C line and the V source around it to bugs.vlang.io when a C build
# fails, and a run by hand has no justfile to export this (CONTRIBUTING.md, V 0.5.2 rule 9).
export V_C_ERROR_BUG_REPORT_DISABLED=1
scripts/lineup.sh "$lineup" "$scene"
command -v ffmpeg >/dev/null || {
    echo "demo-record: needs ffmpeg" >&2
    exit 1
}
if [ -z "$out" ]; then
    out=$(mktemp -d "${TMPDIR:-/tmp}/gehirn-record.XXXXXX")
elif [ -n "$(ls -A "$out" 2>/dev/null)" ]; then
    echo "demo-record: $out is not empty" >&2
    exit 2
fi
mkdir -p "$out/frames"
out=$(cd "$out" && pwd)

# A failed or stopped take leaves thousands of frames otherwise; run/ keeps its logs.
trap 'rm -rf "$out/frames" "$out/caption.ppm" "$out/gehirn-bridge"' EXIT

# OpenGL, because sokol's screenshot readback fails on Metal (CONTRIBUTING.md, V 0.5.2
# rule 6). gg saves frames 1 to 9000, 150 s at 60 fps, as gehirn-bridge_<n>.png, and bridge_1x
# draws them at 1x, since at 2x a Retina Mac saves 7 a second (bridge/main.v). Keep the window
# uncovered, since macOS slows a covered window's frames. LARGE_CONFIG as the justfile's bridge recipe
# gives it, or the bundled GC runs out of root sets on macOS.
v -prod -cflags -DLARGE_CONFIG -d gg_record -d bridge_1x -d darwin_sokol_glcore33 -o "$out/gehirn-bridge" bridge/
# A BRIDGE_MOUSE left in the shell from making stills would replay its hover into the take.
VGG_SCREENSHOT_FOLDER="$out/frames" VGG_SCREENSHOT_FRAMES=$(seq -s, 1 9000) env -u BRIDGE_MOUSE \
    "$root/scripts/scenes/$scene.sh" "$out/gehirn-bridge" \
    "$mock" "$umbilical" "$watch" "$plug" "$out/run" "$lineup"

# gg's frame rate follows how fast it saves each frame, which changes with what the
# frame shows, so each frame lasts until the next was saved. The newest is left out,
# since the kill may cut it short.
n=$(find "$out/frames" -name '*.png' | wc -l | tr -d ' ')
if [ "$n" -lt 100 ]; then
    echo "demo-record: gg saved $n frames; see $out/run/bridge.log" >&2
    exit 1
fi
fps=$(
    python3 - "$out/frames" "$n" <<'EOF'
import os, sys
d, n = sys.argv[1], int(sys.argv[2])
t = [os.path.getmtime(f"{d}/gehirn-bridge_{i}.png") for i in range(1, n + 1)]
with open(f"{d}/frames.txt", "w") as f:
    for i in range(1, n):
        f.write(f"file gehirn-bridge_{i}.png\nduration {t[i] - t[i - 1]:.4f}\n")
print(f"{(n - 2) / (t[n - 2] - t[0]):.1f}")
EOF
)

# The edit runs from MAGI deliberating on the goto, or from the field unit's start in a scene
# without one, to 2 s after the scene's last beat, or to the GIF's end below if that is later.
# The 40 s grace shows nothing new, so in a scene that kills HQ it plays at 8x under a caption
# at the bottom, clear of the mission clock that shows the speed. The bridge built with
# bridge_1x draws at 1x, so its frames are 1280 by 800, within X's 1920 by 1200.
at() { awk -v k="$1" 'index($0, k) { print $1; exit }' "$out/run/beats"; }

# lead prints how many seconds before a verdict's beat a cut opens on MAGI deliberating: the
# slowest ballot of the first verdict in HQ's log that contains $1, rounded up, and 1 s, since
# the beat counts whole seconds. The mock's slowest takes 1.7 s, a hosted one up to 9 s. The
# latency ends each ballot line of magi/magi.v Verdict.str.
lead() {
    awk -v v="$1" 'index($0, v) && !seen { seen = n = 4 }
        n && n-- && match($0, /[0-9]+ ms\)$/) { ms = substr($0, RSTART, RLENGTH - 4) + 0; if (ms > max) max = ms }
        END { print int((max + 999) / 1000) + 1 }' "$out/run/hq/hq.log"
}

# votes prints the verdicts on an irreversible proposal that the scene shows with ballots, r
# the second of the first and p of the last. The GIF loops from MAGI deliberating on r to 3 s
# after p: in the demo the refused release and the approved one, or the one release vote a
# run had.
votes() { awk '$2 == "ballots" && /need 3:/' "$out/run/beats"; }
r=$(votes | awk 'NR == 1 { print $1 }') p=$(votes | awk 'END { print $1 }')

s=$(at 'goto approved')
if [ -n "$s" ]; then
    s=$((s - $(lead 'need 2: 可決')))
else
    s=$(at 'field unit up')
fi
s=$((s > 0 ? s : 0)) e=$(($(tail -n 1 "$out/run/beats" | cut -d ' ' -f 1) + 2))
e=$((p + 3 > e ? p + 3 : e))
mp4=$out/gehirn-$scene.mp4
a=$(at 'HQ killed') b=$(at 'the cable counts as cut')
if [ -n "$a" ] && [ -n "$b" ]; then
    a=$((a + 3)) b=$((b - 2))
    c=$(awk -v s="$s" -v a="$a" -v b="$b" 'BEGIN { print a - s + (b - a) / 8 }')
    python3 tools/caption.py "40 S GRACE AT 8X" >"$out/caption.ppm"
    ffmpeg -hide_banner -loglevel error -y -f concat -i "$out/frames/frames.txt" -i "$out/caption.ppm" -filter_complex \
        "[0:v]trim=$s:$a,setpts=PTS-STARTPTS[x];[0:v]trim=$a:$b,setpts=(PTS-STARTPTS)/8[y];[0:v]trim=$b:$e,setpts=PTS-STARTPTS[z];[x][y][z]concat=n=3,fps=30[v];[v][1:v]overlay=(W-w)/2:H-h-6:enable='between(t,$((a - s)),$c)',format=yuv420p[o]" \
        -map '[o]' -c:v libx264 -crf 20 -movflags +faststart "$mp4"
else
    a=$e b=$e
    ffmpeg -hide_banner -loglevel error -y -f concat -i "$out/frames/frames.txt" -vf \
        "trim=$s:$e,setpts=PTS-STARTPTS,fps=30,format=yuv420p" -c:v libx264 -crf 20 -movflags +faststart "$mp4"
fi

# clip prints where the second $1 of the scene's clock falls in the MP4, whose grace from a to
# b plays at 8x.
clip() { awk -v t="$1" -v s="$s" -v a="$a" -v b="$b" 'BEGIN { if (t > b) t -= (b - a) * 7 / 8; else if (t > a) t = a + (t - a) / 8; print t - s }'; }

# The GIF shows the MAGI block alone, large enough to read on a phone (bridge/draw.v magi_box,
# 16, 58, 736 by 412).
gif="no gehirn-magi.gif, since the scene showed no vote on an irreversible proposal"
if [ -n "$r" ]; then
    f=$(clip $((r - $(lead "$(votes | awk 'NR == 1 { sub(/^[0-9]+ ballots /, ""); print }')"))))
    t=$(clip $((p + 3)))
    ffmpeg -hide_banner -loglevel error -y -ss "$f" -t "$(awk -v f="$f" -v t="$t" 'BEGIN { print t - f }')" -i "$mp4" -vf \
        'crop=752:420:8:54,fps=12,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=none' \
        "$out/gehirn-magi.gif"
    gif="$out/gehirn-magi.gif ($(du -h "$out/gehirn-magi.gif" | cut -f1))"
fi
echo "demo-record: $mp4 ($(du -h "$mp4" | cut -f1)) and $gif, from $n frames at $fps a second"
