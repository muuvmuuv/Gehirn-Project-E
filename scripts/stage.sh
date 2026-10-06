# shellcheck shell=bash
# The stage every script in scripts/scenes sources. From the scene's arguments, BRIDGE_BIN
# MOCK_PORT UMBILICAL_PORT WATCH_PORT PLUG_PORT DIR LINEUP, it checks the lineup and the scene
# with scripts/lineup.sh, makes the run directory, sets the lineup's models, the keys and the
# ports, and stops everything on exit; up starts the mock, the bridge, HQ and the field unit, and
# pilot seats a scripted pilot. Every argument has a default and the stage changes to the repository
# root, so a scene also runs by hand from anywhere, and a relative DIR starts at the root. By
# hand, run `just build bridge` first: a scene flies ./gehirn and ./gehirn-bridge as they are.

# The ports dodge ones in use, and the run directory, a fresh temp dir unless given, takes
# the journal and the recorder, which are a pilot's data and never belong in the repo.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root" || exit
bridge_bin=${1:-$root/gehirn-bridge} mock_port=${2:-8081} umbilical_port=${3:-7447} watch_port=${4:-7448} plug_port=${5:-7777} run=${6:-} lineup=${7:-mock}
name=$(basename "$0" .sh)
scripts/lineup.sh "$lineup" "$name" || exit
bin=$root/gehirn

# The walking human (h1 of body/world.v default_world, one loop per 21 s) starts with the field
# unit. HQ listens before the field unit starts, so the field unit's first dial reaches it, and on
# the mock the goto lands about 4 s in: 2 s for the core, 1.7 s for the slowest ballot. The pilot
# sits down as it lands, and the body reaches the beacon about 13.5 s later, as the human comes
# within reach. HQ deliberates every 3.5 s from the goto, the core's 2 s and the 1.5 s pause,
# and MAGI judge the percept that is newest when the core's proposal comes back: for the first
# release one from about 17.5 s after the goto, with the human 0.7 m from the beacon, and for
# the next, after the 8 s cooldown, one from 12 s later, with the human 3.9 m away. Both clocks
# run from the goto, so a slow host shifts them together.
pilot_s=11 # plug/dummy.v needs 500 pilot ticks under a goal, 10 s at 50 Hz
pilot_speed=0.6
pilot_offset=-45 # south of the pillar, clear of the human's loop
cooldown_s=8     # as PLAN's Known issue 23 times it; 5 s puts the next release to MAGI 3.5 s sooner
if [ -z "$run" ]; then
    run=$(mktemp -d "${TMPDIR:-/tmp}/gehirn-demo.XXXXXX")
elif [ -n "$(ls -A "$run" 2>/dev/null)" ]; then
    echo "$name: $run is not empty, and the run needs a fresh journal and recorder" >&2
    exit 2
fi
mkdir -p "$run/hq" "$run/field"
run=$(cd "$run" && pwd)

# Every variable of docs/configuration.md but SSL_CERT_FILE, DRIVE, BODY and PLANNER, so nothing
# hosted or personal leaks in; above all CORE_JOURNAL, PLUG_RECORDER and DUMMY_WEIGHTS, the
# pilot's data. Hosted models keep their variables, their endpoints and keys among them. WORLD goes
# too, since every beat above is timed on the default world; a scene that plays another world
# exports WORLD after sourcing this file, as an absolute path since HQ and the field unit each run
# in a directory of their own, times its own beats and sets field_note, which up says in place of
# the default world's walking human. DRIVE, BODY and PLANNER only say how the body moves, so
# `DRIVE=differential just demo`, `just body=mujoco demo` and `PLANNER=local just demo` fly the
# stage on a differential body, on the MuJoCo base and on the local planner; the beats above are
# timed on the default body and the reflex.
unset MAGI_TIMEOUT_MS CORE_TIMEOUT_MS CORE_BACKEND CL1_SPIKES CL1_SIDECAR PILOT_ID PLUG_ADDR \
    MISSION START WORLD CORE_JOURNAL PLUG_RECORDER DUMMY_WEIGHTS HQ_PERIOD_MS UNIT_ID
if [ "$lineup" = mock ]; then
    unset GEHIRN_URL GEHIRN_KEY CORE_URL CORE_KEY CORE_MODEL MELCHIOR_URL MELCHIOR_KEY \
        MELCHIOR_MODEL BALTHASAR_URL BALTHASAR_KEY BALTHASAR_MODEL CASPER_URL CASPER_KEY \
        CASPER_MODEL CORE_REASONING MELCHIOR_REASONING BALTHASAR_REASONING CASPER_REASONING \
        BALTHASAR_BACKEND
    export TYPESAFE_API_KEY=mock
    export GEHIRN_URL=http://127.0.0.1:$mock_port/v1/chat/completions
    export TYPESAFE_URL=http://127.0.0.1:$mock_port/v1/systemone

    # The bridge shows these names on the units' ballots, so it says what answered. gehirn
    # refuses two MAGI units on one model at one URL; BALTHASAR asks the mock's Jev route as
    # jev-1.13.0.
    export CORE_MODEL=mock-core MELCHIOR_MODEL=mock-melchior CASPER_MODEL=mock-casper
else
    # The lineup of docs/running.md, "Hosted models", unless the environment names others.
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
    export CORE_URL=http://127.0.0.1:$mock_port/v1/chat/completions CORE_MODEL=mock-core CORE_KEY=mock
