# Hardware

gehirn has never driven a real body. Every run flies `Sim` or the MuJoCo base, and the first real body is still PLAN's [Open question 1](../PLAN.md#open-questions-for-the-owner). This doc is for someone choosing or bringing one: what a body has to bring below the armor, how a body that can fall changes the safe state, and the hardware the owner is looking at. The tasks are PLAN's Phases 5 to 7, and the reasoning behind the split between the field unit and the motor controller is [ADR-0001](adr/0001-where-it-runs.md).

## What a body brings

The armor is a soft layer on an operating system without real time guarantees ([Safety](safety.md)). On hardware the same limits run again below the operating system, on a motor controller behind a physical e-stop, and the controller zeroes its outputs when commands go stale for 200 ms, as `Sim` and `body.Mujoco` do (PLAN, Invariant 10 and Phase 5). A body for gehirn brings:

- velocity commands on the plane, sideways too for the default `DRIVE=holonomic`, or speed and turn for `DRIVE=differential`;
- a percept of its pose and velocity, with obstacles from a range sensor and people from a detector, as `SENSING=range` takes them ([ADR-0011](adr/0011-sensing.md));
- its stopping distance, measured, which the armor widens every keep and the fence by (`Body.stopping`, [Safety](safety.md#how-the-body-moves));
- a watchdog that stops it when commands stop, and an e-stop that works without the field process;
- an aarch64 computer for the field unit, which ships as a static musl binary (Invariant 9), or a link to one.

## Stopping a body that can fall

IEC 60204-1 names three stops. Stop 0 cuts power at once. Stop 1 brings the machine to a controlled stop and then cuts power. Stop 2 brings it to a controlled stop and keeps power on. gehirn's safe state is stop 2 everywhere: a fault, a cut umbilical, a spent battery and the pilot's eject all leave the body holding at zero with power on. Phase 5's e-stop is stop 0. On a wheeled body both are safe, since a base that loses power just stands.

A legged body falls in stop 0, and it falls whenever its balance controller stops, so stop 2 depends on software that runs on an operating system, which Invariant 10 rules out for anything safety relevant. Its safe state has to be stop 1: a kneel or a sit into a pose that holds without power, then power off, with stop 0 kept for the hardware button. That touches:

- the empty battery of Invariant 6, which stands the body still at zero and would need a reserve for the kneel;
- Phase 5 Task 2's e-stop that cuts motor power, and its done criterion;
- every fault path that ends in a halt (CONTRIBUTING.md, Errors 2).

Open: an ADR on stopping a body that can fall, before any legged body. The simulated bodies cannot fall, so in the demo it would be a state, a reserve and a line on the bridge.

## Asimov 1

Menlo Research's open humanoid, sold as a DIY kit for $20,000 ([menlo.ai](https://menlo.ai), [docs.menlo.ai](https://docs.menlo.ai)). The owner watches it as the first real body and expects to join at its second version rather than build the first ([decisions](decisions.md#project)). As of 2026-11-06:

| Part | Asimov 1 |
| --- | --- |
| Size | 1.2 m, 35 kg |
| Joints | 25: 6 per leg, 5 per arm, 1 waist, 2 neck |
| Compute | Radxa CM5 for motion control, Raspberry Pi 5 for media and networking, both aarch64 |
| Sensing | 6 axis IMU, 2 MP monocular camera, stereo microphones, speaker |
| Power | 13S4P lithium ion, 491 Wh |
| Open | CAD, electrical design, bill of materials, MJCF and URDF models ([menloresearch/asimov-1](https://github.com/menloresearch/asimov-1)) |
| Not public | Firmware, which the docs list as coming soon, and Asimov Edge, the service on the robot that takes commands |

The robot walks on its own policy. A client sends velocity in its MOVE mode, and the robot has three modes: DAMP, where no actuator holds; STAND, which holds a pose and tips over unless supported; and MOVE, where the walking policy balances it at any velocity, zero included. Only MOVE stands free. A critical fault latches DAMP until the firmware restarts.

The wire is protobuf over UDP to Asimov Edge: commands to port 8850, state from port 8851, a version endpoint on port 3000. The schema ships as generated bindings in the MIT licensed `asimov-protocol` package on PyPI, 1.3.0rc4, whose source repository is not public. A velocity command carries `vx`, `vy` and `vyaw` with a sequence number and a timestamp. The Python `menlo-sdk` is one client of it, and gehirn could send the same datagrams from V with no Python in the loop. State streams at 200 Hz; the 10 Hz on the spec sheet is the app's telemetry. The SDK repeats a held velocity at 10 Hz as a keepalive, and Asimov Edge zeroes the velocity 2 s after the last command it received and keeps balancing in MOVE.

What fits gehirn:

- `vy` steps sideways, so the default holonomic drive fits it without `differential` ([decisions](decisions.md#stack), holonomic by default).
- The MJCF model can load into the MuJoCo of [ADR-0008](adr/0008-the-simulator.md), though it walks only with Menlo's policy in the loop, unlike `body.Mujoco`'s base on slides.
- The field unit's static aarch64 musl binary could run on the Pi 5. No run has tried it.
- The robot has a command arbiter and a safety layer of its own, and an E-Stop in its Asimov Manager app, an override toward safety as the stance welcomes ([decisions](decisions.md#stack)).

What it changes:

- A paired gamepad or a Drive Robot session in Asimov Manager outranks any script, so it drives the body around the armor (Invariant 1). Neither may be active while gehirn flies; a pilot steers through `gehirn-gamepad` and the plug instead.
- DAMP, a latched fault and a power cut all drop it ([Stopping a body that can fall](#stopping-a-body-that-can-fall)). Whether its walking policy runs behind real time guarantees is not in the public files.
- Its command timeout is 2 s against gehirn's 200 ms, so a field unit that dies leaves it walking for up to 2 s, about 1 m at 0.5 m/s. A field unit on the robot's Pi takes the network out of that; the rest needs a shorter timeout from Menlo or a watchdog of gehirn's own that trips the e-stop.
- Legs take a step or two to stop, so its stopping distance has to be measured with Menlo's policy on their model before the armor can use it.
- It has no range sensor, which the lidar below supplies.
- The protocol is a release candidate, so a client pins its version.

## A vacuum robot's lidar

The lidar comes from a used vacuum robot, which also brings bumpers, cliff sensors and wheel odometry. Its rotating lidar scans one plane all around, a few meters out, and on most models turns about five times a second. That gives ADR-0011's range ring a real source. A model whose lidar protocol is already reverse engineered saves writing a driver from scratch.

On a humanoid the scan plane tilts with every step, so the lidar sits at the hips or its scans are corrected by the IMU, and it sees one height only.

Whole, the vacuum is a wheeled base of a few kilograms that cannot fall, with those sensors and a charging dock: a possible first body for Phase 5 and ADR-0011 on `DRIVE=differential`, the option PLAN keeps for a wheeled first body (Open question 7). Open, not decided.
