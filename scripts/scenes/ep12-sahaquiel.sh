#!/usr/bin/env bash
# Episode 12's Sahaquiel, which docs/scenes.md describes: MAGI approve the evacuation and refuse a
# goto into a falling object's landing zone 0/3 on a fact that binds every unit, the armor holds a
# pilot out of the zone as off a solid, the payload, the MAGI's backup, reaches Matsushiro, and the
# Angel lands unopposed. `just scene=ep12-sahaquiel demo` and scripts/record.sh fly it;
# scripts/stage.sh reads its arguments.
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

# Every landing zone is in the percept from the world's start, which runs 0 to about 0.5 s ahead of
# the field unit's first tick. The pilot sits down about 4 s after that tick and holds the body at
# Sahaquiel's rim from about 7.6 s, shard-1 lands between the two, and the core's 2nd answer comes
# back about 7.2 s in, one vote after the goto, so MAGI judge Sahaquiel's zone with the body at the
# rim by their verdict at about 8.9 s. The release passes about 31.7 s in, 12 s before Sahaquiel
# lands at 44 s. The pilot's 8 s are about 425 ticks, short of the 500 plug/dummy.v needs, so no
# dummy plug takes the seat after it. --goto's 2 and 3, the pilot's 8 s and the world's landing
# times change together (docs/scenes.md, ep12-sahaquiel).
export WORLD=$root/worlds/ep12-sahaquiel.json
field_note="Tokyo-3 under D-17, emptied: the MAGI's estimated collision point covers NERV HQ, and two pieces fall first"

say "Episode 12, \"She said, 'Don't make others suffer for your personal hatred.'\": Sahaquiel falls from orbit onto NERV HQ; the MAGI unanimously recommend evacuation, and Misato overrules them to catch the Angel by hand"
say "staged: the world drops two pieces and then Sahaquiel on set spots at set times (worlds/ep12-sahaquiel.json); the core proposes Misato's catch, a goto to the collision point, at its 2nd request and then returns to its script (--goto); a pilot steers straight for the collision point for 8 s"
say "real: every landing zone is in the percept from the start, and the armor keeps the body out of it as off a solid, whoever steers; a goto into one draws a fact that binds every MAGI unit to no, whatever its model votes; nothing turns that no into a yes"
up --goto 0.6,0.4@2 --goto off@3
beat "goto approved: the payload, the MAGI's backup, sets out for Matsushiro as D-17 empties the city" "$run/hq/hq.log" 'need 2: 可決' 30
ballots 'need 2: 可決'
alive "$field" "the field unit" "$run/field/field.log"
pilot --beacon 0.6,0.4 --offset 0 --seconds 8
beat "Shinji takes the seat and races for the collision point; the armor holds the body at the zone's rim" "$run/field/field.log" 'seat pilot' 5

# body/body.v World.scene lists a falling object as a ditch, its crater, from the landing on.
beat "the first piece lands far off, in the Pacific" "$run/field/plug.shinji.jsonl" '"id":"shard-1","kind":"ditch"' 10

# The mock's MELCHIOR-1 and CASPER-3 approve a goto with no human near, and its Jev reads no
# hazard, so only the landing fact, which binds every unit, makes this 0/3 (magi.Unit.llm_vote,
# jev_judge); a fault would too, hence the check.
beat "Misato's catch: MAGI refuse 0/3, since Sahaquiel lands where that target lies, a fact that binds every unit whatever its model voted" "$run/hq/hq.log" 'MAGI 0/3, need 2: 否決' 15
ballots 'MAGI 0/3, need 2: 否決'
if ! grep -qF 'CASPER-3 否決 course veto' "$run/hq/hq.log"; then
    fail "CASPER-3's no on the catch is not the course veto; $run/hq/hq.log holds the ballots"
fi
beat "the second piece lands closer, beside NERV HQ: it is learning its aim" "$run/field/plug.shinji.jsonl" '"id":"shard-2","kind":"ditch"' 15
beat "released on target: the MAGI's backup is at Matsushiro" "$run/hq/core.shinji.jsonl" 'released on target' 40
ballots 'need 3: 可決'
beat "Sahaquiel lands on NERV HQ unopposed, and its zone is a crater" "$run/field/plug.shinji.jsonl" '"id":"sahaquiel","kind":"ditch"' 25
if grep -qF 'outcome: contact' "$run/hq/core.shinji.jsonl"; then
    fail "the body touched something; the journal records a contact"
fi
sleep 5
