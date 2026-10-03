#!/usr/bin/env python3
"""Self check for pilot.datagram: python3 tools/test_pilot.py"""

import math

from pilot import avoid, datagram, off

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

print("pilot: ok")
