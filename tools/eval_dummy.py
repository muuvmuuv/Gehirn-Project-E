#!/usr/bin/env python3
"""Phase 4 evaluation: fly the dummy plug from given starts and count how it does.

Every run starts gehirn at one of --starts in a fresh directory, with tools/pilot.py in the
seat for --pilot-seconds, flying with --pilot-args, after which the dummy plug flies alone.
The run's recorder begins as a copy of --recorders, so the nearest neighbor dummy plug knows
the ticks the network in --weights was trained on; those recorders are only read. A run ends
one second after the first release or at the time limit. Each run counts who held the seat
when the body first came within 0.6 m of the goal, where a release lands on target, whether
the dummy plug was benched, and how far it steered off what the pilot would have steered on
the same tick. A DAgger round, whose --pilot-args hold --dagger, also counts the ticks the
pilot corrected the dummy plug. Each dummy plug of --dummies flies every start: knn, the
nearest neighbor one, and policy, the network. With both, the script exits 0 when the
network arrives in more runs and gets benched in fewer, the done criterion of PLAN Phase 4.
GEHIRN_URL and the rest come from the environment, as for tools/trials.py.

    python3 tools/eval_dummy.py --recorders train/*/plug.jsonl --weights dummy.shinji.json \\
        --starts '1,-4.5;-1.5,4;4.5,-1' --runs 2
    python3 tools/eval_dummy.py --dummies policy --weights dummy.shinji.json --starts=-3.5,-2.5 \\
        --pilot-seconds 60 --pilot-args '--avoid 1.2 --offset 20 --dagger 30'   # a DAgger round
"""

import argparse
import json
import math
import os
import queue
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from pilot import ARRIVE, command, off, parser
from trials import read_journal, release

REACH = 0.6  # lcl.beacon_reach plus the 0.1 m within which main.v counts a release on target
BENCHED = "plug: dummy plug out of sync"  # main.v main()'s line when the dummy plug is benched
LINGER = 1.0  # seconds a run goes on after the first release
GRACE = 3.0  # seconds between terminate and kill
POLL = 0.2
ASTRAY = 30.0  # degrees off the pilot's own command that README's DAgger loop corrects

print_lock = threading.Lock()


