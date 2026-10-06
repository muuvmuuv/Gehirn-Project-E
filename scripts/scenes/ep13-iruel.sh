#!/usr/bin/env bash
# Episode 13's MAGI hack, which docs/scenes.md describes: an unknown verb counts as irreversible
# and needs all three units, one holdout blocks it, and the armor refuses it even 3/3. `just
# scene=ep13-iruel demo` and scripts/record.sh fly it; scripts/stage.sh reads its arguments.
set -euo pipefail

# shellcheck source=scripts/stage.sh
source "$(dirname "${BASH_SOURCE[0]}")/../stage.sh"

# On Jev BALTHASAR-2 rejects every verb outside lcl.known_verbs whatever the mock answers
# (magi/jev.v jev_judge), so it runs on a chat model, as lineup C does; three model names keep
# Invariant 4's check.
export BALTHASAR_BACKEND=llm BALTHASAR_MODEL=mock-balthasar

# NERV HQ's MAGI room, where the body stands alone and nobody comes nearer it than Misato, at
# 3.9 m. The units refuse the unknown verb before they read a distance, and the armor before it
# measures one, so the room moves no beat.
export WORLD=$root/worlds/ep13-iruel.json
field_note="NERV HQ's MAGI room: Ritsuko, Maya and Misato head for CASPER's open hatch, and Hyuga and Aoba stay at their consoles"

say "Episode 13, \"Lilliputian Hitcher\": an Angel takes the MAGI one unit at a time and calls for self destruct"
say "staged: the MAGI room of NERV HQ, the three units as towers and CASPER's open hatch as the beacon; the mock forces each fall, which three model families would not share (Invariant 4): the Angel holds the core too, since in gehirn only the core proposes, and it proposes self_destruct, a verb outside its schema, on every request; MELCHIOR-1 approves it from the first vote, BALTHASAR-2 from the second, and CASPER-3 refuses until the third; BALTHASAR-2 runs on a chat model, since on Jev gehirn refuses every verb it does not know"
say "real: an unknown verb counts as irreversible and needs all three units, the cooldown spaces the votes, and the armor permits only verbs the body has"
up --propose 'self_destruct:Self destruct.' --vote melchior=approve \
    --vote balthasar=approve@2 --vote casper=reject --vote casper=approve@3
beat "the Angel holds MELCHIOR-1: self_destruct is no verb gehirn knows, so it counts as irreversible and needs all three; BALTHASAR-2 refuses it unforced, by the mock's script, CASPER-3 as staged" "$run/hq/hq.log" 'MAGI 1/3, need 3: 否決' 20
ballots 'MAGI 1/3, need 3: 否決'
beat "BALTHASAR-2 falls: two of three, and CASPER-3 alone still blocks it" "$run/hq/hq.log" 'MAGI 2/3, need 3: 否決' 25
ballots 'MAGI 2/3, need 3: 否決'
beat "had Ritsuko been a second late: CASPER-3 falls, and MAGI approve 3/3" "$run/hq/hq.log" 'MAGI 3/3, need 3: 可決' 25
ballots 'MAGI 3/3, need 3: 可決'
beat "the armor refuses: self_destruct is no verb the body has, so MAGI's approval is never enough (Invariant 5)" "$run/field/field.log" 'armor: self_destruct refused' 5
sleep 5
