#!/usr/bin/env python3
"""Train the dummy plug's policy on a training set from tools/export_dummy.py.

The policy is a small multilayer perceptron: what plug/dummy.v observe sees, through one
layer of tanh units, to the command in the goal's frame. Adam fits it to the mean squared
error with the standard library only, and the seed fixes the result, so one set always gives
the same weights. Ticks the pilot flew to correct the dummy plug can weigh more than others.
The weights go to a JSON file that plug/dummy.v load_policy reads, by default the one gehirn
loads for pilot shinji:

    python3 tools/train_dummy.py dummy.shinji.set
    python3 tools/train_dummy.py dummy.shinji.set --out dummy.rei.json --corrections 3
"""

import argparse
import json
import math
import random
import sys
import time
from operator import mul

VERSION = 1  # plug/dummy.v policy_version: the weights format and the features of observe
INPUTS = 7  # plug/dummy.v inputs: the distance, then three numbers for a solid and a human
MAX_UNITS = 256  # plug/dummy.v max_units: the most tanh units gehirn accepts


def load_set(path: str) -> list[tuple[list[float], list[float], bool]]:
    """Return the samples of a training set, or exit with a line that says why not."""
    data = []
    try:
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                try:
                    s = json.loads(line)
                    x, y, c = [float(v) for v in s["x"]], [float(v) for v in s["y"]], s["correction"] is True
                except (ValueError, KeyError, TypeError):
                    sys.exit(f"train_dummy: {path} line {n} is no sample of tools/export_dummy.py")
                if len(x) != INPUTS or len(y) != 2:
                    sys.exit(f"train_dummy: {path} line {n} has {len(x)} inputs and {len(y)} outputs, "
                             f"not {INPUTS} and 2")
                data.append((x, y, c))
    except OSError as e:
        sys.exit(f"train_dummy: cannot read {path}: {e.strerror}")
    if not data:
        sys.exit(f"train_dummy: {path} holds no samples")
    return data


# The counterpart of predict() is plug/dummy.v Policy.act; tools/test_train_dummy.py and
# plug/dummy_test.v test_policy_act check one input against the same numbers.
def predict(net: dict, x: list[float]) -> list[float]:
    """Return the policy's command in the goal's frame, along and across, for the inputs x."""
    h = [math.tanh(b + sum(map(mul, row, x))) for row, b in zip(net["w1"], net["b1"])]
    return [b + sum(map(mul, row, h)) for row, b in zip(net["w2"], net["b2"])]


def train(data: list[tuple[list[float], list[float], bool]], hidden: int = 32, epochs: int = 40,
          lr: float = 0.01, batch: int = 64, seed: int = 1, corrections: float = 1.0,
          log: bool = False) -> dict:
    """Fit the policy to data, (inputs, command, correction) triples, and return its weights.

    A correction's error counts corrections times as much as another tick's. The learning rate
    falls from lr to a tenth of it over the epochs.
    """
    rnd = random.Random(seed)
    nin = len(data[0][0])
    w1 = [[rnd.gauss(0.0, 1.0 / math.sqrt(nin)) for _ in range(nin)] for _ in range(hidden)]
    b1 = [0.0] * hidden
    w2 = [[rnd.gauss(0.0, 1.0 / math.sqrt(hidden)) for _ in range(hidden)] for _ in range(2)]
    b2 = [0.0, 0.0]
    params = [*w1, b1, *w2, b2]  # rows in place, so Adam updates the weights themselves
    m = [[0.0] * len(p) for p in params]
    v = [[0.0] * len(p) for p in params]
    step = 0
    order = list(range(len(data)))
    for epoch in range(epochs):
        rate = lr * 0.1 ** (epoch / max(1, epochs - 1))
        rnd.shuffle(order)
        sse = 0.0
        for s in range(0, len(order), batch):
            xs, hs, e0, e1 = [], [], [], []
            for k in order[s:s + batch]:
                x, y, c = data[k]
                h = [math.tanh(b + sum(map(mul, row, x))) for row, b in zip(w1, b1)]
                d0 = b2[0] + sum(map(mul, w2[0], h)) - y[0]
                d1 = b2[1] + sum(map(mul, w2[1], h)) - y[1]
                sse += d0 * d0 + d1 * d1
                weight = corrections if c else 1.0
                xs.append(x)
                hs.append(h)
                e0.append(weight * d0)
                e1.append(weight * d1)

            # Gradients of the batch's mean, the back pass summed over the batch column by column.
            hcols = list(zip(*hs))
            dh = [[(a * w2[0][j] + b * w2[1][j]) * (1.0 - hk[j] * hk[j]) for a, b, hk in zip(e0, e1, hs)]
                  for j in range(hidden)]
            xcols = list(zip(*xs))
            grads = [[sum(map(mul, d, col)) for col in xcols] for d in dh]
            grads.append([sum(d) for d in dh])
            grads.append([sum(map(mul, e0, col)) for col in hcols])
            grads.append([sum(map(mul, e1, col)) for col in hcols])
            grads.append([sum(e0), sum(e1)])
            step += 1
            scale = 2.0 / len(xs)
            c1, c2 = 1.0 - 0.9 ** step, 1.0 - 0.999 ** step
            for p, g, mp, vp in zip(params, grads, m, v):
                for i, gi in enumerate(g):
                    gi *= scale
                    mp[i] = 0.9 * mp[i] + 0.1 * gi
                    vp[i] = 0.999 * vp[i] + 0.001 * gi * gi
                    p[i] -= rate * (mp[i] / c1) / (math.sqrt(vp[i] / c2) + 1e-8)
        if log and (epoch + 1) % 10 == 0:
            print(f"train_dummy: epoch {epoch + 1}, mean squared error {sse / len(order):.5f}", file=sys.stderr)
    return {"v": VERSION, "w1": w1, "b1": b1, "w2": w2, "b2": b2}


def mse(net: dict, data: list[tuple[list[float], list[float], bool]]) -> float:
    """Return the policy's mean squared error over data, every tick counted once."""
    return sum((p - t) ** 2 for x, y, _ in data for p, t in zip(predict(net, x), y)) / len(data)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])  # None under -OO
    ap.add_argument("set", help="training set from tools/export_dummy.py")
    ap.add_argument("--out", default="dummy.shinji.json", help="weights file, gehirn's DUMMY_WEIGHTS")
    ap.add_argument("--hidden", type=int, default=32, help=f"tanh units, 1 to {MAX_UNITS}")
    ap.add_argument("--epochs", type=int, default=40, help="passes over the set")
    ap.add_argument("--seed", type=int, default=1, help="seed of the initial weights and the order")
    ap.add_argument("--corrections", type=float, default=1.0,
                    help="how much more a pilot's correction of the dummy plug counts than another tick")
    args = ap.parse_args()
    if not 1 <= args.hidden <= MAX_UNITS:
        sys.exit(f"train_dummy: --hidden is {args.hidden}; accepted 1 to {MAX_UNITS}")

    data = load_set(args.set)
    t0 = time.monotonic()
    net = train(data, args.hidden, args.epochs, seed=args.seed, corrections=args.corrections, log=True)
    took = time.monotonic() - t0
    try:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(net, f)
    except OSError as e:
        sys.exit(f"train_dummy: cannot write {args.out}: {e.strerror}")
    corrections = sum(c for _, _, c in data)
    print(f"train_dummy: {len(data)} ticks, {corrections} corrections, {args.hidden} units, "
          f"{args.epochs} epochs in {took:.0f} s, mean squared error {mse(net, data):.5f}, to {args.out}")


if __name__ == "__main__":
    main()
