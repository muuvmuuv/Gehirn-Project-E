# gehirn's one entry point for the checks, the build and the mock missions.
# CONTRIBUTING.md "Checks" says when each runs; lefthook.yml calls the same recipes on what is staged.

# V 0.5.2 uploads the failing C line and the V source around it to bugs.vlang.io when a C build fails.
export V_C_ERROR_BUG_REPORT_DISABLED := "1"

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

# Which models `just demo` and `just demo-record` fly: mock, scripted by tools/mock_endpoint.py
# without keys; hosted, README's hosted lineup; or magi, the hosted MAGI judging the mock's
# scripted core, which proposes the release at the beacon whatever the human does. The last two
# take GEHIRN_KEY and TYPESAFE_API_KEY: `python3 tools/withenv.py .env just lineup=magi demo`.
lineup := "mock"

# Flies one narrated mission with HQ, the field unit and the bridge apart, on lineup's models.
demo mock="8081" umbilical="7447" watch="7448" plug="7777" dir="": _lineup build bridge (_fly justfile_directory() / "gehirn-bridge" mock umbilical watch plug dir lineup)

# Records `just demo` from the bridge's frames into an MP4 and a looping GIF; needs ffmpeg.
demo-record mock="8081" umbilical="7447" watch="7448" plug="7777" dir="": _lineup build
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
        {{ quote(mock) }} {{ quote(umbilical) }} {{ quote(watch) }} {{ quote(plug) }} "$out/run" {{ quote(lineup) }}

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

    # The edit runs from MAGI deliberating on the goto to 2 s after the cable reconnects. The 40 s
    # grace shows nothing new, so it plays at 8x under a caption at the bottom, clear of the
    # mission clock that shows the speed. gg saves a Retina window at twice its size, and X takes
    # at most 1920 by 1200.
    at() { awk -v k="$1" 'index($0, k) { print $1; exit }' "$out/run/beats"; }

    # lead prints how many seconds before a verdict's beat a cut opens on MAGI deliberating: the
    # slowest ballot of the first verdict in HQ's log that contains $1, rounded up, and 1 s, since
    # the beat counts whole seconds. The mock's slowest takes 1.7 s, a hosted one up to 9 s.
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

# Refuses an unknown lineup, and hosted models without their keys, before anything builds.
[private]
[no-exit-message]
_lineup:
    #!/usr/bin/env bash
    lineup={{ quote(lineup) }}
    case "$lineup" in
        mock) ;;
        hosted | magi)
            if [ -z "${GEHIRN_KEY:-}" ] || [ -z "${TYPESAFE_API_KEY:-}" ]; then
                echo "demo: lineup $lineup needs GEHIRN_KEY and TYPESAFE_API_KEY; python3 tools/withenv.py .env just lineup=$lineup demo passes them from .env" >&2
                exit 2
            fi
            ;;
        *)
            echo "demo: lineup is \"$lineup\", not mock, hosted or magi" >&2
            exit 2
            ;;
    esac

