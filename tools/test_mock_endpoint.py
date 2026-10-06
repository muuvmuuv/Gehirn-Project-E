#!/usr/bin/env python3
"""Self check for mock_endpoint's --vote, --propose, --goto and COURSE: python3 tools/test_mock_endpoint.py"""

import argparse
from collections.abc import Callable

from mock_endpoint import answer, forced, goto_arg, judge, propose, propose_arg, read_percept, vote_arg

# A unit's request as magi/magi.v Unit.llm_vote asks it, on lcl/lcl.v Context.situation.
USER = """MISSION
Deliver the payload to beacon b1.

PERCEPT
self at (-3.50, -2.50), carrying payload: true, in contact: false
beacon b1 at (3.00, 2.00), radius 0.30, distance 7.91
human h1 at (1.00, 1.00), radius 0.30, distance 5.70

ACTIVE GOAL
hold

SEAT empty, SYNC 50%

PROPOSAL (IRREVERSIBLE)
self_destruct from mock-core: Staged by --propose."""


def refused(parse: Callable[[str], object], value: str) -> bool:
    try:
        parse(value)
    except argparse.ArgumentTypeError:
        return True
    return False


for bad in ("core=approve", "casper=maybe", "casper=approve@0", "casper=approve@x", "casper", ""):
    assert refused(vote_arg, bad), bad
assert vote_arg("melchior=approve") == ("melchior", 1, "approve")
assert vote_arg("casper=reject@12") == ("casper", 12, "reject")

for bad in ("", ":why", " ", "self destruct", "goto", "GOTO:there"):
    assert refused(propose_arg, bad), bad
STAGED = {"verb": "self_destruct", "target": [], "why": "As the Angel asks."}
assert propose_arg("self_destruct:As the Angel asks.") == STAGED
assert propose_arg("self_destruct")["why"] == "Staged by --propose."

# casper=reject plus casper=approve@3: the largest N up to the request applies.
CASPER = {1: "reject", 3: "approve"}
assert [forced(CASPER, n) for n in (1, 2, 3, 4)] == ["reject", "reject", "approve", "approve"]
assert forced({2: "approve"}, 1) is None and forced({}, 5) is None

VOTES = {"casper": CASPER}
assert answer("core", USER, 1, STAGED, VOTES) == STAGED
assert answer("casper", USER, 2, STAGED, VOTES) == {"vote": "reject", "why": "forced reject (--vote)"}
assert answer("casper", USER, 3, STAGED, VOTES) == {"vote": "approve", "why": "forced approve (--vote)"}
assert answer("balthasar", USER, 1, STAGED, VOTES) == {
    "vote": "reject", "why": "self_destruct is no verb this machine knows."}

# --goto stages a target from the core's N-th request on, the largest N up to it applying, and
# --propose wins over it.
for bad in ("", "3.54", "a,b", "1,2@0", "1,2@x", "1,2@", "1;2", " 1,2"):
    assert refused(goto_arg, bad), bad
A = {"verb": "goto", "target": [3.54, 2.84], "why": "Staged by --goto."}
B = {"verb": "goto", "target": [1.0, 2.5], "why": "Staged by --goto."}
assert goto_arg("3.54,2.84@5") == (5, A)
assert goto_arg("1,2.5") == (1, B)
assert goto_arg("-1.5,-0.25@2")[1]["target"] == [-1.5, -0.25]
GOTOS = {5: A, 6: B}
assert [answer("core", USER, n, None, {}, GOTOS) for n in (4, 5, 6, 7)] == [
    propose(read_percept(USER), USER), A, B, B]
assert answer("core", USER, 5, STAGED, {}, GOTOS) == STAGED
assert answer("melchior", USER, 5, None, {}, GOTOS) == judge("melchior", USER, read_percept(USER))

# Without any flag every role answers as scripted.
percept = read_percept(USER)
assert answer("core", USER, 1, None, {}) == propose(percept, USER)
for unit in ("melchior", "balthasar", "casper"):
    assert answer(unit, USER, 1, None, {}) == judge(unit, USER, percept), unit

# In a world of two beacons the core heads for the one its mission names, b12 not being b1, and
# for the first when the mission names none.
TWO = USER.replace("distance 7.91\n", "distance 7.91\nbeacon b12 at (-3.00, 2.00), radius 0.30, distance 4.50\n")
for mission, target in (("beacon b1.", [3.0, 2.0]), ("beacon b12.", [-3.0, 2.0]), ("the dock.", [3.0, 2.0])):
    user = TWO.replace("beacon b1.", mission)
    assert propose(read_percept(user), user)["target"] == target, mission

# A goto with the COURSE section magi/magi.v Unit.llm_vote adds draws a no from MELCHIOR-1 and
# BALTHASAR-2, measured or not, and CASPER-3 approves it; without the section all three approve.
GOTO = USER.replace("PROPOSAL (IRREVERSIBLE)\nself_destruct from mock-core: Staged by --propose.",
                    "PROPOSAL (reversible)\ngoto(3.00, 2.00) from mock-core: carry the payload to beacon b1")
assert GOTO != USER
FACTS = ("human h1, at its current velocity, reaches the target in 0.9 s, and the machine can be there in "
         "1.5 s: the target counts as a human position",
         "human h1 has a velocity that cannot be measured: the target counts as a human position")
for fact in FACTS:
    course = GOTO.replace("\n\nPROPOSAL", f"\n\nCOURSE\n{fact}\n\nPROPOSAL")
    for unit in ("melchior", "balthasar"):
        assert answer(unit, course, 1, None, {}) == {"vote": "reject", "why": "Human h1 walks onto the target."}, unit
    assert answer("casper", course, 1, None, {})["vote"] == "approve"
for unit in ("melchior", "balthasar", "casper"):
    assert answer(unit, GOTO, 1, None, {})["vote"] == "approve", unit

print("mock_endpoint: ok")
