# gehirn's one entry point for the checks, the build and the mock missions.
# CONTRIBUTING.md "Checks" says when each runs; lefthook.yml calls the same recipes on what is staged.

# Runs every check on the working tree.
check: fmt vet test py

# Verifies that V files are formatted; `v fmt -w` fixes them.
fmt *paths=".":
    v fmt -verify {{ paths }}

# Checks that every pub fn has a doc comment that starts with its name.
vet *paths=".":
    v vet -W {{ paths }}

# Runs every _test.v; warnings and notices fail the build.
test: zenoh
    v -W -N test .

# Fetches the pinned zenoh-c release for this host into thirdparty/zenoh-c, which zenoh/zenoh.c.v links.
zenoh:
    #!/usr/bin/env bash
    set -euo pipefail
    version=1.10.1

    # Asks getconf for glibc, since a glibc host with Debian's or Ubuntu's musl package also has /lib/ld-musl-*.
    libc=musl
    if getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
        libc=gnu
    fi

    # ponytail: macOS on Apple Silicon and Linux on aarch64 and x86_64 only; another host needs its target and checksum here.
    case "$(uname -s)-$(uname -m)-$libc" in
        Darwin-arm64-*) target=aarch64-apple-darwin sum=82da6e95eb895413369f55d1a53eb5b621b22ab8afc446b041b7760eec240ff4 ;;
        Linux-aarch64-musl) target=aarch64-unknown-linux-musl sum=de99cc82c7ae93eaa2aa5a0c8bcfcefed7624b0e0f85c679f7dba9c54ccdff9c ;;
        Linux-aarch64-gnu) target=aarch64-unknown-linux-gnu sum=65970bbed6dc10fec4fa39d05f3876e85fcb9b0f87d5be0a54bd7517240db501 ;;
        Linux-x86_64-musl) target=x86_64-unknown-linux-musl sum=293866bb632fd579fb0603bbfdb8d383e7c2d4eadc8ec3ae199fafa1dbc99c55 ;;
        Linux-x86_64-gnu) target=x86_64-unknown-linux-gnu sum=9ee0f2d732b0f3042a7e1cd3076042a2bc3ac0415587c40bc3ed7b8b62fbde11 ;;
        *) echo "zenoh: no pinned zenoh-c build for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
    esac
    dir=thirdparty/zenoh-c
    if [ "$(cat "$dir/VERSION" 2>/dev/null)" = "$version $target" ]; then
        exit 0
    fi
    echo "zenoh: fetching zenoh-c $version for $target into $dir"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/zenoh-c.zip" "https://github.com/eclipse-zenoh/zenoh-c/releases/download/$version/zenoh-c-$version-$target-standalone.zip"
    got=$( (sha256sum 2>/dev/null || shasum -a 256) < "$tmp/zenoh-c.zip" | cut -d' ' -f1)
    if [ "$got" != "$sum" ]; then
        echo "zenoh: checksum mismatch for zenoh-c $version $target" >&2
        exit 1
    fi
    rm -rf "$dir"
    mkdir -p "$dir"
    unzip -q "$tmp/zenoh-c.zip" -d "$dir"
    echo "$version $target" > "$dir/VERSION"

# Runs every tools/test_*.py self check and compiles the Python files.
py *paths="tools/*.py sidecar/*.py":
    for t in tools/test_*.py; do python3 "$t" || exit 1; done
    python3 -m py_compile {{ paths }}

# Builds the release binary ./gehirn.
build: zenoh
    v -prod -o gehirn .

# Builds the bridge, ./gehirn-bridge, which runs on its own machine (ADR-0005).
bridge: zenoh
    v -prod -o gehirn-bridge bridge/

# Builds the gamepad bridge, ./gehirn-gamepad, which runs on the pilot's machine and alone needs SDL2 (ADR-0006).
gamepad:
    v -prod -o gehirn-gamepad gamepad/