def outcome(recorder: str, since_ms: int, log: str, style: argparse.Namespace) -> dict:
    """Return how a run went since since_ms: who first reached the goal and how soon after it was
    set, how often the dummy plug was benched, the ticks it flew, the sum of its angles off what
    the pilot flying with style would have steered there and the ticks off by more than ASTRAY,
    and the ticks the pilot corrected it."""
    arrived_by, arrive_s, first_ms, dummy_ticks, corrections = None, None, None, 0, 0
    off_sum, astray = 0.0, 0
    try:
        with open(recorder, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    r = json.loads(line)
                    t, pose, target, seat = r["t_ms"], r["pose"], r["target"], r["seat"]
                except (ValueError, KeyError, TypeError):
                    continue
                if t < since_ms or len(target) != 2 or len(pose) != 2:
                    continue
                first_ms = t if first_ms is None else first_ms
                corrections += r.get("correction") is True
                if seat == "dummy" and math.dist(pose, target) >= ARRIVE:
                    angle = off(r.get("u_seat") or [], command(tuple(pose), r.get("scene") or [], style))
                    dummy_ticks += 1
                    off_sum += angle
                    astray += angle > ASTRAY
                if arrived_by is None and math.dist(pose, target) < REACH:
                    arrived_by, arrive_s = seat, (t - first_ms) / 1000
    except FileNotFoundError:
        pass
    try:
        with open(log, encoding="utf-8", errors="replace") as f:
            benched = sum(line.startswith(BENCHED) for line in f)
    except FileNotFoundError:
        benched = 0
    return {"arrived_by": arrived_by, "arrive_s": arrive_s, "benched": benched, "dummy_ticks": dummy_ticks,
            "off_sum": off_sum, "astray": astray, "corrections": corrections}


def fly(n: int, dummy: str, start: str, args: argparse.Namespace, slots: "queue.Queue[int]") -> dict:
    """Fly run n from start with one dummy plug and return what came of it."""
    slot = slots.get()
    try:
        d = os.path.join(args.out, f"run-{n:02d}-{dummy}")
        os.makedirs(d)
        recorder, journal, log = (os.path.join(d, f) for f in ("plug.jsonl", "core.jsonl", "gehirn.log"))
        with open(recorder, "wb") as w:
            for path in args.recorders:
                with open(path, "rb") as f:
                    shutil.copyfileobj(f, w)
        addr = f"127.0.0.1:{args.plug_base + slot}"
        env = {
            **os.environ,
            "START": start,
            "CORE_JOURNAL": journal,
            "PLUG_RECORDER": recorder,
            "PLUG_LISTEN": addr,
            "PILOT_KEY": args.key,
            "DUMMY_WEIGHTS": args.weights if dummy == "policy" else os.path.join(d, "no-weights.json"),
        }
        since_ms, t0 = int(time.time() * 1000), time.monotonic()
        with open(log, "wb") as out, open(os.path.join(d, "pilot.log"), "wb") as pout:
            g = subprocess.Popen([args.binary], cwd=d, env=env, stdout=out, stderr=subprocess.STDOUT)
            p = subprocess.Popen([sys.executable, args.pilot, "--addr", addr, "--recorder", recorder,
                                  "--seconds", str(args.pilot_seconds), *shlex.split(args.pilot_args)],
                                 cwd=d, env=env, stdout=pout, stderr=subprocess.STDOUT)
            deadline, seen = t0 + args.limit, False
            while g.poll() is None and time.monotonic() < deadline:
                if not seen and release(read_journal(journal)):
                    seen, deadline = True, min(deadline, time.monotonic() + LINGER)
                time.sleep(POLL)
            for proc in (p, g):
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(GRACE)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait()
    finally:
        slots.put(slot)
    r = {"run": n, "dummy": dummy, "start": start, "release": release(read_journal(journal)),
         **outcome(recorder, since_ms, log, args.style)}
    arrived = f"{r['arrived_by']} arrived after {r['arrive_s']:.1f} s" if r["arrived_by"] else "nobody arrived"
    corrected = f", {r['corrections']} ticks corrected" if args.style.dagger is not None else ""
    with print_lock:
        print(f"run {n:02d} {dummy} from {start}: {arrived}, benched {r['benched']} times{corrected}, "
              f"released {r['release'] or 'nothing'}", flush=True)
    return r


def summary(runs: list[dict]) -> dict:
    """Return how often one dummy plug arrived, got benched and saw the payload delivered, how far
    off the pilot's own command it steered on average and how often by more than ASTRAY, and the
    ticks the pilot corrected it."""
    ticks = sum(r["dummy_ticks"] for r in runs)
    return {
        "runs": len(runs),
        "arrived": sum(r["arrived_by"] == "dummy" for r in runs),
        "benched": sum(r["benched"] > 0 for r in runs),
        "on_target": sum(r["release"] == "on target" for r in runs),
        "off_deg": sum(r["off_sum"] for r in runs) / ticks if ticks else 0.0,
        "astray_pct": 100.0 * sum(r["astray"] for r in runs) / ticks if ticks else 0.0,
        "corrections": sum(r["corrections"] for r in runs),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])  # None under -OO
    ap.add_argument("--starts", required=True, help="START values separated by semicolons, x,y;x,y")
    ap.add_argument("--runs", type=int, default=1, help="runs per start and dummy plug")
    ap.add_argument("--dummies", default="knn,policy", help="knn, policy or both, comma separated")
    ap.add_argument("--recorders", nargs="*", default=[], help="recorders every run's recorder starts with")
    ap.add_argument("--weights", help="the policy's weights, gehirn's DUMMY_WEIGHTS")
    ap.add_argument("--pilot-seconds", type=float, default=3.0, help="how long the pilot flies before leaving")
    ap.add_argument("--pilot-args", default="--avoid 1.2 --offset 20", help="more arguments for tools/pilot.py")
    ap.add_argument("--jobs", type=int, default=3, help="runs flown at the same time")
    ap.add_argument("--limit", type=float, default=90.0, help="seconds before a run is cut off")
    ap.add_argument("--binary", default="./gehirn", help="gehirn executable")
    ap.add_argument("--plug-base", type=int, default=7800, help="PLUG_LISTEN port of job slot 0")
    ap.add_argument("--out", help="empty or new directory for the runs, default a fresh temp dir")
    args = ap.parse_args()

    dummies = args.dummies.split(",")
    if not set(dummies) <= {"knn", "policy"}:
        sys.exit(f"eval_dummy: --dummies is {args.dummies}; accepted knn, policy or knn,policy")
    if "policy" in dummies and not (args.weights and os.path.isfile(args.weights)):
        sys.exit("eval_dummy: the policy needs --weights, a file tools/train_dummy.py wrote")
    args.weights = os.path.abspath(args.weights) if args.weights else ""
    args.recorders = [os.path.abspath(p) for p in args.recorders]
    args.binary = os.path.abspath(args.binary)
    if not (os.path.isfile(args.binary) and os.access(args.binary, os.X_OK)):
        sys.exit(f"eval_dummy: cannot run {args.binary}")
    args.pilot = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pilot.py")
    args.style = parser().parse_args(shlex.split(args.pilot_args))
    args.key = secrets.token_hex(32)
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        if os.listdir(args.out):
            sys.exit(f"eval_dummy: {args.out} is not empty, and every run needs a fresh recorder")
    else:
        args.out = tempfile.mkdtemp(prefix="gehirn-eval-")
    args.out = os.path.abspath(args.out)
    plan = [(dummy, start) for start in args.starts.split(";") for _ in range(args.runs) for dummy in dummies]
    print(f"eval_dummy: {len(plan)} runs of {args.binary}, {args.jobs} at a time, in {args.out}", flush=True)

    slots: queue.Queue[int] = queue.Queue()
    for s in range(args.jobs):
        slots.put(s)
    with ThreadPoolExecutor(args.jobs) as pool:
        runs = list(pool.map(lambda i: fly(i + 1, *plan[i], args, slots), range(len(plan))))
    with open(os.path.join(args.out, "runs.json"), "w", encoding="utf-8") as f:
        json.dump(runs, f, indent=1)

    totals = {dummy: summary([r for r in runs if r["dummy"] == dummy]) for dummy in dummies}
    for dummy, t in totals.items():
        corrected = f"; {t['corrections']} ticks corrected" if args.style.dagger is not None else ""
        print(f"{dummy}: arrived in {t['arrived']} of {t['runs']} runs, benched in {t['benched']}, "
              f"{t['on_target']} delivered on target; off the pilot by {t['off_deg']:.1f} degrees on "
              f"average and by more than {ASTRAY:g} in {t['astray_pct']:.1f}% of its ticks{corrected}")
    if len(totals) < 2:
        return
    knn, policy = totals["knn"], totals["policy"]
    done = policy["arrived"] > knn["arrived"] and policy["benched"] < knn["benched"]
    print(f"phase 4: {'done' if done else 'not done'} (the policy must arrive more often and get benched less)")
    sys.exit(0 if done else 1)


if __name__ == "__main__":
    main()
