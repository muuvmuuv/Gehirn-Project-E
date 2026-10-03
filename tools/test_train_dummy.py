#!/usr/bin/env python3
"""Self check for train_dummy: python3 tools/test_train_dummy.py"""

import json
import math
import os
import random
import subprocess
import sys
import tempfile

from train_dummy import INPUTS, VERSION, mse, predict, train

# plug/dummy_test.v test_policy_act expects the same command from plug/dummy.v Policy.act.
SHARED_NET = {"v": 1, "w1": [[0.5, -0.25, 0.0, 1.0, 0.0, 0.0, -0.5], [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]],
              "b1": [0.1, -0.2], "w2": [[1.0, -1.0], [0.5, 0.25]], "b2": [0.3, -0.1]}
SHARED_X = [2.0, -0.5, 0.25, 0.75, 0.0, -1.0, 0.5]
SHARED_Y = [1.2134674883172833, 0.3754798388849572]
assert all(math.isclose(a, b, abs_tol=1e-12) for a, b in zip(predict(SHARED_NET, SHARED_X), SHARED_Y))

# A pilot whose command is a smooth function of what the policy sees.
rnd = random.Random(7)
data = []
for _ in range(400):
    x = [rnd.uniform(0.35, 3.0)] + [rnd.uniform(-1.0, 1.0) for _ in range(INPUTS - 1)]
    data.append((x, [0.6 - 0.4 * x[3] * x[1], 0.3 * x[2] - 0.2 * x[5]], False))
net = train(data, hidden=8, epochs=30)
assert net == train(data, hidden=8, epochs=30), "the seed fixes the weights"
assert mse(net, data) < 0.1 * mse(train(data, hidden=8, epochs=0), data), mse(net, data)
assert net["v"] == VERSION and len(net["w1"]) == len(net["b1"]) == 8, net
assert all(len(r) == INPUTS for r in net["w1"]) and len(net["w2"]) == len(net["b2"]) == 2, net
assert all(len(r) == 8 for r in net["w2"]), net

# The same ticks once flown straight and once corrected to the left: the weight decides.
twins = [(x, [0.6, 0.0], False) for x, _, _ in data[:100]] + [(x, [0.6, 0.6], True) for x, _, _ in data[:100]]
across = [sum(predict(train(twins, hidden=4, epochs=20, corrections=c), x)[1] for x, _, _ in twins[:100]) / 100
          for c in (1.0, 5.0)]
assert 0.2 < across[0] < 0.4 < 0.45 < across[1], across

# From a set file to a weights file, and a line that is no sample refused with one line.
with tempfile.TemporaryDirectory() as d:
    path, out = os.path.join(d, "set"), os.path.join(d, "w.json")
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(json.dumps({"x": x, "y": y, "correction": c}) + "\n" for x, y, c in data[:50])
    tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), "train_dummy.py")
    run = subprocess.run([sys.executable, tool, path, "--out", out, "--hidden", "4", "--epochs", "2"],
                         capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    with open(out, encoding="utf-8") as f:
        assert len(json.load(f)["w1"]) == 4
    with open(path, "a", encoding="utf-8") as f:
        f.write('{"x": [1, 2], "y": [0, 0], "correction": false}\n')
    run = subprocess.run([sys.executable, tool, path, "--out", out], capture_output=True, text=True)
    assert run.returncode == 1 and run.stderr == f"train_dummy: {path} line 51 has 2 inputs and 2 outputs, not 7 and 2\n", run.stderr

print("train_dummy: ok")
