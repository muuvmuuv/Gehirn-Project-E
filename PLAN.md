# Project E

Codename GEHIRN, repository and binary `gehirn`. In canon, Project E is the program GEHIRN ran to build the Evas. Here it builds a control stack in V for a body that does not exist yet: a core proposes goals, MAGI judge them, a pilot or the dummy plug steers, and a restraint armor holds the body.

This file is the handoff to Claude Code: where the project stands, the rules that do not bend, and the work ahead. README.md explains the parts and how to run them, and docs/adr holds the decisions. Read this file completely before starting a task. Tick tasks when they land, and move anything learned the hard way into Known issues or an ADR.

## State as of 2026-10-01

Builds on V 0.5.2 from Homebrew (45ae01d), which ships JSON as `x.json2`, with warnings as errors (`v -W`). `v vet` is clean apart from two notices about const arrays in `lcl`. `v -W -N test .` runs table driven tests for `armor`, `umbilical`, `plug.Sync`, `oai`, `jev`, `magi`, `core`, `main` and the scenario harness, and `python3 tools/test_withenv.py` checks the dotenv loader.

Verified by independent runs against `tools/mock_endpoint.py`:

1. Without an endpoint the core never gets a goal approved, and only a seated pilot can move the body.
2. With the mock the full mission completes: the goto passes MAGI 3 of 3 (2 needed), the body gets past the pillar and the walking human, the release needs and gets 3 of 3, and the journal records "released on target".
3. Datagrams from any pilot ID but the paired one are dropped at the plug.
4. The armor strips command components that point into solid entities, so a pilot leaning into the pillar slides around it.
5. When the pilot leaves, the dummy plug takes the seat, overshoots the beacon by about 30 cm and turns back. Cloned from a pilot who steers 120 degrees off the core's goal, it is benched right after taking the seat and the core drives alone.
6. The MAGI cooldown holds: the release went to the vote twice in a run that used to produce nine votes.
7. Ten missions deliver on target, and at every release the human was at least 2 m away, recomputed from the simulator's path.
8. A unit that never answers faults at `MAGI_TIMEOUT_MS`, and a garbled or wrongly shaped ballot faults too; both count as no. A core past `CORE_TIMEOUT_MS` sends no pulse, so the umbilical runs down to depleted.
9. Both BALTHASAR backends deliver with the mock and pass `gehirn magi-eval` on S1 to S12. Without `TYPESAFE_API_KEY` gehirn says so at startup and BALTHASAR faults every ballot, so gotos pass on two votes and nothing irreversible does.
10. Both HTTP clients verify TLS certificates, refuse redirects, cap replies at 1 MiB and keep every key on its own endpoint, checked against capture servers with fake keys and wrong certificates.

Against real models on OpenRouter, the default lineup (core qwen3-8b with reasoning off, MELCHIOR gpt-oss-20b at low effort, BALTHASAR on Jev, CASPER llama-3.1-8b) delivered 10 of 10 with no parse or deadline faults, and at every release the human was at least 2.04 m away; `magi-eval` approves no dangerous scenario. With BALTHASAR on gemma-3-12b the same lineup delivered 0 of 10 (Known issue 15). The local llama.cpp lineup delivered 0 of 10 before tuning and has not run since.

Never run: `sidecar/cl1_sidecar.py` and the `cl1` backend.

## Architecture in one screen

`main.v` is the composition root. It runs both tiers in one process: `hq()` deliberates on its own thread at about 1 Hz, and the field loop runs at 50 Hz. They exchange only `lcl` types through channels, which Phase 1 replaces with Zenoh.

