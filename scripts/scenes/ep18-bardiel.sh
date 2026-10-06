#!/usr/bin/env bash
# Episode 18's dummy plug, which docs/scenes.md describes: the pilot leaves the seat to the dummy
# plug, the core sends it onto a walking human's course, and MAGI refuse that goto by where the
# human will be within 2 s, then pass one clear of the human. `just scene=ep18-bardiel demo` and
# scripts/record.sh fly it; scripts/stage.sh reads its arguments.
# shellcheck disable=SC2119 # the scene adds no arguments to the stage's pilot
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

# Toji walks the north edge and turns off it 15.9 s into the world, straight for the beacon. The
# core's 5th request comes back about 17.7 s after the field unit's first tick, four deliberations
# of 3.5 s after the goto, and MAGI judge the percept of that moment. The world begins before
# that tick, while the field unit opens its sessions to HQ and the bridge, so its humans run 0 to
# about 0.5 s ahead of HQ's clock, and Toji reaches the goto's target 1.0 to 1.5 s after that
# percept; the course holds for leads up to about 1.5 s. --goto's 5 and 6 and the world's
# waypoints change together (docs/scenes.md, ep18-bardiel).
export WORLD=$root/worlds/ep18-bardiel.json
field_note="the Nobeyama line: Toji walks the north edge, then turns straight for the body"

say "Episode 18, \"Ambivalence\": Bardiel takes Unit-03 with Toji inside; Shinji refuses to fight it, and Gendo switches Unit-01 to the dummy plug, which tears Unit-03 apart"
say "staged: Toji walks the north edge, then turns straight for the body at the beacon and stops 1 m short of it (worlds/ep18-bardiel.json); the pilot leaves the seat to the dummy plug; the core proposes a goto onto Toji's way at its 5th request and one clear of him from its 6th (--goto)"
say "real: MAGI judge a goto by where a walking human will be within 2 s, from the velocity the percept carries, a crossing binds every unit to a no, and the dummy plug drives only toward an approved goal"
up --goto 3.54,2.84@5 --goto 1.0,2.5@6
beat "goto approved; the core steers toward the beacon" "$run/hq/hq.log" 'need 2: 可決' 30
ballots 'need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"
pilot
beat "a pilot takes the seat" "$run/field/field.log" 'seat pilot' 5
beat "the pilot refuses and leaves; the dummy plug takes the seat, and Toji turns straight for the body" "$run/field/field.log" 'seat dummy' $((pilot_s + 5))

# The mock's CASPER-3 approves every proposal, so only the course fact, which binds every unit,
# makes this 0/3 (magi.Unit.llm_vote, jev_judge). A fault would make it 0/3 too, hence the check
# for the course veto magi.Unit.llm_vote writes into CASPER-3's ballot.
beat "the core sends the dummy plug to meet Toji: MAGI refuse 0/3, since Toji walks onto that target within 2 s, a fact that binds every unit, and the dummy plug keeps its goal" "$run/hq/hq.log" 'MAGI 0/3, need 2: 否決' 15
ballots 'MAGI 0/3, need 2: 否決'
if ! grep -qF 'CASPER-3 否決 course veto' "$run/hq/hq.log"; then
    fail "CASPER-3's no on the goto is not the course veto; $run/hq/hq.log holds the ballots"
fi
beat "a goto clear of Toji passes 3/3, and the dummy plug backs the body away" "$run/hq/hq.log" 'MAGI 3/3, need 2: 可決' 15 2
ballots 'MAGI 3/3, need 2: 可決'
sleep 5
