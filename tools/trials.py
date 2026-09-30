#!/usr/bin/env python3
"""Phase 0 trials: run gehirn missions from the default start and count how they end.

Each run gets its own directory with a fresh journal, recorder and log, and its own plug
port; everything else, GEHIRN_URL and the models included, comes from the environment,
falling back to the KEY=VALUE lines of --env-file for variables the environment lacks.
A run ends one second after the journal records the first release, or at the time limit.
Exits 0 when at least 80% of runs delivered on target and no ballot was lost to a parse
error, the parts of the Phase 0 done criterion in PLAN.md that a journal shows.

    GEHIRN_URL=http://127.0.0.1:11434/v1/chat/completions python3 tools/trials.py --jobs 2
    python3 tools/trials.py --env-file .env    # .env: GEHIRN_KEY=${OPENROUTER_API_KEY}
"""

import argparse
import json
import os
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

from withenv import load_env

# The journal's text lines come from core/core.v Memory, its ballot lines from
# main.v BallotEntry; the log is gehirn's stdout as listed in contract C4.
RELEASE_VOTE = re.compile(r"^proposed release\b.*, (approved|rejected) \d+/\d+$", re.S)
PARSE_ERRORS = ("unreadable", "no JSON object")
LINGER = 1.0  # seconds a run goes on after the first release
GRACE = 3.0  # seconds between terminate and kill
POLL = 0.2

print_lock = threading.Lock()


@dataclass
class Tally:
    """What one run, or all of them, came to."""

    on_target: int = 0
    off_target: int = 0
    no_release: int = 0
    approved: int = 0
    rejected: int = 0
    refusals: int = 0
    ballots: int = 0
    parse_faults: int = 0
    other_faults: int = 0
    core_faults: int = 0

    def add(self, other: "Tally") -> None:
        """Fold another tally into this one."""
        for k, v in vars(other).items():
            setattr(self, k, getattr(self, k) + v)

    def __str__(self) -> str:
        return (
            f"{self.on_target} on target, {self.off_target} off target, {self.no_release} no release; "
            f"release votes {self.approved} approved {self.rejected} rejected; "
            f"armor refusals {self.refusals}; ballots {self.ballots}, "
            f"faults {self.parse_faults} parse {self.other_faults} other; core faults {self.core_faults}"
        )


def read_journal(path: str) -> list[dict]:
    """Return every readable entry of a journal, oldest first."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
    except FileNotFoundError:
        return []
    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return entries


def release(entries: list[dict]) -> str | None:
    """Return 'on target' or 'off target' for the first release in a journal, else None."""
    for e in entries:
        text = e.get("text", "")
        if text.startswith("outcome: released "):
            return text.removeprefix("outcome: released ")
    return None


def tally(journal: str, log: str) -> Tally:
    """Count one run from its journal and its log."""
    t = Tally()
    entries = read_journal(journal)
    where = release(entries)
    t.on_target, t.off_target = int(where == "on target"), int(where == "off target")
    t.no_release = int(where is None)
    for e in entries:
        if e.get("kind") == "ballot":
            t.ballots += 1
            if e.get("vote") == "fault":
                why = str(e.get("why") or "")
                if any(p in why for p in PARSE_ERRORS):
                    t.parse_faults += 1
                else:
                    t.other_faults += 1
        elif m := RELEASE_VOTE.match(e.get("text", "")):
            t.approved += m[1] == "approved"
            t.rejected += m[1] == "rejected"
    try:
        with open(log, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.rstrip("\n")
                t.refusals += line.startswith("armor: ") and line.endswith(" refused")
                t.core_faults += line.startswith("hq: core fault: ")
    except FileNotFoundError:
        pass
    return t


def fly(n: int, args: argparse.Namespace, slots: "queue.Queue[int]") -> Tally:
    """Run mission n in its own directory on a free plug port and tally it."""
    slot = slots.get()
    try:
        d = os.path.join(args.out, f"run-{n:02d}")
        os.makedirs(d)
        journal, log = os.path.join(d, "core.jsonl"), os.path.join(d, "gehirn.log")
        env = {
            **args.env,
            **os.environ,
            "CORE_JOURNAL": journal,
            "PLUG_RECORDER": os.path.join(d, "plug.jsonl"),
            "PLUG_LISTEN": f"127.0.0.1:{args.plug_base + slot}",
        }
        start = time.monotonic()
        with open(log, "wb") as out:
            proc = subprocess.Popen([args.binary], cwd=d, env=env, stdout=out, stderr=subprocess.STDOUT)
            deadline, seen = start + args.limit, False
            while proc.poll() is None and time.monotonic() < deadline:
                if not seen and release(read_journal(journal)):
                    seen, deadline = True, min(deadline, time.monotonic() + LINGER)
                time.sleep(POLL)
            code = proc.poll()
            if code is None:
                proc.terminate()
                try:
                    proc.wait(GRACE)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        elapsed = time.monotonic() - start
    finally:
        slots.put(slot)
    t = tally(journal, log)
    crash = "" if code is None else f"; gehirn exited {code} on its own"
    with print_lock:
        print(f"run {n:02d} after {elapsed:.0f} s: {t}{crash}", flush=True)
    return t


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--runs", type=int, default=10, help="missions to fly")
    ap.add_argument("--jobs", type=int, default=1, help="missions flown at the same time")
    ap.add_argument("--limit", type=float, default=180.0, help="seconds before a run is cut off")
    ap.add_argument("--binary", default="./gehirn", help="gehirn executable")
    ap.add_argument("--plug-base", type=int, default=7800, help="PLUG_LISTEN port of job slot 0")
    ap.add_argument("--out", help="empty or new directory for the runs, default a fresh temp dir")
    ap.add_argument("--env-file", help="dotenv file for variables the environment does not set")
    args = ap.parse_args()

    try:
        args.env = load_env(args.env_file) if args.env_file else {}
    except OSError as e:
        sys.exit(f"trials: cannot read {args.env_file}: {e.strerror}")

    args.binary = os.path.abspath(args.binary)
    if not (os.path.isfile(args.binary) and os.access(args.binary, os.X_OK)):
        sys.exit(f"trials: cannot run {args.binary}")
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        if os.listdir(args.out):
            sys.exit(f"trials: {args.out} is not empty, and every run needs a fresh journal")
    else:
        args.out = tempfile.mkdtemp(prefix="gehirn-trials-")
    args.out = os.path.abspath(args.out)
    print(f"trials: {args.runs} runs of {args.binary}, {args.jobs} at a time, in {args.out}", flush=True)

    slots: queue.Queue[int] = queue.Queue()
    for s in range(args.jobs):
        slots.put(s)
    total = Tally()
    with ThreadPoolExecutor(args.jobs) as pool:
        for t in pool.map(lambda n: fly(n, args, slots), range(1, args.runs + 1)):
            total.add(t)

    print(f"total of {args.runs}: {total}")
    # ponytail: the criterion's other clause, no release with a human inside 2 m, is not
    # checked here; journal the human distance with each release vote to add it.
    done = total.on_target * 10 >= args.runs * 8 and total.parse_faults == 0
    print(f"phase 0: {'done' if done else 'not done'} (needs 80% on target and no parse faults)")
    sys.exit(0 if done else 1)


if __name__ == "__main__":
    main()
