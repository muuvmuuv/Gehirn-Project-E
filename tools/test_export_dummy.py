#!/usr/bin/env python3
"""Self check for export_dummy: python3 tools/test_export_dummy.py"""

import json
import math

from export_dummy import export, features

# The scene of body/world.v default_world with the human held still.
SCENE = [
    {"id": "b1", "kind": "beacon", "pos": [3.0, 2.0], "r": 0.3},
    {"id": "o1", "kind": "obstacle", "pos": [0.0, -0.3], "r": 0.8},
    {"id": "h1", "kind": "human", "pos": [1.5, 0.0], "r": 0.3},
]

# plug/dummy_test.v test_observe expects the same numbers from plug/dummy.v observe.
SHARED = [2.3323807579381204, -0.7383642874308872, -0.22239888175629136, 0.7711310417560499,
          -0.7711310417560499, 0.014280075529516156, -0.7854041541233885, 0.7855339622647798,
          -0.7855339622647798]


def close(a: list[float], b: list[float]) -> bool:
    return len(a) == len(b) and all(math.isclose(x, y, abs_tol=1e-12) for x, y in zip(a, b))


assert close(features([1.0, 0.8], [3.0, 2.0], SCENE), SHARED), features([1.0, 0.8], [3.0, 2.0], SCENE)

# Inside a rim the closeness stops at 1, past SIGHT the distance stops at 3, out of sight is zero.
# The pillar lies left of the way there and the human right, which the fourth number of each says.
f = features([0.5, -0.9], [3.0, 2.0], SCENE)
assert f is not None and f[0] == 3.0 and f[3] == f[4] == 1.0 and f[8] == -f[7] < 0.0, f
assert features([-4.0, -4.0], [3.0, 2.0], SCENE)[5:] == [0.0, 0.0, 0.0, 0.0]
assert features([3.0, 2.0], [3.0, 2.0], SCENE) is None


def line(**fields: object) -> str:
    r = {"t_ms": 1, "seat": "pilot", "pose": [1.0, 0.8], "target": [3.0, 2.0], "u_seat": [0.6, 0.0],
         "u_core": [1.0, 0.0], "u_out": [0.6, 0.0], "sync": 0.5, "scene": SCENE, "correction": False}
    r.update(fields)
    return json.dumps(r)


RECORDER = [
    line(),
    line(correction=True, u_seat=[0.0, 0.5]),
    line(seat="dummy"),  # only the pilot teaches
    line(seat="empty"),
    line(target=[]),  # no goal
    line(pose=[2.9, 1.9]),  # inside the arrival radius
    line(scene=[]),  # recorded before the scene was
    line(pose=[1.0]),
    line(u_seat=[0.6, "0"]),
    line(scene=[{"kind": "human", "pos": [1.0, None], "r": 0.3}]),
    "[1, 2]",
    '{"t_ms": 1, "seat": "pilot", "pose": [1.0, 0.8',  # a cut last line
]
got = list(export(RECORDER))
assert len(got) == 2, got
assert close(got[0]["x"], SHARED) and got[0]["correction"] is False, got[0]

# The command in the goal's frame: (2, 1.2) is the way to the goal, its left normal is across.
g = [2.0 / math.hypot(2.0, 1.2), 1.2 / math.hypot(2.0, 1.2)]
assert close(got[0]["y"], [0.6 * g[0], -0.6 * g[1]]), got[0]
assert close(got[1]["y"], [0.5 * g[1], 0.5 * g[0]]) and got[1]["correction"] is True, got[1]

print("export_dummy: ok")
