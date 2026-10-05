#!/usr/bin/env bash
# Episode 19's benched dummy plug, which docs/scenes.md describes: the dummy plug keeps a sync
# ratio of its own, is benched at 30% and leaves the core to drive alone, and a pilot who sits
# down lifts the bench. `just scene=ep19-bench demo` and scripts/record.sh fly it;
# scripts/stage.sh reads its arguments.
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

say "Episode 19, \"Introjection\": Unit-01 rejects the dummy plug, and Shinji returns to pilot it"
say "staged: the dummy plug learns from a pilot who steers 120 degrees off the core's goal, and a second pilot sits down 5 s after the bench"
say "real: the dummy plug's own sync ratio, the bench at 30%, the core driving alone, and the bench lifting for a pilot"
# shellcheck disable=SC2119 # the scene adds no arguments to the mock's
up
beat "goto approved; the core steers toward the beacon" "$run/hq/hq.log" 'need 2: 可決' 30
ballots 'need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"
pilot --offset 120
beat "a pilot takes the seat and steers 120 degrees off the core's goal: its sync falls, and at 30% or below the core only advises" "$run/field/field.log" 'seat pilot' 5
beat "the pilot leaves; the dummy plug, cloned from that pilot, takes the seat and falls out of sync within a second: benched at 30%, and the core drives alone at 0.4 m/s" "$run/field/field.log" 'benched until the pilot is back' $((pilot_s + 5))
seated=$(grep -cF 'seat pilot' "$run/field/field.log")
sleep 5
pilot --offset 0 --avoid 1.2 --seconds 40
beat "a second pilot sits down: the bench lifts, and the dummy plug's sync starts over" "$run/field/field.log" 'seat pilot' 5 $((seated + 1))
beat "released on target" "$run/hq/core.shinji.jsonl" 'released on target' 90
ballots 'need 3: 可決'
sleep 5