# Flies the mock missions and puts the adversarial scenarios to the mock MAGI; port is the mock's.
missions runs="10" port="8081": build
    #!/usr/bin/env bash
    set -euo pipefail
    # 8081 is the port of the llama.cpp preset and gehirn's default GEHIRN_URL.
    python3 tools/mock_endpoint.py --listen 127.0.0.1:{{ port }} --quiet &
    mock=$!
    trap 'kill $mock' EXIT
    export GEHIRN_URL=http://127.0.0.1:{{ port }}/v1/chat/completions
    export TYPESAFE_URL=http://127.0.0.1:{{ port }}/v1/systemone TYPESAFE_API_KEY=mock
    python3 tools/trials.py --runs {{ runs }} --jobs 3
    ./gehirn magi-eval 3

# Flies one narrated mission on the mock with HQ, the field unit and the bridge apart; no keys.
demo mock="8081" umbilical="7447" watch="7448" plug="7777" dir="": build bridge (_fly justfile_directory() / "gehirn-bridge" mock umbilical watch plug dir)

# Records `just demo` from the bridge's frames into an MP4 and a looping GIF; needs ffmpeg.
demo-record mock="8081" umbilical="7447" watch="7448" plug="7777" dir="": build
    #!/usr/bin/env bash
    set -euo pipefail
    command -v ffmpeg >/dev/null || { echo "demo-record: needs ffmpeg" >&2; exit 1; }
    out={{ quote(dir) }}
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
        {{ just_executable() }} --justfile {{ quote(justfile()) }} _fly "$out/gehirn-bridge" \
        {{ quote(mock) }} {{ quote(umbilical) }} {{ quote(watch) }} {{ quote(plug) }} "$out/run"

    # gg's frame rate follows how fast it saves each frame, which changes with what the
    # frame shows, so each frame lasts until the next was saved. The newest is left out,
    # since the kill may cut it short.
    n=$(find "$out/frames" -name '*.png' | wc -l | tr -d ' ')
    if [ "$n" -lt 100 ]; then
        echo "demo-record: gg saved $n frames; see $out/run/bridge.log" >&2
        exit 1
    fi
    fps=$(python3 - "$out/frames" "$n" <<'EOF'
    import os, sys
    d, n = sys.argv[1], int(sys.argv[2])
    t = [os.path.getmtime(f"{d}/gehirn-bridge_{i}.png") for i in range(1, n + 1)]
    with open(f"{d}/frames.txt", "w") as f:
        for i in range(1, n):
            f.write(f"file gehirn-bridge_{i}.png\nduration {t[i] - t[i - 1]:.4f}\n")
    print(f"{(n - 2) / (t[n - 2] - t[0]):.1f}")
    EOF
    )

    # The 40 s grace shows nothing new, so it plays at 8x under a caption that says so. gg
    # saves a Retina window at twice its size, and X takes at most 1920 by 1200.
    at() { awk -v k="$1" 'index($0, k) { print $1; exit }' "$out/run/beats"; }
    a=$(($(at 'HQ killed') + 3)) b=$(($(at 'the cable counts as cut') - 2))
    c=$(awk -v a="$a" -v b="$b" 'BEGIN { print a + (b - a) / 8 }')
    python3 tools/caption.py "40 S GRACE AT 8X" >"$out/caption.ppm"
    ffmpeg -hide_banner -loglevel error -y -f concat -i "$out/frames/frames.txt" -i "$out/caption.ppm" -filter_complex \
        "[0:v]trim=0:$a,setpts=PTS-STARTPTS[x];[0:v]trim=$a:$b,setpts=(PTS-STARTPTS)/8[y];[0:v]trim=$b,setpts=PTS-STARTPTS[z];[x][y][z]concat=n=3,fps=30,scale=1280:-2:flags=lanczos[v];[v][1:v]overlay=(W-w)/2:12:enable='between(t,$a,$c)',format=yuv420p[o]" \
        -map '[o]' -c:v libx264 -crf 20 -movflags +faststart "$out/gehirn-demo.mp4"

    # The GIF loops from the refused release to the approved one.
    r=$(at 'release refused') p=$(at 'release approved')
    ffmpeg -hide_banner -loglevel error -y -ss $((r - 3)) -t $((p - r + 6)) -i "$out/gehirn-demo.mp4" -vf \
        'fps=12,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=none' \
        "$out/gehirn-magi.gif"
    rm -rf "$out/frames" "$out/caption.ppm" "$out/gehirn-bridge"
    echo "demo-record: $out/gehirn-demo.mp4 ($(du -h "$out/gehirn-demo.mp4" | cut -f1)) and $out/gehirn-magi.gif ($(du -h "$out/gehirn-magi.gif" | cut -f1)), from $n frames at $fps a second"

