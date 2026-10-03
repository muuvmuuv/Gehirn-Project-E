#!/usr/bin/env python3
"""Self check for eval_dummy.outcome and summary: python3 tools/test_eval_dummy.py"""

import json
import math
import os
import tempfile

from eval_dummy import outcome, summary
from pilot import parser

STYLE = parser().parse_args(["--offset", "20"])
AHEAD = [0.6 * 0.7071067811865476, 0.6 * 0.7071067811865476]  # straight at the beacon from (0, -1)


def tick(t: int, seat: str, pose: list[float], target: list[float], correction: bool = False,
         u: list[float] | None = None) -> str:
    return json.dumps({"t_ms": t, "seat": seat, "pose": pose, "target": target, "correction": correction,
                       "u_seat": u or [0.0, 0.0], "scene": []}) + "\n"


RECORDER = [
    tick(10, "pilot", [3.0, 2.1], [3.0, 2.0]),  # a training tick from before the run
    tick(1000, "empty", [-3.5, -2.5], []),  # no goal yet
    tick(1020, "pilot", [-3.4, -2.4], [3.0, 2.0]),
    tick(1040, "dummy", [0.0, -1.0], [3.0, 2.0], u=AHEAD),  # 20 degrees right of this pilot
    tick(1060, "pilot", [0.1, 1.0], [3.0, 2.0], correction=True),
    "{cut line\n",
    tick(4040, "dummy", [2.6, 1.8], [3.0, 2.0], u=[-0.6, 0.0]),  # 0.45 m off, inside the reach, steering away
    tick(4060, "empty", [2.9, 2.0], [3.0, 2.0]),
]
LOG = ("field: plug for \"shinji\"\nplug: dummy plug out of sync at 30%, benched until the pilot is back\n"
       "field: goto(3.00, 2.00)\n")

with tempfile.TemporaryDirectory() as d:
    recorder, log = os.path.join(d, "plug.jsonl"), os.path.join(d, "gehirn.log")
    with open(recorder, "w", encoding="utf-8") as f:
        f.writelines(RECORDER)
    with open(log, "w", encoding="utf-8") as f:
        f.write(LOG)
    got = outcome(recorder, 1000, log, STYLE)
    off_sum = got.pop("off_sum")
    assert got == {"arrived_by": "dummy", "arrive_s": 3.02, "benched": 1, "dummy_ticks": 2, "astray": 1,
                   "corrections": 1}, got
    # 20 degrees off at the first dummy tick, and at the second the reverse of 20 degrees left of the
    # bearing to the beacon.
    assert math.isclose(off_sum, 20.0 + 180.0 - (20.0 + math.degrees(math.atan2(0.2, 0.4)))), off_sum
    assert outcome(os.path.join(d, "none.jsonl"), 0, os.path.join(d, "none.log"), STYLE)["arrived_by"] is None

runs = [{"arrived_by": "dummy", "benched": 0, "release": "on target", "corrections": 0, "dummy_ticks": 10,
         "off_sum": 100.0, "astray": 1},
        {"arrived_by": "empty", "benched": 2, "release": "on target", "corrections": 40, "dummy_ticks": 30,
         "off_sum": 500.0, "astray": 7},
        {"arrived_by": None, "benched": 1, "release": None, "corrections": 2, "dummy_ticks": 0,
         "off_sum": 0.0, "astray": 0}]
assert summary(runs) == {"runs": 3, "arrived": 1, "benched": 2, "on_target": 2, "off_deg": 15.0,
                         "astray_pct": 20.0, "corrections": 42}, summary(runs)

print("eval_dummy: ok")
