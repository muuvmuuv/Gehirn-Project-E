#!/usr/bin/env python3
"""Staging panel: keys that switch the mock's forced votes, proposals and gotos while the demo or a
scene flies on lineup mock, through the POST /stage that tools/mock_endpoint.py --stage serves to
loopback. It reaches the mock on 127.0.0.1 alone, never HQ, the field unit or the bridge, and a
mock that scripts/stage.sh starts for any other lineup refuses it (docs/scenes.md, Staging live).

    python3 tools/staging.py 8081        # just stage 8081, beside just demo 8081

m and c cycle MELCHIOR-1's and CASPER-3's ballot through forced approve, forced reject and the
script; g makes the core propose a goto outside the fence, which MELCHIOR-1 and BALTHASAR-2
refuse, and p self_destruct, which needs all three, each until pressed again; x returns all to
the script, and q quits and leaves the stage as it is. Each holds from the role's next request.
"""

import argparse
import http.client
import json
import sys
import termios
import tty

from mock_endpoint import FENCE

# ponytail: no key for BALTHASAR-2, since on Jev, the default, the mock forces nothing and Jev's
# reasons could not say they were forced; a b key for BALTHASAR_BACKEND=llm when a show needs it.
UNITS = {"m": "melchior", "c": "casper"}
NEXT = {None: "approve", "approve": "reject", "reject": "off"}

# Past the fence the mock's units hold, so MELCHIOR-1 and BALTHASAR-2 refuse it on any world.
OUTSIDE = f"{FENCE + 1:g},0"


def press(key: str, now: dict) -> dict | None:
    """Return the POST /stage body for key, given what the mock last said it stages, or None for a
    key that stages nothing."""
    if key in UNITS:
        unit = UNITS[key]
        return {"vote": f"{unit}={NEXT[now['vote'][unit]]}"}
    if key == "g":
        return {"goto": "off" if now["goto"] else OUTSIDE}
    if key == "p":
        return {"propose": "off" if now["propose"] else "self_destruct"}
    if key == "x":
        return {"clear": True}
    return None


def post(port: int, body: dict) -> dict:
    """POST body to /stage on 127.0.0.1:port and return what the mock stages now, or exit with why
    it refused."""
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        conn.request("POST", "/stage", json.dumps(body), {"Content-Type": "application/json"})
        res = conn.getresponse()
        reply = json.loads(res.read())
    except (OSError, http.client.HTTPException, ValueError) as e:
        sys.exit(f"staging: no mock answers on 127.0.0.1:{port}: {e}")
    finally:
        conn.close()
    if res.status != 200:
        why = reply.get("error", {}).get("message") if isinstance(reply, dict) else None
        sys.exit(f"staging: 127.0.0.1:{port} refuses with HTTP {res.status}: {why or 'no mock with --stage'}")
    return reply


def show(now: dict) -> str:
    """Describe what the mock stages in one line."""
    votes = ", ".join(f"{unit} {vote or 'script'}" for unit, vote in now["vote"].items())
    core = (f"goto({now['goto'][0]:.2f}, {now['goto'][1]:.2f})" if now["goto"] else "script")
    return f"staging: {votes}; core {now['propose'] or core}"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])  # None under -OO
    ap.add_argument("port", nargs="?", type=int, default=8081, help="the mock's port, just demo's first")
    port = ap.parse_args().port
    now = post(port, {})
    print("staging: m MELCHIOR-1, c CASPER-3: approve, reject, script; g goto outside the fence; "
          "p self_destruct; x all to script; q quit")
    print(show(now), flush=True)
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd) if sys.stdin.isatty() else None
    try:
        if saved:
            tty.setcbreak(fd)
        while (key := sys.stdin.read(1)) not in ("", "q"):
            body = press(key, now)
            if body is not None:
                now = post(port, body)
                print(show(now), flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        if saved:
            termios.tcsetattr(fd, termios.TCSADRAIN, saved)


if __name__ == "__main__":
    main()
