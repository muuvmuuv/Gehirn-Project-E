#!/usr/bin/env python3
"""Self check for pilot.datagram, avoid, off, world and home: python3 tools/test_pilot.py"""

import math
import os
from pathlib import Path

from pilot import BEACON, START, avoid, datagram, home, off, world

# plug/plug_test.v test_read_datagram opens this same datagram and test_seal makes it, so the
# sides cannot drift.
KEY = bytes(range(32))
SHARED = (b'{"v":1,"seq":1790000000000000,"pilot":"shinji","u":[0.4,0.1],"eject":false}\n'
          b"fa38345f9bbb948b76b3bf0dd41a3c4e237e7a623a545f68d9a767d164f59133")

got = datagram("shinji", [0.4, 0.1], False, 1790000000000000, KEY)
assert got == SHARED, got
assert datagram("shinji", [0.4, 0.1], False, 1790000000000000, bytes(32)) != SHARED

# Nothing within reach leaves the command alone; a pillar ahead bends it to the side nearer the
# beacon, whatever side the command leans to, at the same speed and harder the closer it is.
PILLAR = [{"kind": "obstacle", "pos": [0.0, 0.0], "r": 0.8}, {"kind": "beacon", "pos": [3.0, -0.5], "r": 0.3}]
B = (3.0, -0.5)
assert avoid((-3.0, 0.0), B, PILLAR, [0.6, 0.05], 1.2) == [0.6, 0.05]
near, nearer = avoid((-1.5, 0.0), B, PILLAR, [0.6, 0.05], 1.2), avoid((-1.0, 0.0), B, PILLAR, [0.6, 0.05], 1.2)
assert math.isclose(math.hypot(*near), math.hypot(0.6, 0.05)) and near[1] < 0.0, near
assert near[0] > nearer[0] and nearer[1] < near[1], (near, nearer)
assert avoid((-1.0, 0.0), B, PILLAR, [0.6, 0.0], 0.0) == [0.6, 0.0]

assert math.isclose(off([1.0, 0.0], [0.0, 2.0]), 90.0)
assert off([0.0, 0.0], [0.6, 0.0]) == 180.0 and off([0.0, 0.0], [0.0, 0.0]) == 0.0

# START and BEACON match worlds/default.json, which body/world_test.v pins to body/world.v
# default_world. A world file WORLD names moves both, and START moves the start of any world.
WORLDS = Path(__file__).resolve().parent.parent / "worlds"
EXAMPLE = ((-4.0, -3.0), (3.5, 2.5))
assert world(str(WORLDS / "default.json")) == (START, BEACON)
assert world(str(WORLDS / "example.json")) == EXAMPLE
saved = {k: os.environ.pop(k, None) for k in ("WORLD", "START")}
try:
    assert home() == (START, BEACON)
    os.environ["START"] = "1,-2"
    assert home() == ((1.0, -2.0), BEACON)
    os.environ["WORLD"] = str(WORLDS / "example.json")
    assert home() == ((1.0, -2.0), EXAMPLE[1])
    del os.environ["START"]
    assert home() == EXAMPLE
    os.environ["WORLD"] = str(WORLDS / "no-such-world.json")
    try:
        home()
        raise AssertionError("home read a world file that is not there")
    except SystemExit as e:
        assert str(e).startswith("pilot: WORLD is "), e
finally:
    for k, v in saved.items():
        os.environ.pop(k, None)
        if v is not None:
            os.environ[k] = v

print("pilot: ok")
