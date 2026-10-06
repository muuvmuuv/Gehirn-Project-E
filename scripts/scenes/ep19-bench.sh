#!/usr/bin/env bash
# Episode 19's benched dummy plug, which docs/scenes.md describes: the dummy plug keeps a sync
# ratio of its own, is benched at 30% and leaves the core to drive alone, and a pilot who sits
# down lifts the bench. `just scene=ep19-bench demo` and scripts/record.sh fly it;
# scripts/stage.sh reads its arguments.
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

# The Geofront with the default world's start, beacon and pillar, so the first pilot's flight
# along the fence, the handover and the bench are the demo's; nothing new comes within the
# reflex's 1.2 m of that track. The evacuee crosses the body's way after the second pilot sits
# down and steps around it, and from about 29 s on nobody is within 4.6 m of the beacon.
export WORLD=$root/worlds/ep19-bench.json
field_note="the Geofront: Gendo stands by the cage, Kaji tends his melons, and an evacuee leaves the crushed shelter"

say "Episode 19, \"Introjection\": Unit-01 rejects the dummy plug, and Shinji returns to pilot it"
say "staged: the Geofront, with NERV's pyramid, Zeruel at its flank, Gendo by the cage, Kaji at his melons and an evacuee from the crushed shelter, who stop or step aside for the body; the dummy plug learns from a pilot who steers 120 degrees off the core's goal, and a second pilot sits down 5 s after the bench"
say "real: the dummy plug's own sync ratio, the bench at 30%, the core driving alone, the bench lifting for a pilot, and the armor slowing the body near a human"
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
beat "a second pilot sits down as the unit passes Kaji's melons: the bench lifts, and the dummy plug's sync starts over" "$run/field/field.log" 'seat pilot' 5 $((seated + 1))
beat "released on target, with nobody within 2.5 m of the beacon" "$run/hq/core.shinji.jsonl" 'released on target' 90
ballots 'need 3: 可決'
if grep -qF 'outcome: contact' "$run/hq/core.shinji.jsonl"; then
    fail "the body touched someone; the journal records a contact"
fi
sleep 5
