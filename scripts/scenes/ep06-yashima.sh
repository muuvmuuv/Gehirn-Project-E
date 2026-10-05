#!/usr/bin/env bash
# Operation Yashima's vote, from Episode 6, which docs/scenes.md describes: two of three MAGI move
# the body, since a goto is reversible, and the same two of three cannot release. `just
# scene=ep06-yashima demo` and scripts/record.sh fly it; scripts/stage.sh reads its arguments.
# shellcheck disable=SC2119 # the scene adds no arguments to the stage's pilot
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

say "Episode 6, \"Rei II\": MAGI back Operation Yashima with two votes for and one conditional yes"
say "staged: CASPER-3 votes no on everything; its forced no stands in for the canon's conditional yes, which gehirn has no ballot for, since a ballot is yes or no"
say "real: a simple majority moves the body, and an irreversible act needs every unit"
up --vote casper=reject
beat "goto approved 2/3: CASPER-3 says no, but a goto is reversible, so two of three send the unit out" "$run/hq/hq.log" 'MAGI 2/3, need 2: 可決' 30
ballots 'MAGI 2/3, need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"

# The demo's pilot and dummy plug bring the body to the beacon on the demo's clock, unnarrated.
pilot

# The first release vote, with the human within reach, goes 0/3 and is not narrated.
beat "release refused 2/3: the same two of three cannot release, since a release is irreversible and needs all three" "$run/hq/hq.log" 'MAGI 2/3, need 3: 否決' 90
ballots 'MAGI 2/3, need 3: 否決'
sleep 5
