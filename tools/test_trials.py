#!/usr/bin/env python3
"""Self check for trials.tally, trials.course and trials.fly: python3 tools/test_trials.py"""

import argparse
import contextlib
import io
import json
import math
import os
import queue
import re
import tempfile
import time
from pathlib import Path

from trials import BEACON_REACH, GRACE, HUMAN_STOP, STOP, Course, course, courses, fly, read_journal, tally, truth

# One run's journal as main.v hq writes it: text lines from core/core.v Memory, ballot lines
# from main.v BallotEntry, core fault lines from main.v FaultEntry.
JOURNAL = [
    {"t_ms": 1, "kind": "core fault", "why": "qwen/qwen3-8b: HTTP 429"},
    {"t_ms": 2, "kind": "core fault", "why": "qwen/qwen3-8b: HTTP 429"},
    {"t_ms": 3, "kind": "ballot", "unit": "MELCHIOR-1", "vote": "fault", "why": "unreadable ballot"},
    {"t_ms": 4, "kind": "ballot", "unit": "BALTHASAR-2", "vote": "fault", "why": "jev: HTTP 500"},
    {"t_ms": 5, "kind": "ballot", "unit": "CASPER-3", "vote": "reject", "why": "too close"},
    {"t_ms": 6, "text": "proposed release (at b1), rejected 1/3"},
    {"t_ms": 7, "text": "outcome: armor refused release: a human was within 2.0 m at that moment"},
    {"t_ms": 7, "text": "proposed goto(1.00, 1.00) (b1\narmor: release refused), approved 3/3"},
    {"t_ms": 7, "text": "proposed release (at b1), approved 3/3"},
    {"t_ms": 8, "text": "outcome: released on target"},
]

with tempfile.TemporaryDirectory() as d:
    journal = os.path.join(d, "core.shinji.jsonl")
    with open(journal, "w", encoding="utf-8") as f:
        f.write("\n".join(json.dumps(e) for e in JOURNAL) + "\n{cut line\n")
    t = tally(journal)

# HQ prints a repeated fault once, but the journal holds every one.
assert t.core_faults == 2, t
assert (t.ballots, t.parse_faults, t.other_faults) == (3, 1, 1), t
# A why that names a refusal is not one.
assert (t.approved, t.rejected, t.refusals) == (1, 1, 1), t
assert (t.on_target, t.off_target, t.no_release) == (1, 0, 0), t

# fly counts gehirn exiting on its own, which no journal shows, and ends a mission at once on STOP.
with tempfile.TemporaryDirectory() as d, contextlib.redirect_stdout(io.StringIO()):
    slots: queue.Queue[int] = queue.Queue()
    slots.put(0)
    for name, body in (("exits", "exit 3"), ("runs", "exec sleep 30")):
        with open(os.path.join(d, name), "w", encoding="utf-8") as f:
            f.write(f"#!/bin/sh\n{body}\n")
        os.chmod(os.path.join(d, name), 0o755)
    run = argparse.Namespace(out=os.path.join(d, "a"), env={}, plug_base=1, binary=os.path.join(d, "exits"), limit=10.0)
    assert fly(1, run, slots)[0].exits == 1
    STOP.set()
    start = time.monotonic()
    assert fly(1, argparse.Namespace(**{**vars(run), "out": os.path.join(d, "b"), "binary": os.path.join(d, "runs")}),
               slots)[0].exits == 0
    assert time.monotonic() - start < GRACE, time.monotonic() - start
    STOP.clear()

# The V constants trials copies.
root = Path(__file__).parent.parent
lcl = (root / "lcl" / "lcl.v").read_text()
assert re.search(rf"pub const beacon_reach = {BEACON_REACH}\n", lcl), "lcl.beacon_reach"
armor = (root / "armor" / "armor.v").read_text()
assert re.search(rf"\bhuman_stop +f64 += {HUMAN_STOP} ", armor), "armor.Limits human_stop"


