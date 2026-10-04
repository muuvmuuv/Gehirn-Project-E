#!/usr/bin/env python3
"""Self check for eval_dummy.outcome, pilot_ticks, plug_up and summary: python3 tools/test_eval_dummy.py"""

import json
import math
import os
import re
import tempfile
from pathlib import Path

from eval_dummy import KNN_LIMIT, outcome, pilot_ticks, plug_up, summary
from pilot import parser

STYLE = parser().parse_args(["--offset", "20"])
AHEAD = [0.6 * 0.7071067811865476, 0.6 * 0.7071067811865476]  # straight at the beacon from (0, -1)


def tick(t: int, seat: str, pose: list[float], target: list[float], correction: bool = False,
         u: list[float] | None = None, sync: float = 0.5, scene: list[dict] | None = None) -> str:
    return json.dumps({"t_ms": t, "seat": seat, "pose": pose, "target": target, "correction": correction,
                       "u_seat": u or [0.0, 0.0], "sync": sync, "scene": scene or []}) + "\n"


# From (0, -1) the pillar's rim lies 0.1 m inside the body's center and the human's 0.7 m away.
SCENE = [{"kind": "obstacle", "pos": [0.0, -0.3], "r": 0.8}, {"kind": "human", "pos": [1.0, -1.0], "r": 0.3}]


RECORDER = [
    tick(10, "pilot", [3.0, 2.1], [3.0, 2.0]),  # a training tick from before the run
    tick(1000, "empty", [-3.5, -2.5], []),  # no goal yet
    tick(1020, "pilot", [-3.4, -2.4], [3.0, 2.0]),
    tick(1040, "dummy", [0.0, -1.0], [3.0, 2.0], u=AHEAD, sync=0.42, scene=SCENE),  # 20 degrees right of this pilot
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
    off_sum, human_gap = got.pop("off_sum"), got.pop("human_gap")
    assert got == {"arrived_by": "dummy", "arrive_s": 3.02, "benched": 1, "dummy_ticks": 2, "astray": 1,
                   "corrections": 1, "low_sync": 0.42, "near_solid": 1}, got
    assert math.isclose(human_gap, 0.7), human_gap
    # 20 degrees off at the first dummy tick, and at the second the reverse of 20 degrees left of the
    # bearing to the beacon.
    assert math.isclose(off_sum, 20.0 + 180.0 - (20.0 + math.degrees(math.atan2(0.2, 0.4)))), off_sum
    none = outcome(os.path.join(d, "none.jsonl"), 0, os.path.join(d, "none.log"), STYLE)
    assert none["arrived_by"] is None and none["human_gap"] is None and none["low_sync"] == 1.0, none

    # The three pilot ticks toward a goal, the one 0.1 m short of it included.
    assert pilot_ticks([recorder, recorder]) == 6, pilot_ticks([recorder])
    assert plug_up(log) and not plug_up(recorder) and not plug_up(os.path.join(d, "none.log"))

dummy = (Path(__file__).parent.parent / "plug" / "dummy.v").read_text()
assert re.search(rf"\blimit +int = {KNN_LIMIT}\b", dummy), "plug/dummy.v Dummy.limit"

runs = [{"arrived_by": "dummy", "arrive_s": 9.0, "benched": 0, "release": "on target", "corrections": 0,
         "dummy_ticks": 10, "off_sum": 100.0, "astray": 1, "low_sync": 0.55, "near_solid": 3, "human_gap": 0.4},
        {"arrived_by": "empty", "arrive_s": 12.0, "benched": 2, "release": "on target", "corrections": 40,
         "dummy_ticks": 30, "off_sum": 500.0, "astray": 7, "low_sync": 0.3, "near_solid": 0, "human_gap": None},
        {"arrived_by": None, "arrive_s": None, "benched": 1, "release": None, "corrections": 2, "dummy_ticks": 0,
         "off_sum": 0.0, "astray": 0, "low_sync": 1.0, "near_solid": 5, "human_gap": 1.5}]
assert summary(runs) == {"runs": 3, "arrived": 1, "benched": 2, "on_target": 2, "off_deg": 15.0,
                         "astray_pct": 20.0, "corrections": 42, "arrive_s": 9.0, "low_sync": 0.3,
                         "near_solid": 8, "human_gap": 0.4}, summary(runs)

print("eval_dummy: ok")
