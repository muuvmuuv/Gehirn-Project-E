#!/usr/bin/env python3
"""Phase 0 trials: run gehirn missions from the default start and count how they end.

Each run gets its own directory with a fresh journal, recorder and log, and its own plug
port; everything else, GEHIRN_URL and the models included, comes from the environment,
falling back to the KEY=VALUE lines of --env-file for variables the environment lacks.
A run ends one second after the journal records the first release, or at the time limit.
Startup warnings in a run's log, such as a Jev unit without a key, are echoed once.
Each run's line and the total's are followed by a course line, which course measures from
the recorder: when the body came within reach of the mission's beacon and how far it drove
there, how close it came to a human and to a solid, and how often it stepped toward a human
inside the armor's human_stop.
Exits 0 when at least 80% of runs delivered on target and no ballot was lost to a parse
error, the parts of the Phase 0 done criterion in PLAN.md that a journal shows.

    python3 tools/trials.py --jobs 2
    python3 tools/trials.py --env-file .env    # .env: GEHIRN_KEY=${OPENROUTER_API_KEY} and TYPESAFE_API_KEY
"""

import argparse
import json
import math
import os
import queue
import re
import subprocess
import statistics
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

from withenv import load_env

# The journal's text lines come from core/core.v Memory, its ballot lines from
# main.v BallotEntry and its core fault lines from main.v FaultEntry. An armor refusal is the
# outcome main.v refused words as "armor refused <goal>: <reason>" and hq journals as an
# outcome line.
# The log is gehirn's stdout, which shows model text too, so it is read only for WARNINGS.
RELEASE_VOTE = re.compile(r"^proposed release\b.*, (approved|rejected) \d+/\d+$", re.S)
# Fault texts of a ballot the unit's reply could not be read for: oai/oai.v ask (unreadable
# completion) and extract_json (no JSON object), magi/magi.v read_reply (unreadable ballot) and
# jev/jev.v read_reply (unreadable reply). core/llm.v read_proposal's unreadable proposal is a
# core fault and never reaches a ballot.
PARSE_ERRORS = ("unreadable", "no JSON object")
# Startup lines of main.v main(), key_warning and ca_warning, which explain faults a tally
# only counts, and the lines refusing a configuration load_config rejects or a core new_backend
# cannot start, which explain a run that exits at once.
WARNINGS = ("magi: ", "gehirn: ")
# lcl/lcl.v beacon_reach: how close to a beacon's center, in meters, the body counts as at it.
BEACON_REACH = 0.5
# armor/armor.v Limits human_stop: inside it, in meters from the body's center to a human's rim,
# the armor moves the body toward no human.
HUMAN_STOP = 0.7
TOWARD = 1e-9  # m, the least step toward a human that counts, as Known issue 33 counted
LINGER = 1.0  # seconds a run goes on after the first release
GRACE = 3.0  # seconds between terminate and kill
POLL = 0.2

print_lock = threading.Lock()
warned: set[str] = set()
STOP = threading.Event()  # set by a caller that ends every running mission at once, as tools/worldgen.py does on a signal


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
    exits: int = 0  # gehirn exited on its own before the run's end; fly sets it, tally cannot

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
    """Return every readable line of a journal or a recorder, oldest first, a cut one left out."""
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


def tally(journal: str) -> Tally:
    """Count one run from its journal."""
    t = Tally()
    entries = read_journal(journal)
    where = release(entries)
    t.on_target, t.off_target = int(where == "on target"), int(where == "off target")
    t.no_release = int(where is None)
    for e in entries:
        if e.get("kind") == "core fault":
            t.core_faults += 1
        elif e.get("kind") == "ballot":
            t.ballots += 1
            if e.get("vote") == "fault":
                why = str(e.get("why") or "")
                if any(p in why for p in PARSE_ERRORS):
                    t.parse_faults += 1
                else:
                    t.other_faults += 1
        elif e.get("text", "").startswith("outcome: armor refused "):
            t.refusals += 1
        elif m := RELEASE_VOTE.match(e.get("text", "")):
            t.approved += m[1] == "approved"
            t.rejected += m[1] == "rejected"
    return t


@dataclass
class Course:
    """How the body moved in one run, as course measures it from the recorder and the journal.

    beacon_s is None when the body never came within BEACON_REACH of the mission's beacon, and
    path_m then runs over the whole recorder; human_m and solid_m are None without a human or a
    solid in the scene.
    """

    beacon_s: float | None = None
    path_m: float = 0.0
    human_m: float | None = None
    solid_m: float | None = None
    toward: int = 0

    def __str__(self) -> str:
        at = "never within reach" if self.beacon_s is None else f"within reach after {self.beacon_s:.2f} s"
        return f"beacon {at}, path {self.path_m:.2f} m; " + closest(self.human_m, self.solid_m, self.toward)


def closest(human_m: float | None, solid_m: float | None, toward: int) -> str:
    """Render the closest approaches and the steps toward a human, for each course line."""
    rims = ", ".join(f"{what} {'none' if m is None else f'{m:.3f} m'}"
                     for what, m in (("human", human_m), ("solid", solid_m)))
    return f"closest rim: {rims}; {toward} ticks toward a human inside human_stop"


def release_tick(journal: list[dict], recorder: list[dict]) -> int:
    """Return the index of the recorder line where the run's first release happened, else the last.

    That line is the first at or after the approving verdict of the release that came out first
    in the journal: the last approved release verdict before the journal's first release outcome.
    """
    texts = [(e.get("t_ms", 0), e.get("text", "")) for e in journal]
    done = next((t for t, text in texts if text.startswith("outcome: released ")), None)
    if done is None or not recorder:
        return len(recorder) - 1
    approved = [t for t, text in texts if t <= done and (m := RELEASE_VOTE.match(text)) and m[1] == "approved"]
    at = max(approved, default=done)
    return next((i for i, line in enumerate(recorder) if line["t_ms"] >= at), len(recorder) - 1)


