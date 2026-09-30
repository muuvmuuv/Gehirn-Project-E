#!/usr/bin/env python3
"""Self check for withenv.load_env: python3 tools/test_withenv.py"""

import os
import tempfile

from withenv import load_env

FIXTURE = """# comment

export A_KEY="sk-or-v1-abc"
GEHIRN_KEY=${A_KEY}
Q='single quoted'
HOME_COPY=$HOME/x
UNKNOWN=${NOPE}
noequals
"""

with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False) as f:
    f.write(FIXTURE)
try:
    e = load_env(f.name)
finally:
    os.unlink(f.name)

assert e["A_KEY"] == "sk-or-v1-abc", e
assert e["GEHIRN_KEY"] == "sk-or-v1-abc", e
assert e["Q"] == "single quoted", e
assert e["HOME_COPY"] == os.environ["HOME"] + "/x", e
assert e["UNKNOWN"] == "${NOPE}", e
assert len(e) == 5, e
print("withenv: ok")
