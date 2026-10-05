#!/usr/bin/env bash
# Records a scene from the bridge's frames into an MP4 and a looping GIF; needs ffmpeg. The
# justfile's demo-record recipe runs it for the demo. Its arguments are SCENE, the name of a script
# in scripts/scenes, demo unless given, then that scene's own MOCK_PORT UMBILICAL_PORT WATCH_PORT
# PLUG_PORT, DIR for the recording, an empty or new directory, and LINEUP; the scene defaults the
# ones left empty, and a relative DIR starts at the repository root. By hand, run `just build`
# first: the scene flies ./gehirn as it is.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
root=$PWD
scene=${1:-demo} mock=${2:-} umbilical=${3:-} watch=${4:-} plug=${5:-} out=${6:-} lineup=${7:-}

# V 0.5.2 uploads the failing C line and the V source around it to bugs.vlang.io when a C build
# fails, and a run by hand has no justfile to export this (CONTRIBUTING.md, V 0.5.2 rule 9).
export V_C_ERROR_BUG_REPORT_DISABLED=1
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

# OpenGL, because sokol's screenshot readback fails on Metal (CONTRIBUTING.md, V 0.5.2
# rule 6). gg saves frames 1 to 9000, 150 s at 60 fps, as gehirn-bridge_<n>.png. Keep the
# window uncovered, since macOS slows a covered window's frames.
v -prod -d gg_record -d darwin_sokol_glcore33 -o "$out/gehirn-bridge" bridge/
VGG_SCREENSHOT_FOLDER="$out/frames" VGG_SCREENSHOT_FRAMES=$(seq -s, 1 9000) \
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

# The edit runs from MAGI deliberating on the goto to 2 s after the cable reconnects. The 40 s
# grace shows nothing new, so it plays at 8x under a caption at the bottom, clear of the
# mission clock that shows the speed. gg saves a Retina window at twice its size, and X takes
# at most 1920 by 1200.
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
s=$(($(at 'goto approved') - $(lead 'need 2: 可決'))) e=$(($(at 'cable reconnected') + 2))
s=$((s > 0 ? s : 0))
a=$(($(at 'HQ killed') + 3)) b=$(($(at 'the cable counts as cut') - 2))
c=$(awk -v s="$s" -v a="$a" -v b="$b" 'BEGIN { print a - s + (b - a) / 8 }')
python3 tools/caption.py "40 S GRACE AT 8X" >"$out/caption.ppm"
ffmpeg -hide_banner -loglevel error -y -f concat -i "$out/frames/frames.txt" -i "$out/caption.ppm" -filter_complex \
    "[0:v]trim=$s:$a,setpts=PTS-STARTPTS[x];[0:v]trim=$a:$b,setpts=(PTS-STARTPTS)/8[y];[0:v]trim=$b:$e,setpts=PTS-STARTPTS[z];[x][y][z]concat=n=3,fps=30,scale=1280:-2:flags=lanczos[v];[v][1:v]overlay=(W-w)/2:H-h-6:enable='between(t,$((a - s)),$c)',format=yuv420p[o]" \
    -map '[o]' -c:v libx264 -crf 20 -movflags +faststart "$out/gehirn-demo.mp4"

# The GIF shows the MAGI block alone, large enough to read on a phone (bridge/draw.v draw
# lays it out at 16, 58, 736 by 412), and loops from MAGI deliberating on the refused
# release to 3 s after the approved one, or around the one of them a run had.
r=$(at 'release refused') p=$(at 'release approved') v='need 3: 否決'
if [ -z "$r" ]; then
    r=$p v='need 3: 可決'
fi
p=${p:-$r}
gif="no gehirn-magi.gif, since no release vote came within the demo's wait"
if [ -n "$r" ]; then
    l=$(lead "$v")
    ffmpeg -hide_banner -loglevel error -y -ss $((r - l - s)) -t $((p - r + l + 3)) -i "$out/gehirn-demo.mp4" -vf \
        'crop=752:420:8:54,fps=12,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=none' \
        "$out/gehirn-magi.gif"
    gif="$out/gehirn-magi.gif ($(du -h "$out/gehirn-magi.gif" | cut -f1))"
fi
rm -rf "$out/frames" "$out/caption.ppm" "$out/gehirn-bridge"
echo "demo-record: $out/gehirn-demo.mp4 ($(du -h "$out/gehirn-demo.mp4" | cut -f1)) and $gif, from $n frames at $fps a second"