def course(journal: list[dict], recorder: list[dict]) -> Course:
    """Measure how the body moved in one run, from its journal and recorder as read_journal reads them.

    Each measure is the one PLAN's State of 2026-10-06 used for the MuJoCo base and the stopping
    distance, so numbers stay comparable:
    - beacon_s: seconds from the recorder's first line to the first whose pose lies less than
      BEACON_REACH from the mission's beacon, the first beacon of the first line's scene, which
      gehirn's default MISSION names;
    - path_m: the distance between consecutive poses summed up to that line, or over the whole
      recorder when there is none;
    - human_m and solid_m: the least distance from the body's center to a human's rim and to the
      rim of anything solid, neither beacon nor human, over the lines up to the first release
      (release_tick), where that State took the whole recorder;
    - toward, the count of Known issue 33: the pairs of consecutive lines over the whole recorder
      in which the body's step, projected on the direction from the first line's pose to a human
      whose rim lay inside HUMAN_STOP of it there, exceeds TOWARD.
    """
    lines = [line for line in recorder if len(line.get("pose") or []) == 2 and "t_ms" in line]
    if not lines:
        return Course()
    c = Course()
    beacon = next((e for e in lines[0].get("scene", []) if e.get("kind") == "beacon"), None)
    for i, line in enumerate(lines):
        if i > 0:
            c.path_m += math.dist(lines[i - 1]["pose"], line["pose"])
        if beacon and math.dist(line["pose"], beacon["pos"]) < BEACON_REACH:
            c.beacon_s = (line["t_ms"] - lines[0]["t_ms"]) / 1000
            break
    for line in lines[: release_tick(journal, lines) + 1]:
        for e in line.get("scene", []):
            if e.get("kind") == "beacon" or len(e.get("pos") or []) != 2:
                continue
            rim = math.dist(line["pose"], e["pos"]) - e.get("r", 0.0)
            if e.get("kind") == "human":
                c.human_m = rim if c.human_m is None else min(c.human_m, rim)
            else:
                c.solid_m = rim if c.solid_m is None else min(c.solid_m, rim)
    for a, b in zip(lines, lines[1:]):
        step = (b["pose"][0] - a["pose"][0], b["pose"][1] - a["pose"][1])
        for e in a.get("scene", []):
            if e.get("kind") != "human" or len(e.get("pos") or []) != 2:
                continue
            gap = math.dist(a["pose"], e["pos"])
            ahead = step[0] * (e["pos"][0] - a["pose"][0]) + step[1] * (e["pos"][1] - a["pose"][1])
            if gap - e.get("r", 0.0) < HUMAN_STOP and gap > 0 and ahead / gap > TOWARD:
                c.toward += 1
                break
    return c


def courses(runs: list[Course]) -> str:
    """Render the courses of several runs as the total's course line: the median and range of the
    beacon times and paths of the runs that came within reach, the closest approaches and the
    steps toward a human summed."""
    reached = [r for r in runs if r.beacon_s is not None]
    if reached:
        times = [r.beacon_s for r in reached if r.beacon_s is not None]
        paths = [r.path_m for r in reached]
        at = (f"{len(reached)} within reach after a median {statistics.median(times):.2f} s, "
              f"{min(times):.2f} to {max(times):.2f}, path a median {statistics.median(paths):.2f} m, "
              f"{min(paths):.2f} to {max(paths):.2f}")
    else:
        at = "none within reach"
    humans = [r.human_m for r in runs if r.human_m is not None]
    solids = [r.solid_m for r in runs if r.solid_m is not None]
    toward = sum(r.toward for r in runs)
    return f"beacon {at}; " + closest(min(humans, default=None), min(solids, default=None), toward)


def warnings(log: str) -> list[str]:
    """Return the startup warnings in a run's log."""
    try:
        with open(log, encoding="utf-8", errors="replace") as f:
            return [line.rstrip("\n") for line in f if line.startswith(WARNINGS)]
    except FileNotFoundError:
        return []


def fly(n: int, args: argparse.Namespace, slots: "queue.Queue[int]") -> tuple[Tally, Course]:
    """Run mission n in its own directory on a free plug port, until it ends, reaches the limit or
    STOP is set, tally it and measure its course."""
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
            while proc.poll() is None and time.monotonic() < deadline and not STOP.is_set():
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
    t = tally(journal)
    t.exits = int(code is not None)
    c = course(read_journal(journal), read_journal(os.path.join(d, "plug.jsonl")))
    crash = "" if code is None else f"; gehirn exited {code} on its own"
    with print_lock:
        print(f"run {n:02d} after {elapsed:.0f} s: {t}{crash}", flush=True)
        print(f"run {n:02d} course: {c}", flush=True)
        for w in warnings(log):
            if w not in warned:
                warned.add(w)
                print(w, flush=True)
    return t, c


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])  # None under -OO
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
    runs = []
    with ThreadPoolExecutor(args.jobs) as pool:
        for t, c in pool.map(lambda n: fly(n, args, slots), range(1, args.runs + 1)):
            total.add(t)
            runs.append(c)

    print(f"total of {args.runs}: {total}")
    print(f"course of {args.runs}: {courses(runs)}")
    # ponytail: the criterion's other clause, no release with a human inside 2 m, is not
    # checked here; journal the human distance with each release vote to add it.
    done = total.on_target * 10 >= args.runs * 8 and total.parse_faults == 0
    print(f"phase 0: {'done' if done else 'not done'} (needs 80% on target and no parse faults)")
    sys.exit(0 if done else 1)


if __name__ == "__main__":
    main()