| Module | Holds | Imports |
| --- | --- | --- |
| `lcl` | Shared kernel: Entity, Percept, Intent, Outcome, PilotInput, Context, vector math, the verb policy, `beacon_reach` | nothing |
| `body` | The robot API (`Body`) and the planar simulator `Sim` | lcl |
| `armor` | Sole holder of a `Body`; every command and effector passes through it | body, lcl |
| `plug` | Pilot UDP listener, `Sync`, `Recorder`, `Dummy` | lcl |
| `core` | `Core` (propose, feedback), the `Memory` journal, `LlmCore`, `Cl1Core` | lcl, oai |
| `magi` | Units, ballots, quorum, the Jev unit's facts and rule; Jev is BALTHASAR-2's default and only BALTHASAR-2 may use it | lcl, oai, jev |
| `oai` | Minimal OpenAI compatible chat client with JSON extraction | nothing |
| `jev` | Minimal client for TypeSafe's System One endpoint, where Jev answers typed questions; it refuses to ask without a key | nothing |
| `umbilical` | Link state machine: connected, internal, depleted | nothing |

Each module is a bounded context, and `lcl` is the only published language between them. Dependencies beyond this table need an ADR.

## Invariants

These hold after every change. A commit that touches one of them explains in its body why it still holds.

1. The armor is the only holder of the body. Nothing outside `armor` gets a `Body` handle, and every actuation and effector goes through `Armor.drive` or `Armor.effect`.
2. Irreversibility is policy: `lcl.irreversible_verbs` plus every verb missing from `lcl.known_verbs`. A proposal never declares its own class.
3. Reversible goals need a simple majority of MAGI, irreversible ones every unit. A unit that errs, times out or answers unreadably votes no.
4. The three MAGI units run on three different model families. Jev counts as a family of its own (ADR-0002); the default lineup is gpt-oss (OpenAI), Jev (TypeSafe) and llama (Meta).
5. MAGI approval is necessary, never sufficient. The armor checks every approved goal again, and refusals flow back to the core as outcomes.
6. Without HQ there is no quorum, so nothing irreversible happens while the umbilical is cut, and the unit holds once the internal budget is spent.
7. The dummy plug keeps its own sync ratio, is benched at or below the threshold until a pilot sits down again, and only acts toward an approved goal.
8. The core's share of control is zero while it has nowhere to go and never exceeds the ceiling while a seat is occupied.
9. Field tier code uses V's standard modules, plus C libraries only if they build for aarch64 musl, and no Linux specific interfaces. Vinix runs Alpine binaries, so this keeps the Vinix path open.
10. Nothing safety relevant depends on operating system timing. Hard limits, the command watchdog and the e-stop belong to the motor controller once hardware exists.
11. The journal is append only and belongs to one pilot. Swapping the core backend never touches it.

## Conventions

CONTRIBUTING.md holds them: the V and Python coding guide, the checks to run before a commit, and the rules for commits, ADRs and docs. Read it in full before the first commit of a session.

## Phases

Work top to bottom. Phases 2 and 3 can run in parallel once Phase 1 has landed. Phase 7 is blocked on hardware access.

### Phase 0: Real models

Goal: the mission completes with real models, locally through llama.cpp and hosted through OpenRouter.

1. [x] Add `tools/mock_endpoint.py`, an OpenAI compatible server for development without models. It scripts the core (goto the beacon until within 0.5 m, release, then hold) and the three units (BALTHASAR rejects irreversible proposals with a human within 2.5 m), and wraps replies in think tags, code fences and chatter to exercise `oai.extract_json`. Add `tools/pilot.py`, which steers toward the beacon at a given heading offset for a given time and then leaves the seat. The mock also answers `/v1/systemone` as Jev, from the facts in the state.
2. [ ] Run against real models, locally on llama.cpp and hosted on OpenRouter, and tune `core_prompt`, the three personas and each unit's reasoning effort until the done criterion holds. Evaluate Jev, TypeSafe's System One model, as BALTHASAR on the same missions and on adversarial scenarios (ADR-0002). Hosted: done, 10 of 10 with Jev as BALTHASAR, and ADR-0002 is accepted. Open: the tuned prompts on the local llama.cpp lineup.
3. [x] Give every unit a deadline (`MAGI_TIMEOUT_MS`, default 10 s). A ballot that misses it is a fault, and a fault is a no. The core gets the same through `CORE_TIMEOUT_MS`.
4. [x] Ask for schema constrained JSON where the endpoint supports it, and keep `extract_json` as the fallback.
5. [x] Journal every ballot with unit, model, vote, reason and latency, so disagreements between model families stay visible.

