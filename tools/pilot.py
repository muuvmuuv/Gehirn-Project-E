#!/usr/bin/env python3
"""Scripted pilot for gehirn's entry plug.

Steers toward the beacon at a fixed heading offset for a while, then leaves the seat, which
gehirn notices 500 ms after the last datagram. With --eject it pulls the eject handle
instead of just leaving. The pose comes from gehirn's flight recorder, so run it from the
directory gehirn writes to or pass --recorder. Every datagram is signed with PILOT_KEY, which
gehirn needs too; tools/withenv.py passes it from .env:

    python3 tools/withenv.py .env python3 tools/pilot.py --offset 120 --seconds 20
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
# plug/pilot.v seal, which makes the same bytes for gehirn-gamepad; pose() reads plug.v's Record
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


# ponytail: the recorder flushes about once a second, so this pose lags the body by up to a
# second; read a live pose stream instead once Phase 1 publishes one.
def pose(recorder: str, start: tuple[float, float] = START) -> tuple[float, float]:
    """Return the pose in the recorder's last complete line, or start."""
    try:
        with open(recorder, "rb") as f:
            f.seek(max(0, os.fstat(f.fileno()).st_size - TAIL))
            lines = f.read().split(b"\n")[:-1]
    except FileNotFoundError:
        return start
    for line in reversed(lines):
        try:
            x, y = json.loads(line)["pose"]
            return float(x), float(y)
        except (ValueError, KeyError, TypeError):
            continue
    return start


def steer(at: tuple[float, float], beacon: tuple[float, float], offset_deg: float,
          speed: float) -> list[float]:
    """Return the velocity toward the beacon turned by offset_deg, zero once arrived."""
    dx, dy = beacon[0] - at[0], beacon[1] - at[1]
    if math.hypot(dx, dy) < ARRIVE:
        return [0.0, 0.0]
    a = math.atan2(dy, dx) + math.radians(offset_deg)
    return [speed * math.cos(a), speed * math.sin(a)]


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


def main() -> None:
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
    args = ap.parse_args()

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

    for _ in ticks(args.seconds, args.rate):
        send(steer(pose(recorder, start), args.beacon, args.offset, args.speed), False)
    if args.eject:
        for _ in ticks(0.5, args.rate):
            send([0.0, 0.0], True)
        print("pilot: eject", flush=True)
    else:
        print("pilot: left the seat", flush=True)


if __name__ == "__main__":
    main()
