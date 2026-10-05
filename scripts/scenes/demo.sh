#!/usr/bin/env bash
# The demo: the whole mission, narrated beat by beat, from the goto through the refused and the
# approved release to the cut cable and the reconnect, with HQ, the field unit and the bridge
# apart. `just demo` and scripts/record.sh fly it; scripts/stage.sh reads its arguments.
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"
reconnect_s=5

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

up
beat "goto approved; the core steers toward the beacon" "$run/hq/hq.log" 'need 2: 可決' 30
ballots 'need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"
pilot
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
