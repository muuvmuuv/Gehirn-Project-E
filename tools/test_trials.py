#!/usr/bin/env python3
"""Self check for trials.tally and trials.fly: python3 tools/test_trials.py"""

import argparse
import contextlib
import io
import json
import os
import queue
import tempfile
import time

from trials import GRACE, STOP, fly, tally

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
    assert fly(1, run, slots).exits == 1
    STOP.set()
    start = time.monotonic()
    assert fly(1, argparse.Namespace(**{**vars(run), "out": os.path.join(d, "b"), "binary": os.path.join(d, "runs")}),
               slots).exits == 0
    assert time.monotonic() - start < GRACE, time.monotonic() - start
    STOP.clear()

print("trials: ok")