fi
key() { python3 -c 'import secrets; print(secrets.token_hex(32))'; }
UMBILICAL_KEY=$(key) WATCH_KEY=$(key) PILOT_KEY=$(key)
export UMBILICAL_KEY WATCH_KEY PILOT_KEY
export UMBILICAL_ENDPOINT=tcp/127.0.0.1:$umbilical_port BRIDGE_ENDPOINT=tcp/127.0.0.1:$watch_port
export PLUG_LISTEN=127.0.0.1:$plug_port
export MAGI_COOLDOWN_MS=$((cooldown_s * 1000)) UMBILICAL_GRACE_MS=40000 INTERNAL_BUDGET_MS=300000

pids=""
trap 'kill $pids 2>/dev/null || true; wait; echo "$name: stopped everything; logs in $run"' EXIT
trap 'exit 130' INT TERM
say() {
    printf '%d:%02d %s: %s\n' $((SECONDS / 60)) $((SECONDS % 60)) "$name" "$1"
    echo "$SECONDS $1" >>"$run/beats"
}
fail() {
    printf '%d:%02d %s: %s\n' $((SECONDS / 60)) $((SECONDS % 60)) "$name" "$1" >&2
    exit 1
}

# waits waits up to $1 s until the log $2 holds the text $3 on $4 lines, 1 unless given, and
# fails if they do not come. The texts come from magi/magi.v Verdict.str, the hq:, field:,
# umbilical:, armor:, plug: and release outcome lines of main.v and tools/mock_endpoint.py's first
# line, each of which says that the scripts in scripts/ wait on it.
waits() {
    local n
    for _ in $(seq $(($1 * 5))); do
        n=$(grep -cF "$3" "$2" 2>/dev/null) || true
        if [ "${n:-0}" -ge "${4:-1}" ]; then
            return
        fi
        sleep 0.2
    done
    return 1
}

# beat waits up to $4 s until the log $2 holds the text $3 on $5 lines, 1 unless given, then
# narrates $1, or stops the scene.
beat() {
    waits "$4" "$2" "$3" "${5:-1}" || fail "no \"$3\" in $2 within $4 s; its last line: $(tail -n 1 "$2" 2>/dev/null)"
    say "$1"
}

# ballots prints the newest verdict in HQ's log that contains $1, and the three ballots below,
# and notes the verdict among the beats, where scripts/record.sh finds the votes its GIF loops.
ballots() {
    awk -v v="$1" 'index($0, v) { out = ""; n = 4 } n && n-- { out = out "       " $0 "\n" } END { printf "%s", out }' "$run/hq/hq.log"
    echo "$SECONDS ballots $1" >>"$run/beats"
}
alive() { kill -0 "$1" 2>/dev/null || fail "$2 stopped; its last line: $(tail -n 1 "$3")"; }
start() {
    (cd "$run/$1" && exec "$bin" "$1" >>"$1.log" 2>&1) &
    pids="$pids $!"
}

# up starts the mock, unless the lineup is hosted, with its arguments added to the mock's, then
# the bridge, HQ and the field unit, and narrates each. It leaves bridge, hq and field set to
# their process IDs.
up() {
    if [ "$lineup" != hosted ]; then
        # The units answer after 0.9, 1.7 and 0.5 s, so the bridge shows each one deliberating,
        # 審議中, until its ballot lands, and the core after 2 s, which paces HQ as timed above; the
        # mock answers at once otherwise. The magi lineup asks it for the core alone.
        python3 tools/mock_endpoint.py --listen "127.0.0.1:$mock_port" --quiet --slow melchior=900 \
            --slow balthasar=1700 --slow casper=500 --slow core=2000 "$@" 2>"$run/mock.log" &
        pids="$pids $!"
        waits 5 "$run/mock.log" 'mock: serving' || fail "the mock did not start; $(tail -n 1 "$run/mock.log")"
    fi
    if [ "$lineup" = mock ]; then
        say "mock models on 127.0.0.1:$mock_port, scripted by tools/mock_endpoint.py, so no keys"
    else
        balthasar=Jev
        if [ "${BALTHASAR_BACKEND:-jev}" != jev ]; then
            balthasar=${BALTHASAR_MODEL:-a chat model}
        fi
        say "hosted MAGI: MELCHIOR-1 on $MELCHIOR_MODEL, BALTHASAR-2 on $balthasar and CASPER-3 on $CASPER_MODEL"
        if [ "$lineup" = magi ]; then
            say "the core is the mock's on 127.0.0.1:$mock_port, scripted to release at the beacon whatever the human does"
        else
            say "the core on $CORE_MODEL"
        fi
    fi

    # AppKit reads -NSAppSleepDisabled for this process only, so App Nap cannot slow a window
    # nobody sees while scripts/record.sh saves its frames (CONTRIBUTING.md, V 0.5.2 rule 6).
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
    # shellcheck disable=SC2034 # the scenes read field
    field=$!
    say "field unit up; ${field_note:-a human walks a loop past beacon b1}"
}

# pilot seats tools/pilot.py in the field unit's directory, steering pilot_offset degrees off the
# line to the beacon at pilot_speed m/s for pilot_s seconds. Its arguments go to pilot.py after
# those, and argparse keeps the last of a flag given twice, so a scene can change any of them.
pilot() {
    (cd "$run/field" && exec python3 "$root/tools/pilot.py" --addr "$PLUG_LISTEN" --seconds "$pilot_s" \
        --speed "$pilot_speed" --offset "$pilot_offset" "$@" >>pilot.log 2>&1) &
    pids="$pids $!"
}

SECONDS=0
