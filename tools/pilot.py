#!/usr/bin/env python3
"""Scripted pilot for gehirn's entry plug.

Steers toward the beacon at a fixed heading offset for a while, then leaves the seat, which
gehirn notices 500 ms after the last datagram. With --eject it pulls the eject handle
instead of just leaving. With --avoid it also steers around anything solid and every human
within that many meters of their rim, sliding to the side nearer the beacon, so the dummy
plug has a style around obstacles to learn. With --dagger it flies only to correct the dummy
plug, as DAgger's expert: it takes the seat for --hold seconds whenever the dummy plug steers
more than that many degrees off its own command, or nobody steers toward a goal. The pose,
scene and seat come from gehirn's flight recorder, so run it from the directory gehirn writes
to or pass --recorder. Every datagram is signed with PILOT_KEY, which gehirn needs too;
tools/withenv.py passes it from .env:

    python3 tools/withenv.py .env python3 tools/pilot.py --offset 120 --seconds 20
    python3 tools/withenv.py .env python3 tools/pilot.py --offset 20 --avoid 1.2 --dagger 30 --seconds 60
"""

import argparse
import hashlib
import hmac
import json
import math
import os
import socket
import sys
import time
from collections.abc import Iterator

START = (-3.5, -2.5)  # main.v start_pose's default; the pose until the recorder exists, unless START is set
ARRIVE = 0.35  # lcl.arrive: close enough to the beacon to stop steering
TAIL = 4096  # bytes read from the end of the recorder, several lines' worth


# The counterparts of datagram() are plug/plug.v read_datagram, which checks it, and
# plug/pilot.v seal, which makes the same bytes for gehirn-gamepad; last() reads plug.v's Record
# lines. tools/test_pilot.py and plug/plug_test.v test_read_datagram and test_seal share one
# datagram.
def datagram(pilot: str, u: list[float], eject: bool, seq: int, key: bytes) -> bytes:
    """Encode one pilot command as a JSON line, a newline and its HMAC SHA256 under key in hex.

    seq is the pilot's wall clock in microseconds, strictly increasing across datagrams.
    """
    line = json.dumps({"v": 1, "seq": seq, "pilot": pilot, "u": u, "eject": eject},
                      separators=(",", ":")).encode()
    return line + b"\n" + hmac.new(key, line, hashlib.sha256).hexdigest().encode()


def pilot_key() -> bytes:
    """Return PILOT_KEY from the environment as 32 bytes, or exit with a line that says why."""
    try:
        key = bytes.fromhex(os.environ.get("PILOT_KEY", ""))
    except ValueError:
        key = b""
    if len(key) != 32:
        sys.exit("pilot: PILOT_KEY is unset or not 64 hex digits; gehirn's must match")
    return key


# ponytail: the recorder flushes at least once a second, so this tick lags the body by up to a
# second; read a live stream instead once the plug publishes one.
def last(recorder: str) -> dict:
    """Return the recorder's last complete tick with a pose, or an empty dict before there is one."""
    try:
        with open(recorder, "rb") as f:
            f.seek(max(0, os.fstat(f.fileno()).st_size - TAIL))
            lines = f.read().split(b"\n")[:-1]
    except FileNotFoundError:
        return {}
    for line in reversed(lines):
        try:
            r = json.loads(line)
            x, y = r["pose"]
            r["pose"] = (float(x), float(y))
            return r
        except (ValueError, KeyError, TypeError):
            continue
    return {}


def steer(at: tuple[float, float], beacon: tuple[float, float], offset_deg: float,
          speed: float) -> list[float]:
    """Return the velocity toward the beacon turned by offset_deg, zero once arrived."""
    dx, dy = beacon[0] - at[0], beacon[1] - at[1]
    if math.hypot(dx, dy) < ARRIVE:
        return [0.0, 0.0]
    a = math.atan2(dy, dx) + math.radians(offset_deg)
    return [speed * math.cos(a), speed * math.sin(a)]


def avoid(at: tuple[float, float], beacon: tuple[float, float], scene: list[dict], u: list[float],
          reach: float) -> list[float]:
    """Return u bent around every entity but a beacon whose rim lies within reach of at.

    Each one pushes away and to the side of it nearer the beacon, the harder the closer, and
    the result keeps u's speed.
    """
    speed = math.hypot(*u)
    if speed == 0.0 or reach <= 0.0:
        return u
    ux, uy = u
    bx, by = beacon[0] - at[0], beacon[1] - at[1]
    for e in scene:
        try:
            if e["kind"] == "beacon":
                continue
            rx, ry = at[0] - float(e["pos"][0]), at[1] - float(e["pos"][1])
            gap = math.hypot(rx, ry) - float(e["r"])
        except (KeyError, IndexError, TypeError, ValueError):
            continue
        n = math.hypot(rx, ry)
        if gap >= reach or n < 1e-6:
            continue
        push = speed * (reach - gap) / reach
        ax, ay = rx / n, ry / n
        sx, sy = (-ay, ax) if bx * -ay + by * ax >= 0.0 else (ay, -ax)
        ux += push * (ax + sx)
        uy += push * (ay + sy)
    n = math.hypot(ux, uy)
    return [ux * speed / n, uy * speed / n] if n > 1e-9 else [0.0, 0.0]


