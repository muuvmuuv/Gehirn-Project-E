#!/usr/bin/env python3
"""Self check for pilot.datagram: python3 tools/test_pilot.py"""

from pilot import datagram

# plug/plug_test.v test_read_datagram opens this same datagram and test_seal makes it, so the
# sides cannot drift.
KEY = bytes(range(32))
SHARED = (b'{"v":1,"seq":1790000000000000,"pilot":"shinji","u":[0.4,0.1],"eject":false}\n'
          b"fa38345f9bbb948b76b3bf0dd41a3c4e237e7a623a545f68d9a767d164f59133")

got = datagram("shinji", [0.4, 0.1], False, 1790000000000000, KEY)
assert got == SHARED, got
assert datagram("shinji", [0.4, 0.1], False, 1790000000000000, bytes(32)) != SHARED

print("pilot: ok")
