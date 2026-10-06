#!/usr/bin/env bash
# Episode 3's cut cable, which docs/scenes.md describes: without HQ there is no quorum, the unit
# runs on internal power and stands still once it is spent, and HQ's pulse reconnects it. `just
# scene=ep03-cable demo` and scripts/record.sh fly it; scripts/stage.sh reads its arguments.
# shellcheck disable=SC2119 # the scene adds no arguments to the stage's up and pilot
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

# 30 s of internal power instead of 5:00, so the counter reaches zero within the scene.
export INTERNAL_BUDGET_MS=30000

# Tokyo-3 with the default world's start, beacon and pillar, so the demo's pilot, dummy plug and
# timings carry over; the boys stand on the mountain, more than 3 m from the beacon, from about
# 0:23. With nobody near the beacon a release would pass, so HQ must die before one reaches
# MAGI, which the check after the kill makes sure of.
export WORLD=$root/worlds/ep03-cable.json
field_note="Tokyo-3: Toji and Kensuke slip out of shelter 334 and climb the shrine's stairs on the mountain east of Shamshel"

say "Episode 3, \"A Transfer\": Toji and Kensuke slip out of their shelter to watch from a shrine on the mountain; Shamshel cuts the umbilical cable and throws Unit-01 beside them, and it fights on internal power until the counter reaches zero and it stops"
say "staged: Tokyo-3, with beacon shamshel where the Angel falls and the boys walking from shelter 334 to the shrine; HQ is killed as the dummy plug takes the seat, before the release reaches MAGI, so a dummy plug sits at zero where Shinji did, and internal power lasts 0:30 instead of 5:00"
say "real: each boy stands still while the body is within 2.5 m of him, the grace, 40 s as the demo sets it, no quorum without HQ, the goal falling back to hold at zero, which leaves the core and the dummy plug nothing to steer, the reconnect on HQ's pulse, and the release after it, with both boys more than 3 m away"
up
beat "goto approved; the core steers toward the beacon" "$run/hq/hq.log" 'need 2: 可決' 30
ballots 'need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"
pilot
beat "a pilot takes the seat" "$run/field/field.log" 'seat pilot' 5
beat "the pilot leaves; the dummy plug flies the approved goto" "$run/field/field.log" 'seat dummy' $((pilot_s + 5))
kill "$hq"
if grep -qF 'need 3:' "$run/hq/hq.log"; then
    fail "a release reached MAGI before HQ was killed"
fi
say "HQ killed: the cable goes silent before the release reaches MAGI, and the field unit waits out the grace, 40 s as the demo sets it"
beat "the cable counts as cut; internal power, 0:30 counting down; without HQ no quorum, so the payload stays aboard" "$run/field/field.log" 'connected to internal' 50
beat "internal power spent: the goal falls back to hold, which leaves the core and the dummy plug nothing to steer, so the body stands where it is, at Shamshel" "$run/field/field.log" 'internal to depleted' 40
sleep 5
start hq
say "HQ restarted"
beat "cable reconnected: HQ's pulse powers the body again" "$run/field/field.log" 'depleted to connected' 20
beat "released on target: the release HQ never got to put passes 3/3 after the reconnect, with both boys more than 3 m away" "$run/hq/core.shinji.jsonl" 'released on target' 60
ballots 'need 3: 可決'
sleep 5