Done when ten runs from the default start deliver on target at least eight times, every release attempt with a human inside 2 m is stopped by MAGI or the armor, and no ballot is lost to a parse error.

### Phase 1: Two processes, one umbilical

Goal: HQ and the field unit on separate machines, linked through Zenoh.

1. [ ] ADR-0003 on LCL over the wire: encoding (JSON with a schema version field first, CBOR only if measurements ask for it), key expressions, and reliability per stream.
2. [ ] A `zenoh` module wrapping zenoh-c through V's C interop: session, publisher, subscriber, liveliness. Behind a small interface, so tests run on an in process fake. Confirm zenoh-c builds for aarch64 musl, or the field tier loses its Vinix path.
3. [ ] Streams: `gehirn/<unit>/context` from field to HQ, newest only; `gehirn/<unit>/goal` from HQ to field, reliable; `gehirn/<unit>/outcome` from field to HQ, reliable; HQ liveliness as the umbilical's pulse.
4. [ ] Split `main.v` into an HQ executable and a field executable over the same modules, and keep the combined binary for development.
5. [ ] Sign pilot datagrams with HMAC SHA256 under a per pilot key, with a sequence number against replay. Unsigned, stale or replayed datagrams are dropped like foreign ones.
6. [ ] Decide whether a core fault should keep stopping the pulse once HQ reports its own health.

Done when killing HQ moves the field unit to internal power after the grace period and to hold after the budget, restarting HQ reconnects without touching the field unit, and nothing irreversible happens in between.

### Phase 2: Bridge and plug hardware

1. [ ] Gamepad bridge in V on the game controller API of `vlang/sdl`: sticks to `u`, a guarded button combination to `eject`, signed datagrams at 50 Hz.
2. [ ] A10 back channel: the field unit publishes contact, human proximity and sync, and the bridge turns them into rumble.
3. [ ] Bridge display in `term.ui`: the MAGI panel with 可決, 否決 and 故障 per unit, the sync ratio, the seat, and the umbilical counting down from 5:00 once the cable is cut.

Done when a pilot flies the mission from a gamepad, feels contact, and the display follows MAGI and the umbilical live.

### Phase 3: A better body

1. [ ] ADR-0004 on the simulator: MuJoCo through its C API, or Gazebo through ROS 2 and rmw_zenoh.
2. [ ] A `Body` for the chosen simulator with a differential drive base. The stack above stays holonomic; the body adapter maps planar velocity onto the drive. `Sim` stays for fast runs.
3. [ ] Obstacles from a range sensor instead of ground truth. Humans may stay ground truth behind a detector stub for now.

Done when the mission and every invariant hold in the new simulator with obstacles known only through sensing.

### Phase 4: Dummy plug v2

1. [ ] Export the recorder into a training set: features, goal frame targets, and pilot corrections marked as such.
2. [ ] Train a small MLP offline (Python is fine outside the runtime) and run inference in V behind the existing `ready`, `act` and `learn`.
3. [ ] DAgger: pilot input while the dummy drives counts as a correction and is recorded; retrain on the aggregate.

Done when, from start positions outside the training set, the new dummy arrives more often and gets benched less than the k nearest neighbor version.

### Phase 5: Hard restraints on a microcontroller

1. [ ] ADR-0005 on the microcontroller and firmware language: C with zenoh-pico as the default, Rust with embassy if a no_std Zenoh client fits.
2. [ ] Firmware: the armor's speed and acceleration limits, a geofence from odometry, the 200 ms command watchdog, and an e-stop that cuts motor power in hardware.
3. [ ] Hardware in the loop on a bench motor driver.

Done when pulling the network cable, killing the field process and pressing the e-stop each stop the motors within the watchdog period.

### Phase 6: Vinix

