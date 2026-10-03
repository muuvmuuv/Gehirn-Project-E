#!/usr/bin/env python3
"""Export flight recorders into the dummy plug's training set.

Every tick in which the pilot held the seat toward a goal becomes one JSON line: x, what
the dummy plug's policy sees in that tick's percept; y, the pilot's command in the goal's frame
as speed along the way to the goal and across it to the left; and correction, whether the
pilot had taken the seat from the dummy plug. Ticks without a goal, inside the arrival radius
or recorded without a scene, and lines that are no recorder tick, such as a cut last line, are
skipped. Recorders are only read (CONTRIBUTING.md, Logging 3), so exporting the aggregate
again after more flights is how DAgger retrains; tools/train_dummy.py takes the set.

    python3 tools/export_dummy.py plug.shinji.jsonl > dummy.shinji.set
    python3 tools/export_dummy.py --out dummy.shinji.set runs/*/plug.jsonl
"""

import argparse
import json
import math
import sys
from collections.abc import Iterable, Iterator

ARRIVE = 0.35  # lcl.arrive: plug/dummy.v act lets go inside it, so the policy never acts there
SIGHT = 3.0  # meters past an entity's rim the policy still sees it


def is_point(v: object) -> bool:
    """Report whether v is a list of two finite numbers."""
    return (isinstance(v, list) and len(v) == 2
            and all(isinstance(c, (int, float)) and not isinstance(c, bool) and math.isfinite(c)
                    for c in v))


def is_entity(e: object) -> bool:
    """Report whether e is a scene entity as lcl.Entity encodes it."""
    return (isinstance(e, dict) and isinstance(e.get("kind"), str) and is_point(e.get("pos"))
            and isinstance(e.get("r"), (int, float)) and math.isfinite(e["r"]))


def features(pose: list[float], target: list[float], scene: list[dict]) -> list[float] | None:
    """Return what the dummy plug's policy sees, or None without a goal frame.

    In the goal's frame: the distance to the goal up to SIGHT, then for the nearest solid
    entity and the nearest human the direction to it, along and across, scaled by how close
    its rim is, and that closeness, 1 at the rim and 0 at SIGHT or beyond.
    """
    dx, dy = target[0] - pose[0], target[1] - pose[1]
    d = math.hypot(dx, dy)
    if d < 1e-6:
        return None
    gx, gy = dx / d, dy / d
    f = [min(d, SIGHT)]
    for human in (False, True):
        near = [0.0, 0.0, 0.0]
        for e in scene:
            if e["kind"] == "beacon" or (e["kind"] == "human") != human:
                continue
            rx, ry = e["pos"][0] - pose[0], e["pos"][1] - pose[1]
            n = math.hypot(rx, ry)
            w = min(1.0, 1.0 - (n - e["r"]) / SIGHT)
            if w > near[2] and n > 1e-6:
                near = [w * (rx * gx + ry * gy) / n, w * (ry * gx - rx * gy) / n, w]
        f += near
    return f


# sample() reads the lines of plug/plug.v Record.
def sample(line: str) -> dict | None:
    """Return one recorder line's training sample, or None when it holds none."""
    try:
        r = json.loads(line)
    except ValueError:
        return None
    if not isinstance(r, dict) or r.get("seat") != "pilot":
        return None
    pose, target, u, scene = r.get("pose"), r.get("target"), r.get("u_seat"), r.get("scene")
    if not (is_point(pose) and is_point(target) and is_point(u) and isinstance(scene, list)
            and scene and all(is_entity(e) for e in scene)):
        return None
    d = math.dist(pose, target)
    if d < ARRIVE:
        return None
    gx, gy = (target[0] - pose[0]) / d, (target[1] - pose[1]) / d
    return {"x": features(pose, target, scene), "y": [u[0] * gx + u[1] * gy, u[1] * gx - u[0] * gy],
            "correction": r.get("correction") is True}


def export(lines: Iterable[str]) -> Iterator[dict]:
    """Yield the training sample of every recorder line that holds one."""
    for line in lines:
        s = sample(line)
        if s is not None:
            yield s


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])  # None under -OO
    ap.add_argument("recorders", nargs="+", help="PLUG_RECORDER files to read")
    ap.add_argument("--out", help="file to write the set to, default stdout")
    args = ap.parse_args()

    out = open(args.out, "w", encoding="utf-8") if args.out else sys.stdout
    n = corrections = 0
    try:
        for path in args.recorders:
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    for s in export(f):
                        out.write(json.dumps(s, separators=(",", ":")) + "\n")
                        n += 1
                        corrections += s["correction"]
            except OSError as e:
                sys.exit(f"export_dummy: cannot read {path}: {e.strerror}")
    finally:
        if out is not sys.stdout:
            out.close()
    print(f"export_dummy: {n} pilot ticks, {corrections} of them corrections, from "
          f"{len(args.recorders)} recorders", file=sys.stderr)


if __name__ == "__main__":
    main()
