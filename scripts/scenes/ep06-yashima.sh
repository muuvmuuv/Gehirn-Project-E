#!/usr/bin/env bash
# Operation Yashima's vote, from Episode 6, which docs/scenes.md describes: two of three MAGI move
# the body, since a goto is reversible, and the same two of three cannot release. `just
# scene=ep06-yashima demo` and scripts/record.sh fly it; scripts/stage.sh reads its arguments.
# shellcheck disable=SC2119 # the scene adds no arguments to the stage's pilot
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

# Mt. Futago, where the body reaches the firing point about 17.5 s after the field unit starts.
# Rei circles the gunner 1.8 m out until about 27.5 s and then stands 3.2 m in front of it, so
# MAGI judge the first release, on a percept from about 21 s, with her within reach, and the
# next, 12.2 s later, with her away. Her speed and way and the start move both together.
export WORLD=$root/worlds/ep06-yashima.json
field_note="Mt. Futago: Rei comes up to guard the firing point, and Toji and Kensuke watch from the west"

say "Episode 6, \"Rei II\": MAGI back Operation Yashima with two votes for and one conditional yes"
say "staged: Mt. Futago, with the firing point as the beacon, the substation behind it and Ramiel 7.4 m away across the map; Rei circles the gunner and then stands in front of it, and Toji and Kensuke watch; CASPER-3 votes no on everything, its forced no standing in for the canon's conditional yes, which gehirn has no ballot for, since a ballot is yes or no"
say "real: a simple majority moves the body, an irreversible act needs every unit, and a release needs nobody within reach"
up --vote casper=reject
beat "goto approved 2/3: CASPER-3 says no, but a goto is reversible, so two of three send the unit out" "$run/hq/hq.log" 'MAGI 2/3, need 2: 可決' 30
ballots 'MAGI 2/3, need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"

# The demo's pilot and dummy plug bring the body to the firing point on the demo's clock,
# unnarrated.
pilot
beat "the first shot: release refused 0/3, since Rei is within reach of the gunner" "$run/hq/hq.log" 'MAGI 0/3, need 3: 否決' 90
ballots 'MAGI 0/3, need 3: 否決'
say "the ${cooldown_s} s cooldown stands for new fuses, cooling and the reload; Rei walks out in front of the gunner, toward Ramiel"
beat "the second shot: release refused 2/3, since the same two of three cannot release, which is irreversible and needs all three" "$run/hq/hq.log" 'MAGI 2/3, need 3: 否決' 30
ballots 'MAGI 2/3, need 3: 否決'
sleep 5