[private]
[no-exit-message]
_fly bridge_bin mock umbilical watch plug dir lineup:
    #!/usr/bin/env bash
    set -euo pipefail
    # The ports dodge ones in use, and the run directory, a fresh temp dir unless given, takes
    # the journal and the recorder, which are a pilot's data and never belong in the repo.

    # The walking human (body/body.v scene, one loop per 21 s) starts with the field unit. HQ
    # listens before the field unit starts, so the field unit's first dial reaches it, and on the
    # mock the goto lands about 4 s in: 2 s for the core, 1.7 s for the slowest ballot. The pilot
    # sits down as it lands, and the body reaches the beacon about 13.5 s later, as the human comes
    # within reach. HQ deliberates every 3.5 s from the goto, the core's 2 s and the 1.5 s pause,
    # and MAGI judge the percept that is newest when the core's proposal comes back: for the first
    # release one from about 17.5 s after the goto, with the human 0.7 m from the beacon, and for
    # the next, after the 8 s cooldown, one from 12 s later, with the human 3.9 m away. Both clocks
    # run from the goto, so a slow host shifts them together.
    pilot_s=11        # plug/dummy.v needs 500 pilot ticks under a goal, 10 s at 50 Hz
    pilot_speed=0.6
    pilot_offset=-45  # south of the pillar, clear of the human's loop
    cooldown_s=8      # as PLAN's Known issue 23 times it; 5 s puts the next release to MAGI 3.5 s sooner
    reconnect_s=5
    lineup={{ quote(lineup) }}
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
    # personal leaks in; above all CORE_JOURNAL, PLUG_RECORDER and DUMMY_WEIGHTS, the pilot's data.
    # Hosted models keep their variables, their endpoints and keys among them.
    unset MAGI_TIMEOUT_MS CORE_TIMEOUT_MS CORE_BACKEND CL1_SPIKES CL1_SIDECAR PILOT_ID PLUG_ADDR \
        MISSION START CORE_JOURNAL PLUG_RECORDER DUMMY_WEIGHTS HQ_PERIOD_MS UNIT_ID
    if [ "$lineup" = mock ]; then
        unset GEHIRN_URL GEHIRN_KEY CORE_URL CORE_KEY CORE_MODEL MELCHIOR_URL MELCHIOR_KEY \
            MELCHIOR_MODEL BALTHASAR_URL BALTHASAR_KEY BALTHASAR_MODEL CASPER_URL CASPER_KEY \
            CASPER_MODEL CORE_REASONING MELCHIOR_REASONING BALTHASAR_REASONING CASPER_REASONING \
            BALTHASAR_BACKEND
        export TYPESAFE_API_KEY=mock
        export GEHIRN_URL=http://127.0.0.1:{{ mock }}/v1/chat/completions
        export TYPESAFE_URL=http://127.0.0.1:{{ mock }}/v1/systemone

        # The bridge shows these names on the units' ballots, so it says what answered. gehirn
        # refuses two MAGI units on one model at one URL; BALTHASAR asks the mock's Jev route as
        # jev-1.13.0.
        export CORE_MODEL=mock-core MELCHIOR_MODEL=mock-melchior CASPER_MODEL=mock-casper
    else
        # README's lineup under "Hosted models", unless the environment names others.
        export GEHIRN_URL=${GEHIRN_URL:-https://openrouter.ai/api/v1/chat/completions}
        export CORE_MODEL=${CORE_MODEL:-qwen/qwen3-8b} MELCHIOR_MODEL=${MELCHIOR_MODEL:-openai/gpt-oss-20b}
        export CASPER_MODEL=${CASPER_MODEL:-meta-llama/llama-3.1-8b-instruct}

        # Hosted ballots take seconds, up to 9 s on 2026-10-04, so a shorter cooldown and pause bring
        # the next release to MAGI 4.5 s sooner, before the human walks back toward the drop.
        cooldown_s=6
        export HQ_PERIOD_MS=1000
    fi
    if [ "$lineup" = magi ]; then
        # Its own key keeps GEHIRN_KEY off the mock.
        export CORE_URL=http://127.0.0.1:{{ mock }}/v1/chat/completions CORE_MODEL=mock-core CORE_KEY=mock
    fi
    key() { python3 -c 'import secrets; print(secrets.token_hex(32))'; }
    UMBILICAL_KEY=$(key) WATCH_KEY=$(key) PILOT_KEY=$(key)
    export UMBILICAL_KEY WATCH_KEY PILOT_KEY
    export UMBILICAL_ENDPOINT=tcp/127.0.0.1:{{ umbilical }} BRIDGE_ENDPOINT=tcp/127.0.0.1:{{ watch }}
    export PLUG_LISTEN=127.0.0.1:{{ plug }}
    export MAGI_COOLDOWN_MS=$((cooldown_s * 1000)) UMBILICAL_GRACE_MS=40000 INTERNAL_BUDGET_MS=300000

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

    # waits waits up to $1 s for the text $3 in the log $2, and fails if it does not come. The texts
    # come from magi/magi.v Verdict.str, the hq:, field:, umbilical:, armor: and release outcome
    # lines of main.v and tools/mock_endpoint.py's first line, each of which names this recipe.
    waits() {
        for _ in $(seq $(($1 * 5))); do
            if grep -qF "$3" "$2" 2>/dev/null; then
                return
            fi
            sleep 0.2
        done
        return 1
    }

    # beat waits up to $4 s for the text $3 in the log $2, then narrates $1, or stops the demo.
    beat() {
        waits "$4" "$2" "$3" || fail "no \"$3\" in $2 within $4 s; its last line: $(tail -n 1 "$2" 2>/dev/null)"
        say "$1"
    }

    # either waits up to $1 s for the text $3 in the log $2 or the text $5 in the log $4, and
    # prints 1 or 2 for the one it finds first, or nothing.
    either() {
        for _ in $(seq $(($1 * 5))); do
            if grep -qF "$3" "$2" 2>/dev/null; then
                echo 1
                return
            fi
            if grep -qF "$5" "$4" 2>/dev/null; then
                echo 2
                return
            fi
            sleep 0.2
        done
    }

    # ballots prints the newest verdict in HQ's log that contains $1, and the three ballots below.
    ballots() {
        awk -v v="$1" 'index($0, v) { out = ""; n = 4 } n && n-- { out = out "       " $0 "\n" } END { printf "%s", out }' "$run/hq/hq.log"
    }
    alive() { kill -0 "$1" 2>/dev/null || fail "$2 stopped; its last line: $(tail -n 1 "$3")"; }
    start() { (cd "$run/$1" && exec "$bin" "$1" >>"$1.log" 2>&1) & pids="$pids $!"; }

    SECONDS=0
    if [ "$lineup" != hosted ]; then
        # The units answer after 0.9, 1.7 and 0.5 s, so the bridge shows each one deliberating,
        # 審議中, until its ballot lands, and the core after 2 s, which paces HQ as timed above; the
        # mock answers at once otherwise. The magi lineup asks it for the core alone.
        python3 tools/mock_endpoint.py --listen 127.0.0.1:{{ mock }} --quiet --slow melchior=900 \
            --slow balthasar=1700 --slow casper=500 --slow core=2000 2>"$run/mock.log" &
        pids="$pids $!"
        waits 5 "$run/mock.log" 'mock: serving' || fail "the mock did not start; $(tail -n 1 "$run/mock.log")"
    fi
    if [ "$lineup" = mock ]; then
        say "mock models on 127.0.0.1:{{ mock }}, scripted by tools/mock_endpoint.py, so no keys"
    else
        balthasar=Jev
        if [ "${BALTHASAR_BACKEND:-jev}" != jev ]; then
            balthasar=${BALTHASAR_MODEL:-a chat model}
        fi
        say "hosted MAGI: MELCHIOR-1 on $MELCHIOR_MODEL, BALTHASAR-2 on $balthasar and CASPER-3 on $CASPER_MODEL"
        if [ "$lineup" = magi ]; then
            say "the core is the mock's on 127.0.0.1:{{ mock }}, scripted to release at the beacon whatever the human does"
        else
            say "the core on $CORE_MODEL"
        fi
    fi

    # AppKit reads -NSAppSleepDisabled for this process only, so App Nap cannot slow a window
    # nobody sees while demo-record saves its frames (CONTRIBUTING.md, V 0.5.2 rule 6).
    (cd "$run" && exec "$bridge_bin" -NSAppSleepDisabled YES >bridge.log 2>&1) &
    bridge=$!
    pids="$pids $bridge"

    # The boot sequence covers the bridge's panels for its first 2.8 s (bridge/draw.v boot_ms).
    sleep 3 &
    booting=$!

    # HQ listens before the field unit starts, so the field unit's first dial reaches it.
    start hq
    hq=$!
    beat "HQ up: the core proposes goals, and MAGI judge them" "$run/hq/hq.log" 'listening for the field' 10
    wait "$booting"
    alive "$bridge" "gehirn-bridge" "$run/bridge.log"
    alive "$hq" "HQ" "$run/hq/hq.log"
    start field
    field=$!
    say "field unit up; a human walks a loop past beacon b1"
    beat "goto approved; the core steers toward the beacon" "$run/hq/hq.log" 'need 2: 可決' 30
    ballots 'need 2: 可決'
    alive "$field" "the field unit" "$run/field/field.log"
    (cd "$run/field" && exec python3 "$root/tools/pilot.py" --addr "$PLUG_LISTEN" --seconds "$pilot_s" \
        --speed "$pilot_speed" --offset "$pilot_offset" >pilot.log 2>&1) &
    pids="$pids $!"
    beat "a pilot takes the seat and steers ${pilot_offset#-} degrees off the line to the beacon" "$run/field/field.log" 'seat pilot' 5
    beat "the pilot leaves; the dummy plug, cloned from that pilot, takes the seat" "$run/field/field.log" 'seat dummy' $((pilot_s + 5))

    # Real models judge for themselves: a hosted core holds while the human is within reach and may
    # hold on through a loop or more of the human's (PLAN, Known issue 26), and the armor refuses a
    # release MAGI approved on a percept from before the human came close, so a beat of the release
    # may not come.

    # missed narrates $1, a beat of the release that did not come, and flies on to the cut cable
    # with hosted models, or stops the demo on the mock, which scripts every beat.
    missed() {
        if [ "$lineup" = mock ]; then
            fail "$1"
        fi
        say "$1"
    }
    approved=""
    case $(either 90 "$run/hq/hq.log" 'need 3: 否決' "$run/hq/hq.log" 'need 3: 可決') in
        1)
            say "release refused: a human is within reach of the drop"
            ballots 'need 3: 否決'
            if waits 60 "$run/hq/hq.log" 'need 3: 可決'; then
                say "release approved: the human walked on, and the ${cooldown_s} s cooldown passed"
                ballots 'need 3: 可決'
                approved=1
            else
                missed "MAGI approved no release within 60 s of refusing one"
            fi
            ;;
        2)
            missed "release approved at its first vote, so this run shows no refusal"
            ballots 'need 3: 可決'
            approved=1
            ;;
        *)
            missed "no release went to MAGI within 90 s"
            ;;
    esac
    if [ -n "$approved" ]; then
        if [ "$(either 30 "$run/hq/core.shinji.jsonl" 'released on target' "$run/field/field.log" 'armor: release refused')" = 2 ]; then
            missed "the armor refused a release MAGI approved: by then a human was within 2 m of the drop"
        fi
        if waits 60 "$run/hq/core.shinji.jsonl" 'released on target'; then
            say "released on target"
        else
            missed "no payload released on target"
        fi
    fi
    kill "$hq"
    say "HQ killed: the cable goes silent, and the field unit waits out the 40 s grace"
    beat "the cable counts as cut; internal power, 5:00 counting down" "$run/field/field.log" 'connected to internal' 50
    sleep "$reconnect_s"
    start hq
    say "HQ restarted"
    beat "cable reconnected; the field unit never stopped" "$run/field/field.log" 'internal to connected' 20
    sleep 5
