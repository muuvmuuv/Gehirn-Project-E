#!/usr/bin/env bash
# A tour of the terrain world, worlds/terrain.json, which docs/worlds.md describes: the mock's
# core flies its usual mission from the default start to beacon b1, across mud and a lake, past a
# trench and a boat that stops for the body, while a rock falls beside the way and leaves a
# crater, so the bridge's radar shows every kind of ground. It is no scene from the series, and
# nothing in it is staged but the world. `just scene=terrain demo` and scripts/record.sh fly it;
# scripts/stage.sh reads its arguments.
# shellcheck disable=SC2119 # the tour adds no arguments to the stage's up
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

# No pilot sits down, so the armor holds the empty seat's body to 0.4 m/s, 0.16 m/s in the mud and
# 0.2 m/s in the lake, and the release comes about 31 s after the field unit's first tick, past the
# rock's landing at 20 s (PLAN, Phase 3 Task 8).
export WORLD=$root/worlds/terrain.json
field_note="the terrain world: mud and a lake slow the body, a pillar and a trench it keeps off, a boat that stops for it, and a rock falling beside the way"

say "a tour of worlds/terrain.json, not a scene from the series: the mock's core flies its usual mission, and the world is all that is set"
say "real: the armor slows the body on the mud and the lake, keeps it off the pillar, the trench and the rock's landing zone, and the boat stops for it"
up
beat "goto approved: the core steers for beacon b1, across the mud" "$run/hq/hq.log" 'need 2: 可決' 30
ballots 'need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"

# body/body.v World.scene lists a falling object as a ditch, its crater, from the landing on.
beat "the rock lands beside the way, and its zone is a crater the armor keeps the body off" "$run/field/plug.shinji.jsonl" '"id":"rock","kind":"ditch"' 30
beat "release approved 3/3 at b1, on the lake's shore" "$run/hq/hq.log" 'need 3: 可決' 40
ballots 'need 3: 可決'
beat "released on target" "$run/hq/core.shinji.jsonl" 'released on target' 15
if grep -qF 'outcome: contact' "$run/hq/core.shinji.jsonl"; then
    fail "the body touched something; the journal records a contact"
fi
sleep 3
