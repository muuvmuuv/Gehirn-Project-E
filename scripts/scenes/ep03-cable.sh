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

say "Episode 3, \"A Transfer\": Shamshel cuts the umbilical cable, and Unit-01 fights on internal power until the counter reaches zero and it stops"
say "staged: HQ is killed as the dummy plug takes the seat, before the release reaches MAGI, so a dummy plug sits at zero where Shinji did, and internal power lasts 0:30 instead of 5:00"
say "real: the grace, 40 s as the demo sets it, no quorum without HQ, the goal falling back to hold at zero, which leaves the core and the dummy plug nothing to steer, the reconnect on HQ's pulse, and the release after it"
up
beat "goto approved; the core steers toward the beacon" "$run/hq/hq.log" 'need 2: 可決' 30
ballots 'need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"
pilot
beat "a pilot takes the seat" "$run/field/field.log" 'seat pilot' 5
beat "the pilot leaves; the dummy plug flies the approved goto" "$run/field/field.log" 'seat dummy' $((pilot_s + 5))
kill "$hq"
say "HQ killed: the cable goes silent before the release reaches MAGI, and the field unit waits out the grace, 40 s as the demo sets it"
beat "the cable counts as cut; internal power, 0:30 counting down; without HQ no quorum, so the payload stays aboard" "$run/field/field.log" 'connected to internal' 50
beat "internal power spent: the goal falls back to hold, which leaves the core and the dummy plug nothing to steer, so the body stands still" "$run/field/field.log" 'internal to depleted' 40
sleep 5
start hq
say "HQ restarted"
beat "cable reconnected: HQ's pulse powers the body again" "$run/field/field.log" 'depleted to connected' 20
beat "released on target: the release HQ never got to put passes 3/3 after the reconnect" "$run/hq/core.shinji.jsonl" 'released on target' 60
ballots 'need 3: 可決'
sleep 5