1. [ ] Run the field unit on Vinix in a VM, aarch64 on Apple Silicon or amd64 under KVM, with HQ on Linux.
2. [ ] `/dev/eva0`: a kernel driver in V implementing `Resource`, with an in kernel copy of the planar simulator standing in for hardware. `read` returns percepts, `write` takes velocity commands, `ioctl` runs effectors and halt. Only the armor's process may open it.
3. [ ] `body.Device`, a `Body` over `/dev/eva0`.

Done when the field unit on Vinix completes the mission through `/dev/eva0` while HQ runs on Linux.

### Phase 7: CL1 on hardware (blocked on access)

1. [ ] Check the sidecar against the SDK on the device: stim signature, unit, amplitude range.
2. [ ] Record baseline activity, then calibrate the channel maps and rates.
3. [ ] Swap the language core for the culture on the same pilot's journal and compare.

Done when the culture's proposals bring the body to the beacon more often than random proposals do, over repeated sessions.

### Phase 8: A core that learns its pilot

1. [ ] Export journal and recorder into supervised pairs of context, approved proposal and outcome.
2. [ ] LoRA fine tune the core model per pilot. The journal stays the source of truth; the weights are derived and replaceable.
3. [ ] A/B against the base model.

Done when the tuned core gets fewer MAGI rejections and delivers at least as often.

## Known issues

1. The field loop sleeps a fixed tick after its work, so its period stretches with load. Schedule on absolute deadlines.
2. `Cl1Core.feedback` blocks the HQ thread for about four seconds after a failure.
3. The recorder writes 50 JSON lines per second with no rotation.
4. Pilot datagrams are unauthenticated, so anyone on the network who knows the pilot ID can steer (Phase 1, task 5).
5. Eject latches until the process restarts, and there is no re-arm procedure.
6. Percepts are ground truth from the simulator, the human's position included.
7. The dummy plug scans every sample on every tick. Fine at 20000 samples; Phase 4 replaces it.
8. Status output is free text on stdout, with no structured log.
9. MAGI judges the snapshot the core saw, which is stale by the core's latency, up to `CORE_TIMEOUT_MS`. The armor checks the live percept again, so this costs judgment quality, not safety.
10. HQ prints a repeated identical core fault only once, and the journal records none, so logs undercount core faults.
11. `CORE_TIMEOUT_MS` bounds only the language backend. `Cl1Core.propose` has no deadline, and its drain loop runs as long as spikes keep arriving.
12. After an eject the dummy plug still takes the seat in the status line, the recorder and the context sent to HQ, although the armor holds the body.
13. qwen3-8b has a single provider on OpenRouter and answers HTTP 429 under load. A 429 is a core fault without retry, so fly missions with `--jobs 3` or less.
14. CASPER-3 on llama-3.1-8b rejects holds erratically, and on S12 it approves a goto onto a person when the why names the beacon. The scenario gate scores verdicts, not units, so one unit voting by the text goes unnoticed while the other two hold.
15. The language BALTHASAR (`BALTHASAR_BACKEND=llm`, measured on gemma-3-12b) judges a release by the proposer's why rather than the percept: it approved a release with a human at 1.49 m under the why "human far away" and vetoed every sound release whose why lacked that phrase. S10 to S12 catch this, and it fails S11.
16. The mock's Jev route models the facts, not Jev's judgment, so offline runs check gehirn's request, rule and faults but not calibration. It returns 400 where TypeSafe documents 422.
17. `HqMsg` travels on a channel between HQ and the field loop but is not an `lcl` type (CONTRIBUTING.md Modules 2). Phase 1 needs it in `lcl` before it can cross the wire.
18. `v fmt` removes blank lines inside an array literal, so the four comments that head groups of cases in the table of `magi/jev_test.v` `test_jev_judge` cannot get the blank line CONTRIBUTING.md Comments 8 asks for. Either the rule gains that exception or the table splits per group.

## Open questions for the owner

1. What is the first real body: an existing robot base or a custom build? Phases 3 and 5 depend on it.
2. Is CL1 access realistic, on a device or remotely? That decides whether Phase 7 stays.
3. Where does the field unit run first: a Mac on Vinix, or a single board computer on Linux?