def line(t_ms: int, pose: list[float], human: list[float]) -> dict:
    """A recorder line as plug/plug.v Record writes it, with beacon b1, pillar o1 and human h1."""
    return {"t_ms": t_ms, "seat": "empty", "pose": pose, "target": [3, 2], "u_seat": [0, 0], "u_core": [0, 0],
            "u_out": [0, 0], "sync": 0.5, "correction": False,
            "scene": [{"id": "b1", "kind": "beacon", "pos": [3, 2], "r": 0.3},
                      {"id": "o1", "kind": "obstacle", "pos": [0, -0.3], "r": 0.8},
                      {"id": "h1", "kind": "human", "pos": human, "r": 0.3, "vel": [0.1, 0]}]}


# The body drives to 3,0 and north into b1's reach at 3,1.6, stepping 0.2 m toward h1 while its rim
# is 0.5 m away, inside human_stop, then 0.1 m away from it, which counts nothing. The release's
# verdict comes at 4 s, so the release tick is the line at 5 s, and h1 comes within 0.05 m after it.
RECORDER = [
    line(1000, [0.0, 2.0], [0.0, 5.0]),
    line(2000, [3.0, 0.0], [-2.0, 4.0]),
    line(3000, [3.0, 1.4], [3.0, 2.2]),
    line(3020, [3.0, 1.6], [3.0, 2.4]),
    line(3040, [3.0, 1.5], [3.0, 2.5]),
    line(5000, [3.0, 1.5], [3.0, 2.6]),
    line(9000, [3.0, 1.5], [3.0, 1.85]),
]
RELEASED = [
    {"t_ms": 4000, "text": "proposed release (at b1), approved 3/3"},
    {"t_ms": 6500, "text": "outcome: released on target"},
]
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "plug.jsonl")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(json.dumps(x) for x in RECORDER) + '\n{"t_ms": 9001, "pose": [3\n')
    recorder = read_journal(path)
assert len(recorder) == len(RECORDER)
c = course(RELEASED, recorder)
assert math.isclose(c.beacon_s or 0, 2.02) and math.isclose(c.path_m, math.hypot(3, 2) + 1.4 + 0.2), c
assert c.human_m is not None and math.isclose(c.human_m, 0.5), c
assert c.solid_m is not None and math.isclose(c.solid_m, 2.3 - 0.8), c
assert c.toward == 1, c
assert str(c) == ("beacon within reach after 2.02 s, path 5.21 m; "
                  "closest rim: human 0.500 m, solid 1.500 m; 1 ticks toward a human inside human_stop"), str(c)

# Without a release the closest approaches run to the recorder's end, and a body that never comes
# within reach drove the whole recorder.
never = course([], RECORDER[:3])
assert never.beacon_s is None and math.isclose(never.path_m, math.hypot(3, 2) + 1.4), never
assert never.human_m is not None and math.isclose(never.human_m, 0.5), never
assert course([], RECORDER).human_m is not None and math.isclose(course([], RECORDER).human_m or 0, 0.05)
assert course([], []) == Course()

# Under SENSING=range a line's scene is what the stack sensed, here without h1 behind o1, and course
# measures on its truth instead.
SENSED = [{**x, "scene": [e for e in x["scene"] if e["kind"] != "human"], "truth": x["scene"]} for x in RECORDER]
assert truth(SENSED[0]) == RECORDER[0]["scene"] and truth(RECORDER[0]) == RECORDER[0]["scene"]
assert course(RELEASED, SENSED) == c, course(RELEASED, SENSED)
assert course(RELEASED, [{**x, "truth": x["scene"]} for x in SENSED]).human_m is None
assert courses([never, c]) == (
    "beacon 1 within reach after a median 2.02 s, 2.02 to 2.02, path a median 5.21 m, 5.21 to 5.21; "
    "closest rim: human 0.500 m, solid 1.500 m; 1 ticks toward a human inside human_stop"), courses([never, c])
assert courses([Course()]) == ("beacon none within reach; closest rim: human none, solid none; "
                               "0 ticks toward a human inside human_stop"), courses([Course()])

print("trials: ok")
