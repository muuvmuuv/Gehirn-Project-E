#!/usr/bin/env python3
"""Self check for staging's keys and its line: python3 tools/test_staging.py"""

from mock_endpoint import FENCE
from staging import OUTSIDE, press, show

SCRIPT = {"vote": {"melchior": None, "balthasar": None, "casper": None}, "goto": None, "propose": None}


def staged(**kw: object) -> dict:
    """Return the mock's answer to /stage with kw in place of the script."""
    votes = {u: kw.pop(u, None) for u in SCRIPT["vote"]}
    return {**SCRIPT, **kw, "vote": votes}


# m and c cycle their unit through forced approve, forced reject and the script.
for vote, body in ((None, "approve"), ("approve", "reject"), ("reject", "off")):
    assert press("m", staged(melchior=vote)) == {"vote": f"melchior={body}"}, vote
    assert press("c", staged(casper=vote)) == {"vote": f"casper={body}"}, vote
assert press("g", SCRIPT) == {"goto": OUTSIDE} and press("g", staged(goto=[6.0, 0.0])) == {"goto": "off"}
assert press("p", SCRIPT) == {"propose": "self_destruct"}
assert press("p", staged(propose="self_destruct")) == {"propose": "off"}
assert press("x", SCRIPT) == {"clear": True}
for key in ("b", "q", "\n", " ", "M"):
    assert press(key, SCRIPT) is None, key
assert max(abs(float(v)) for v in OUTSIDE.split(",")) > FENCE

assert show(SCRIPT) == "staging: melchior script, balthasar script, casper script; core script"
assert show(staged(casper="reject", goto=[6.0, 0.0])) == (
    "staging: melchior script, balthasar script, casper reject; core goto(6.00, 0.00)")
assert show(staged(goto=[6.0, 0.0], propose="self_destruct")).endswith("core self_destruct")

print("staging: ok")
