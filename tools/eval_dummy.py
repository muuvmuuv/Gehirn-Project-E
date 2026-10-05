#!/usr/bin/env python3
"""Phase 4 evaluation: fly the dummy plug from given starts and count how it does.

Every run starts gehirn at one of --starts in a fresh directory, with tools/pilot.py in the
seat for --pilot-seconds, flying with --pilot-args, after which the dummy plug flies alone.
The run's recorder begins as a copy of --recorders, so the nearest neighbor dummy plug knows
the ticks the network in --weights was trained on, up to the newest KNN_LIMIT a pilot flew, and
the script warns when they hold more; those recorders are only read. A run ends
one second after the first release or at the time limit. Each run counts who held the seat
when the body first came within 0.6 m of the goal, where a release lands on target, whether
the dummy plug was benched, how far it steered off what the pilot would have steered on the
same tick, its lowest sync, its ticks close to the pillar's rim and how close it came to the
human. A DAgger round, whose --pilot-args hold --dagger, also counts the ticks the pilot
corrected the dummy plug. Each dummy plug of --dummies flies every start: knn, the nearest
neighbor one, and policy, the network. With both, the script counts the starts only one of
them arrived from or was benched on, and exits 0 when the done criterion of PLAN Phase 4
holds: the network steers closer to the pilot's own command than the nearest neighbor dummy
plug, by its mean angle off it and by its share of ticks more than ASTRAY degrees off, each
compared to the tenth it prints, so a tie is not met, while it arrives in as many runs and
gets benched in no more. GEHIRN_URL and the rest come from the environment, as for
tools/trials.py.

The defaults and the sets train, validation and test of STARTS are the protocol of PLAN
Phase 4, set on 2026-10-04 before any test run. The pilot flies --avoid 1.2 --offset 20 and
leaves after a second, so the dummy plug flies all but the first 1.5 s. Those sets hold
0.5 m grid points at least 2.5 m from the beacon, 1.1 m from the pillar's rim and 1.6 m from
the center of the human's loop, in sectors by their bearing from the beacon,
counterclockwise from east. test and
validation are the ones in the pillar's shadow, from which the straight line to the beacon
would touch the pillar (about 201 to 234 degrees), and in the northwest whose line crosses
the loop (155 to 178), within 4 m of the pillar's rim, split like a checkerboard: test where
2x + 2y is even. train is every one west of the shadow (184 to 200 degrees), south of it
(236 to 256) and north (100 to 150), which pass the pillar with it on either side and cross
the loop, and two in the open east. The pilot flies the training flights to the end, DAgger
rounds start from train, the network is chosen on validation alone, and test is flown once,
one run per start and dummy plug, with the recorders the network was trained on:

    python3 tools/eval_dummy.py --starts train --dummies knn --pilot-seconds 60 --out train
    python3 tools/export_dummy.py --out dummy.shinji.set train/*/plug.jsonl
    python3 tools/train_dummy.py dummy.shinji.set
    python3 tools/eval_dummy.py --starts test --recorders train/*/plug.jsonl --weights dummy.shinji.json
    python3 tools/eval_dummy.py --dummies policy --weights dummy.shinji.json --starts train \\
        --pilot-seconds 60 --pilot-args '--avoid 1.2 --offset 20 --dagger 30'   # a DAgger round

The fresh test, set on 2026-10-05 before any of its runs, judges the criterion as worded that
day, after test had been seen, with the same pilot, defaults and run. Its 61 starts, fresh,
follow the rule of test and validation on the grid offset by 0.25 m in x and y, so no earlier
run started from any of them: 48 in the shadow and 13 in the northwest, all flown as test.
Its recorders are the training flights from fresh-train, the 35 train starts where 2x + 2y is
even: the flights of 2026-10-04 from those starts, copied out of train/ as they are, not
flown again. They hold 19874 pilot ticks, so the nearest neighbor dummy plug keeps every one
of them and the up to 75 it learns from the pilot in a run's first 1.5 s, which the network
does not. Flights flown again hold other ticks, and it keeps all of them only while they
number KNN_LIMIT - 75 or fewer. The network is trained on their export with
tools/train_dummy.py's defaults, which give the very weights that flew test when trained on
all 71 train flights, and without a DAgger round, since the one from the train starts drew no
correction. With those copies in fresh-train/<start>/plug.jsonl, fresh is flown once, one run
per start and dummy plug:

    python3 tools/export_dummy.py --out dummy.fresh.set fresh-train/*/plug.jsonl
    python3 tools/train_dummy.py dummy.fresh.set --out dummy.fresh.json
    python3 tools/eval_dummy.py --starts fresh --recorders fresh-train/*/plug.jsonl --weights dummy.fresh.json
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
PLUG_UP = "field: plug for "  # main.v main()'s line once the plug listens and the field loop starts
LINGER = 1.0  # seconds a run goes on after the first release
GRACE = 3.0  # seconds between terminate and kill
POLL = 0.2
ASTRAY = 30.0  # degrees off the pilot's own command that README's DAgger loop corrects
NEAR_SOLID = 0.4  # m from a solid's rim, a little past where armor.Limits solid_keep slides a command along it
KNN_LIMIT = 20000  # plug/dummy.v Dummy.limit, the most pilot ticks the nearest neighbor dummy plug keeps

# The protocol's start sets, as the docstring derives them from body/body.v Sim.scene.
STARTS = {
    "train": "-4.5,-0.5;-4.5,0;-4.5,0.5;-4.5,1;-4,-0.5;-4,0;-4,0.5;-4,1;-4,1.5;-3.5,0;-3.5,0.5;-3.5,1;"
             "-3.5,1.5;-3,0;-3,0.5;-3,1;-3,1.5;-2.5,0.5;-2.5,1;-2.5,1.5;-2,0.5;-2,1;-2,1.5;-1.5,1;-1.5,1.5;"
             "-1,1.5;-1,-4.5;-1,-4;-0.5,-4.5;-0.5,-4;-0.5,-3.5;0,-4.5;0,-4;0,-3.5;0,-3;0,-2.5;0.5,-4.5;"
             "0.5,-4;0.5,-3.5;0.5,-3;0.5,-2.5;1,-4.5;1,-4;1,-3.5;1,-3;1,-2.5;1,-2;1.5,-3.5;1.5,-3;1.5,-2.5;"
             "1.5,-2;1.5,-1.5;2,-1.5;2,-1;2,-0.5;-1,4.5;-0.5,4.5;0,4;0,4.5;0.5,3.5;0.5,4;0.5,4.5;1,3.5;1,4;"
             "1,4.5;1.5,4;1.5,4.5;2,4.5;2.5,4.5;4.5,-2;4.5,4.5",
    "validation": "-4.5,-1;-4,-2.5;-4,-1.5;-3.5,-3;-3.5,-2;-3.5,-1;-3,-3.5;-3,-2.5;-3,-1.5;-3,-0.5;"
                  "-2.5,-4;-2.5,-3;-2.5,-2;-2.5,-1;-2,-4.5;-2,-3.5;-2,-2.5;-2,-1.5;-2,-0.5;-1.5,-4;-1.5,-3;"
                  "-1.5,-2;-1,-2.5;-3,2.5;-2.5,3;-2,2.5;-1,2.5",
    "test": "-4.5,-1.5;-4,-2;-4,-1;-3.5,-3.5;-3.5,-2.5;-3.5,-1.5;-3,-4;-3,-3;-3,-2;-3,-1;-2.5,-3.5;"
            "-2.5,-2.5;-2.5,-1.5;-2.5,-0.5;-2,-4;-2,-3;-2,-2;-2,-1;-2,0;-1.5,-3.5;-1.5,-2.5;-1.5,-1.5;"
            "-1,-3;-1,-2;-0.5,-2.5;-3.5,2.5;-3,3;-2.5,2.5;-2,3;-1.5,2.5;-0.5,2.5",
    "fresh": "-4.25,-2.25;-4.25,-1.75;-4.25,-1.25;-3.75,-3.25;-3.75,-2.75;-3.75,-2.25;-3.75,-1.75;-3.75,-1.25;"
             "-3.75,-0.75;-3.25,-3.75;-3.25,-3.25;-3.25,-2.75;-3.25,-2.25;-3.25,-1.75;-3.25,-1.25;-3.25,-0.75;"
             "-2.75,-3.75;-2.75,-3.25;-2.75,-2.75;-2.75,-2.25;-2.75,-1.75;-2.75,-1.25;-2.75,-0.75;-2.75,-0.25;"
             "-2.25,-4.25;-2.25,-3.75;-2.25,-3.25;-2.25,-2.75;-2.25,-2.25;-2.25,-1.75;-2.25,-1.25;-2.25,-0.75;"
             "-2.25,-0.25;-1.75,-4.25;-1.75,-3.75;-1.75,-3.25;-1.75,-2.75;-1.75,-2.25;-1.75,-1.75;-1.75,-1.25;"
             "-1.25,-3.75;-1.25,-3.25;-1.25,-2.75;-1.25,-2.25;-1.25,-1.75;-0.75,-2.75;-0.75,-2.25;-0.25,-2.25;"
             "-3.75,2.25;-3.25,2.25;-3.25,2.75;-2.75,2.25;-2.75,2.75;-2.25,2.25;-2.25,2.75;-1.75,2.25;-1.75,2.75;"
             "-1.25,2.25;-1.25,2.75;-0.75,2.25;-0.75,2.75",
}
STARTS["fresh-train"] = ";".join(s for s in STARTS["train"].split(";") if sum(map(float, s.split(","))) % 1 == 0)

print_lock = threading.Lock()


def outcome(recorder: str, since_ms: int, log: str, style: argparse.Namespace) -> dict:
    """Return how a run went since since_ms: who first reached the goal and how soon after it was
    set, how often the dummy plug was benched, the ticks it flew, the sum of its angles off what
    the pilot flying with style would have steered there and the ticks off by more than ASTRAY,
    the ticks the pilot corrected it, and while it flew its lowest sync, the ticks within
    NEAR_SOLID of a solid's rim and how close the body came to a human's rim."""
    arrived_by, arrive_s, first_ms, dummy_ticks, corrections = None, None, None, 0, 0
    off_sum, astray, low_sync, near_solid, human_gap = 0.0, 0, 1.0, 0, math.inf
    try:
        with open(recorder, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    r = json.loads(line)
                    t, pose, target, seat = r["t_ms"], r["pose"], r["target"], r["seat"]
                    gaps = [(e["kind"], math.dist(pose, e["pos"]) - e["r"]) for e in r.get("scene") or []]
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
                    low_sync = min(low_sync, r.get("sync", 1.0))
                    near_solid += any(k not in ("beacon", "human") and g < NEAR_SOLID for k, g in gaps)
                    human_gap = min([human_gap] + [g for k, g in gaps if k == "human"])
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
            "off_sum": off_sum, "astray": astray, "corrections": corrections, "low_sync": low_sync,
            "near_solid": near_solid, "human_gap": None if human_gap == math.inf else human_gap}


def plug_up(log: str) -> bool:
    """Report whether gehirn's log says its plug listens."""
    try:
        with open(log, encoding="utf-8", errors="replace") as f:
            return PLUG_UP in f.read()
    except FileNotFoundError:
        return False


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
            deadline, seen = t0 + args.limit, False

            # The nearest neighbor dummy plug replays every recorder before the plug listens, which
            # takes seconds, so the pilot's seconds start once the plug is up.
            while g.poll() is None and time.monotonic() < deadline and not plug_up(log):
                time.sleep(POLL / 10)
            p = subprocess.Popen([sys.executable, args.pilot, "--addr", addr, "--recorder", recorder,
                                  "--seconds", str(args.pilot_seconds), *shlex.split(args.pilot_args)],
                                 cwd=d, env=env, stdout=pout, stderr=subprocess.STDOUT)
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
    off the pilot's own command it steered on average and how often by more than ASTRAY, the
    ticks the pilot corrected it, how soon it arrived on average, its lowest sync, its ticks
    within NEAR_SOLID of a solid's rim, and the closest it brought the body to a human's rim."""
    ticks = sum(r["dummy_ticks"] for r in runs)
    arrivals = [r["arrive_s"] for r in runs if r["arrived_by"] == "dummy"]
    return {
        "runs": len(runs),
        "arrived": len(arrivals),
        "benched": sum(r["benched"] > 0 for r in runs),
        "on_target": sum(r["release"] == "on target" for r in runs),
        "off_deg": sum(r["off_sum"] for r in runs) / ticks if ticks else 0.0,
        "astray_pct": 100.0 * sum(r["astray"] for r in runs) / ticks if ticks else 0.0,
        "corrections": sum(r["corrections"] for r in runs),
        "arrive_s": sum(arrivals) / len(arrivals) if arrivals else None,
        "low_sync": min((r["low_sync"] for r in runs), default=1.0),
        "near_solid": sum(r["near_solid"] for r in runs),
        "human_gap": min((r["human_gap"] for r in runs if r["human_gap"] is not None), default=None),
    }


def met(knn: dict, policy: dict) -> bool:
    """Report whether PLAN Phase 4's done criterion holds for two summaries: the policy is off
    the pilot by fewer degrees on average and astray in a smaller share of its ticks, each to
    the tenth main prints, and arrives in as many runs and gets benched in no more."""
    return (round(policy["off_deg"], 1) < round(knn["off_deg"], 1)
            and round(policy["astray_pct"], 1) < round(knn["astray_pct"], 1)
            and policy["arrived"] >= knn["arrived"] and policy["benched"] <= knn["benched"])


def pilot_ticks(recorders: list[str]) -> int:
    """Return how many ticks of recorders plug/dummy.v load_dummy learns from: the pilot's,
    toward a goal, the ticks inside the arrival radius that tools/export_dummy.py skips included."""
    n = 0
    for path in recorders:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    r = json.loads(line)
                    pose, target, u = r["pose"], r["target"], r.get("u_seat") or []
                    n += (r["seat"] == "pilot" and len(pose) == len(target) == len(u) == 2
                          and math.dist(pose, target) >= 1e-6)
                except (ValueError, KeyError, TypeError):
                    continue
    return n


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])  # None under -OO
    ap.add_argument("--starts", required=True,
                    help="START values separated by semicolons, x,y;x,y, or a set of STARTS: train, "
                         "validation, test, fresh-train or fresh")
    ap.add_argument("--runs", type=int, default=1, help="runs per start and dummy plug")
    ap.add_argument("--dummies", default="knn,policy", help="knn, policy or both, comma separated")
    ap.add_argument("--recorders", nargs="*", default=[], help="recorders every run's recorder starts with")
    ap.add_argument("--weights", help="the policy's weights, gehirn's DUMMY_WEIGHTS")
    ap.add_argument("--pilot-seconds", type=float, default=1.0, help="how long the pilot flies before leaving")
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
    if "knn" in dummies and (held := pilot_ticks(args.recorders)) > KNN_LIMIT:
        print(f"eval_dummy: --recorders hold {held} pilot ticks and the nearest neighbor dummy plug keeps the "
              f"newest {KNN_LIMIT}, fewer than a network trained on them saw", file=sys.stderr, flush=True)
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
    starts = STARTS.get(args.starts, args.starts).split(";")
    plan = [(dummy, start) for start in starts for _ in range(args.runs) for dummy in dummies]
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
        soon = f"after {t['arrive_s']:.1f} s on average" if t["arrive_s"] is not None else "never"
        human = f"{t['human_gap']:.2f} m" if t["human_gap"] is not None else "never seen"
        print(f"{dummy}: arrived in {t['arrived']} of {t['runs']} runs, benched in {t['benched']}, "
              f"{t['on_target']} delivered on target; off the pilot by {t['off_deg']:.1f} degrees on "
              f"average and by more than {ASTRAY:g} in {t['astray_pct']:.1f}% of its ticks{corrected}; "
              f"arrived {soon}, lowest sync {100 * t['low_sync']:.0f}%, {t['near_solid']} ticks within "
              f"{NEAR_SOLID:g} m of a solid's rim, closest to a human's rim {human}")
    if len(totals) < 2:
        return

    # plan flies both dummy plugs of one start and repeat back to back, so their runs pair up.
    pairs = list(zip(runs[dummies.index("knn")::2], runs[dummies.index("policy")::2]))
    arrived = [sum(a["arrived_by"] == "dummy" and b["arrived_by"] != "dummy" for a, b in pairs),
               sum(b["arrived_by"] == "dummy" and a["arrived_by"] != "dummy" for a, b in pairs)]
    benched = [sum(a["benched"] > 0 and b["benched"] == 0 for a, b in pairs),
               sum(b["benched"] > 0 and a["benched"] == 0 for a, b in pairs)]
    print(f"paired: only knn arrived from {arrived[0]} starts and only the policy from {arrived[1]}; "
          f"only knn was benched from {benched[0]} and only the policy from {benched[1]}")
    done = met(totals["knn"], totals["policy"])
    print(f"phase 4: {'done' if done else 'not done'} (the policy must steer closer to the pilot by both "
          f"measures, arrive as often and get benched no more)")
    sys.exit(0 if done else 1)


if __name__ == "__main__":
    main()
