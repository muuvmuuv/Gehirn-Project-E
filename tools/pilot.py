#!/usr/bin/env python3
"""Scripted pilot for gehirn's entry plug.

Steers toward the beacon at a fixed heading offset for a while, then leaves the seat, which
gehirn notices 500 ms after the last datagram. With --eject it pulls the eject handle
instead of just leaving. The pose comes from gehirn's flight recorder, so run it from the
directory gehirn writes to or pass --recorder.

    python3 tools/pilot.py --offset 120 --seconds 20
"""

import argparse
import json
import math
import os
import socket
import time
from collections.abc import Iterator

START = (-3.5, -2.5)  # body/body.v Sim's start pose, used until the recorder exists
ARRIVE = 0.35  # lcl.arrive: close enough to the beacon to stop steering
TAIL = 4096  # bytes read from the end of the recorder, several lines' worth


# The counterpart of datagram() is plug/plug.v Wire; pose() reads its Record lines.
def datagram(pilot: str, u: list[float], eject: bool) -> bytes:
    """Encode one pilot command."""
    return json.dumps({"pilot": pilot, "u": u, "eject": eject}).encode()


# ponytail: the recorder flushes about once a second, so this pose lags the body by up to a
# second; read a live pose stream instead once Phase 1 publishes one.
def pose(recorder: str) -> tuple[float, float]:
    """Return the pose in the recorder's last complete line, or the start pose."""
    try:
        with open(recorder, "rb") as f:
            f.seek(max(0, os.fstat(f.fileno()).st_size - TAIL))
            lines = f.read().split(b"\n")[:-1]
    except FileNotFoundError:
        return START
    for line in reversed(lines):
        try:
            x, y = json.loads(line)["pose"]
            return float(x), float(y)
        except (ValueError, KeyError, TypeError):
            continue
    return START


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
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
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

    recorder = args.recorder or f"plug.{args.pilot}.jsonl"
    host, _, port = args.addr.rpartition(":")
    dest = (host, int(port))
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(f"pilot: {args.pilot} to {args.addr}, offset {args.offset:g} deg for {args.seconds:g} s",
          flush=True)
    for _ in ticks(args.seconds, args.rate):
        u = steer(pose(recorder), args.beacon, args.offset, args.speed)
        sock.sendto(datagram(args.pilot, u, False), dest)
    if args.eject:
        for _ in ticks(0.5, args.rate):
            sock.sendto(datagram(args.pilot, [0.0, 0.0], True), dest)
        print("pilot: eject", flush=True)
    else:
        print("pilot: left the seat", flush=True)


if __name__ == "__main__":
    main()