[private]
[no-exit-message]
_fly bridge_bin mock umbilical watch plug dir:
    #!/usr/bin/env bash
    set -euo pipefail
    # The ports dodge ones in use, and the run directory, a fresh temp dir unless given, takes
    # the journal and the recorder, which are a pilot's data and never belong in the repo.

    # Measured on 2026-10-02: these put the body at the beacon just after the walking human
    # (body/body.v scene, one loop per 21 s) passes it, so MAGI refuses the first release and
    # approves the next. Zenoh's redial lands the goto about 2 s after HQ starts.
    hq_delay=5        # s from the field unit's start to HQ's
    pilot_s=11        # plug/dummy.v needs 500 pilot ticks under a goal, 10 s at 50 Hz
    pilot_speed=0.7
    pilot_offset=-45  # south of the pillar, clear of the human's loop
    reconnect_s=5
    root=$PWD bin=$PWD/gehirn bridge_bin={{ quote(bridge_bin) }}
    run={{ quote(dir) }}
    if [ -z "$run" ]; then
        run=$(mktemp -d "${TMPDIR:-/tmp}/gehirn-demo.XXXXXX")
    elif [ -n "$(ls -A "$run" 2>/dev/null)" ]; then
        echo "demo: $run is not empty, and the run needs a fresh journal and recorder" >&2
        exit 2
    fi
    mkdir -p "$run/hq" "$run/field"
    run=$(cd "$run" && pwd)

    # Every variable of README's configuration table but SSL_CERT_FILE, so nothing hosted or
    # personal leaks in; above all CORE_JOURNAL and PLUG_RECORDER, the pilot's data.
    unset GEHIRN_URL GEHIRN_KEY CORE_URL CORE_KEY CORE_MODEL MELCHIOR_URL MELCHIOR_KEY \
        MELCHIOR_MODEL BALTHASAR_URL BALTHASAR_KEY BALTHASAR_MODEL CASPER_URL CASPER_KEY \
        CASPER_MODEL CORE_REASONING MELCHIOR_REASONING BALTHASAR_REASONING CASPER_REASONING \
        BALTHASAR_BACKEND MAGI_TIMEOUT_MS CORE_TIMEOUT_MS CORE_BACKEND CL1_SPIKES CL1_SIDECAR \
        PILOT_ID PLUG_ADDR MISSION CORE_JOURNAL PLUG_RECORDER HQ_PERIOD_MS UNIT_ID
    key() { python3 -c 'import secrets; print(secrets.token_hex(32))'; }
    UMBILICAL_KEY=$(key) WATCH_KEY=$(key) PILOT_KEY=$(key)
    export UMBILICAL_KEY WATCH_KEY PILOT_KEY TYPESAFE_API_KEY=mock
    export GEHIRN_URL=http://127.0.0.1:{{ mock }}/v1/chat/completions
    export TYPESAFE_URL=http://127.0.0.1:{{ mock }}/v1/systemone
    export UMBILICAL_ENDPOINT=tcp/127.0.0.1:{{ umbilical }} BRIDGE_ENDPOINT=tcp/127.0.0.1:{{ watch }}
    export PLUG_LISTEN=127.0.0.1:{{ plug }}
    export MAGI_COOLDOWN_MS=5000 UMBILICAL_GRACE_MS=40000 INTERNAL_BUDGET_MS=300000

    pids=""
    trap 'kill $pids 2>/dev/null || true; wait; echo "demo: stopped everything; logs in $run"' EXIT
    trap 'exit 130' INT TERM
    say() {
        printf '%d:%02d demo: %s\n' $((SECONDS / 60)) $((SECONDS % 60)) "$1"
        echo "$SECONDS $1" >>"$run/beats"
    }
    fail() {
        printf '%d:%02d demo: %s\n' $((SECONDS / 60)) $((SECONDS % 60)) "$1" >&2
        exit 1
    }

    # beat waits up to $4 s for the text $3 in the log $2, then narrates $1. The texts come from
    # magi/magi.v Verdict.str, the field:, umbilical: and release outcome lines of main.v and
    # tools/mock_endpoint.py's first line, each of which names this recipe.
    beat() {
        for _ in $(seq $(($4 * 5))); do
            if grep -qF "$3" "$2" 2>/dev/null; then
                say "$1"
                return
            fi
            sleep 0.2
        done
        fail "no \"$3\" in $2 within $4 s; its last line: $(tail -n 1 "$2" 2>/dev/null)"
    }

    # ballots prints the first verdict in HQ's log that contains $1, and the three ballots below.
    ballots() { awk -v v="$1" 'index($0, v) && !seen { seen = n = 4 } n && n-- { print "       " $0 }' "$run/hq/hq.log"; }
    alive() { kill -0 "$1" 2>/dev/null || fail "$2 stopped; its last line: $(tail -n 1 "$3")"; }
    start() { (cd "$run/$1" && exec "$bin" "$1" >>"$1.log" 2>&1) & pids="$pids $!"; }

    SECONDS=0
    python3 tools/mock_endpoint.py --listen 127.0.0.1:{{ mock }} --quiet 2>"$run/mock.log" &
    pids="$pids $!"
    beat "mock models on 127.0.0.1:{{ mock }}, scripted by tools/mock_endpoint.py, so no keys" "$run/mock.log" 'mock: serving' 5

    # AppKit reads -NSAppSleepDisabled for this process only, so App Nap cannot slow a window
    # nobody sees while demo-record saves its frames (CONTRIBUTING.md, V 0.5.2 rule 6).
    (cd "$run" && exec "$bridge_bin" -NSAppSleepDisabled YES >bridge.log 2>&1) &
    bridge=$!
    pids="$pids $bridge"
    start field
    field=$!
    say "field unit up and waiting for HQ; a human walks a loop past beacon b1"
    sleep "$hq_delay"
    alive "$bridge" "gehirn-bridge" "$run/bridge.log"
    alive "$field" "the field unit" "$run/field/field.log"
    start hq
    hq=$!
    say "HQ up: the core proposes goals, and MAGI judge them"
    beat "goto approved; the core steers toward the beacon" "$run/hq/hq.log" 'MAGI 3/3, need 2' 15
    ballots 'MAGI 3/3, need 2'
    (cd "$run/field" && exec python3 "$root/tools/pilot.py" --addr "$PLUG_LISTEN" --seconds "$pilot_s" \
        --speed "$pilot_speed" --offset "$pilot_offset" >pilot.log 2>&1) &
    pids="$pids $!"
    beat "a pilot takes the seat and steers ${pilot_offset#-} degrees off the line to the beacon" "$run/field/field.log" 'seat pilot' 5
    beat "the pilot leaves; the dummy plug, cloned from that pilot, takes the seat" "$run/field/field.log" 'seat dummy' $((pilot_s + 5))
    beat "release refused: a human is within reach of the drop" "$run/hq/hq.log" 'need 3: 否決' 40
    ballots 'need 3: 否決'
    beat "release approved: the human walked on, and the 5 s cooldown passed" "$run/hq/hq.log" 'need 3: 可決' 30
    ballots 'need 3: 可決'
    beat "released on target" "$run/hq/core.shinji.jsonl" 'released on target' 10
    kill "$hq"
    say "HQ killed: the cable goes silent, and the field unit waits out the 40 s grace"
    beat "the cable counts as cut; internal power, 5:00 counting down" "$run/field/field.log" 'connected to internal' 50
    sleep "$reconnect_s"
    start hq
    say "HQ restarted"
    beat "cable reconnected; the field unit never stopped" "$run/field/field.log" 'internal to connected' 20
    sleep 5