def off(u: list[float], v: list[float]) -> float:
    """Return the angle between u and v in degrees, 180 when only one of them moves."""
    nu, nv = math.hypot(*u), math.hypot(*v)
    if nu < 0.05 or nv < 0.05:
        return 0.0 if (nu < 0.05) == (nv < 0.05) else 180.0
    return math.degrees(math.acos(max(-1.0, min(1.0, (u[0] * v[0] + u[1] * v[1]) / (nu * nv)))))


def ticks(seconds: float, rate: float) -> Iterator[None]:
    """Yield rate times per second for seconds, on absolute deadlines so the rate holds."""
    start = time.monotonic()
    for i in range(round(seconds * rate)):
        yield
        time.sleep(max(0.0, start + (i + 1) / rate - time.monotonic()))


def point(value: str) -> tuple[float, float]:
    """Parse X,Y."""
    x, y = value.split(",")
    return float(x), float(y)


def command(at: tuple[float, float], scene: list[dict], args: argparse.Namespace) -> list[float]:
    """Return what this pilot, flying with args from parser(), steers at at with scene around it."""
    return avoid(at, args.beacon, scene, steer(at, args.beacon, args.offset, args.speed), args.avoid)


def parser() -> argparse.ArgumentParser:
    """Return the pilot's argument parser, which tools/eval_dummy.py also reads --pilot-args with."""
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])  # None under -OO
    ap.add_argument("--addr", default="127.0.0.1:7777", help="gehirn's PLUG_LISTEN")
    ap.add_argument("--pilot", default="shinji", help="gehirn's PILOT_ID")
    ap.add_argument("--offset", type=float, default=0.0,
                    help="heading offset in degrees, positive is counterclockwise")
    ap.add_argument("--seconds", type=float, default=15.0, help="how long to steer")
    ap.add_argument("--speed", type=float, default=0.6, help="commanded speed in m/s")
    ap.add_argument("--rate", type=float, default=50.0, help="datagrams per second")
    ap.add_argument("--recorder", help="gehirn's PLUG_RECORDER, default plug.<pilot>.jsonl")
    ap.add_argument("--beacon", type=point, default=(3.0, 2.0), metavar="X,Y", help="where to steer")
    ap.add_argument("--eject", action="store_true", help="pull the eject handle for 0.5 s at the end")
    ap.add_argument("--avoid", type=float, default=0.0, metavar="M",
                    help="steer around solid things and humans within M meters of their rim")
    ap.add_argument("--dagger", type=float, metavar="DEG",
                    help="only take the seat while the dummy plug steers more than DEG off, or nobody does")
    ap.add_argument("--hold", type=float, default=2.0, help="seconds each --dagger correction lasts")
    return ap


def main() -> None:
    args = parser().parse_args()

    key = pilot_key()
    start = point(os.environ["START"]) if os.environ.get("START") else START
    recorder = args.recorder or f"plug.{args.pilot}.jsonl"
    host, _, port = args.addr.rpartition(":")
    dest = (host, int(port))
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(f"pilot: {args.pilot} to {args.addr}, offset {args.offset:g} deg for {args.seconds:g} s",
          flush=True)
    seq = 0

    def send(u: list[float], eject: bool) -> None:
        nonlocal seq
        seq = max(time.time_ns() // 1000, seq + 1)
        sock.sendto(datagram(args.pilot, u, eject, seq, key), dest)

    until, corrections = 0.0, 0
    for _ in ticks(args.seconds, args.rate):
        r = last(recorder)
        at = r.get("pose", start)
        u = command(at, r.get("scene") or [], args)
        if args.dagger is not None and time.monotonic() >= until:
            astray = r.get("seat") == "dummy" and off(r.get("u_seat") or [], u) > args.dagger
            if len(r.get("target") or []) != 2 or not (astray or r.get("seat") == "empty"):
                continue
            until = time.monotonic() + args.hold
            corrections += 1
        send(u, False)
    if args.eject:
        for _ in ticks(0.5, args.rate):
            send([0.0, 0.0], True)
        print("pilot: eject", flush=True)
    elif args.dagger is not None:
        print(f"pilot: corrected the dummy plug {corrections} times, then left the seat", flush=True)
    else:
        print("pilot: left the seat", flush=True)


if __name__ == "__main__":
    main()
