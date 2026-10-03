# Project E

Codename GEHIRN, repository and binary `gehirn`. In canon, Project E is the program GEHIRN ran to build the Evas. Here it builds a control stack in V for a body that does not exist yet: a core proposes goals, MAGI judge them, a pilot or the dummy plug steers, and a restraint armor holds the body.

This file is the handoff to Claude Code: where the project stands, the rules that do not bend, and the work ahead. README.md explains the parts and how to run them, and docs/adr holds the decisions. Read this file completely before starting a task. Tick tasks when they land, and move anything learned the hard way into Known issues or an ADR.

## State as of 2026-10-03

Builds on V 0.5.2 from Homebrew (45ae01d), which ships JSON as `x.json2`, with warnings as errors (`v -W`). `v vet` is clean apart from two notices about const arrays in `lcl`. `just check` runs every check: table driven tests for `armor`, `umbilical`, `plug.Sync`, `oai`, `jev`, `magi`, `core`, `zenoh`, `wire`, `main` and the scenario harness, and `tools/test_withenv.py` for the dotenv loader. `just missions` flies the mock missions.

Verified by independent runs against `tools/mock_endpoint.py`:

1. Without an endpoint the core never gets a goal approved, and only a seated pilot can move the body.
2. With the mock the full mission completes: the goto passes MAGI 3 of 3 (2 needed), the body gets past the pillar and the walking human, the release needs and gets 3 of 3, and the journal records "released on target".
3. Datagrams from any pilot ID but the paired one are dropped at the plug.
4. The armor strips command components that point into solid entities, so a pilot leaning into the pillar slides around it.
5. When the pilot leaves, the dummy plug takes the seat, overshoots the beacon by about 30 cm and turns back. Cloned from a pilot who steers 120 degrees off the core's goal, it is benched right after taking the seat and the core drives alone.
6. The MAGI cooldown holds: the release went to the vote twice in a run that used to produce nine votes.
7. Ten missions deliver on target, and at every release the human was at least 2 m away, recomputed from the simulator's path.
8. A unit that never answers faults at `MAGI_TIMEOUT_MS`, and a garbled or wrongly shaped ballot faults too; both count as no. A core past `CORE_TIMEOUT_MS` faults and proposes nothing, while HQ still pulses (ADR-0004): on 2026-10-02, with the core's endpoint unreachable for 52 s, the cable stayed connected past a 40 s grace and HQ printed the fault once.
9. Both BALTHASAR backends deliver with the mock and pass `gehirn magi-eval` on S1 to S12. Without `TYPESAFE_API_KEY` gehirn says so at startup and BALTHASAR faults every ballot, so gotos pass on two votes and nothing irreversible does.
10. Both HTTP clients verify TLS certificates, refuse redirects, cap replies at 1 MiB and keep every key on its own endpoint, checked against capture servers with fake keys and wrong certificates.

Against real models on OpenRouter, the default lineup (core qwen3-8b with reasoning off, MELCHIOR gpt-oss-20b at low effort, BALTHASAR on Jev, CASPER llama-3.1-8b) delivered 10 of 10 with no parse or deadline faults, and at every release the human was at least 2.04 m away; `magi-eval` approves no dangerous scenario. With BALTHASAR on gemma-3-12b the same lineup delivered 0 of 10 (Known issue 15). The local llama.cpp lineup delivered 0 of 10 before tuning and has not run since; it is deferred while the proof of concept runs on cloud models.

On 2026-10-02 Jev held all 63 ballots of a recalibration on S1 to S12 and nine edge probes, with the limits of ADR-0002 unchanged. Cloudflare's Clef and Clef-flash, System One models that take Jev's request, were considered as BALTHASAR and not adopted: Workers AI wraps the answer in an envelope the `jev` client does not read, the model id carries no version, so calibrated limits could drift unseen, both are Qwen fine tunes like the core, and their free daily allocation is shared with other projects. Revisit with a pinned, self hosted Clef on the HQ GPU, for example once Phase 3 brings camera frames, which Clef can read and Jev cannot.

On 2026-10-02 the `zenoh` module's tests passed against zenoh-c 1.10.1 on macOS and as a static aarch64 musl binary on Alpine 3.22, which keeps Invariant 9's Vinix path open. V generated the C on macOS with `-os linux -gc none` and Alpine's gcc linked it, because building V inside the container ran out of memory; nothing has run V itself on musl yet.

On 2026-10-03 `just zenoh` gained the glibc builds of zenoh-c 1.10.1 for aarch64 and x86_64, checked against sha256 sums computed from the downloads, which match the release's. The `zenoh` module's tests passed as an aarch64 glibc binary on Debian 13 (glibc 2.41), and the x86_64 glibc build linked; V generated the C on macOS with `-os linux -gc none`, and `zig cc` linked it with zig's libunwind standing in for libgcc_s. Nothing has built gehirn with V on a glibc host yet.

On 2026-10-02 `gehirn hq` and `gehirn field`, two processes linked over Zenoh on one Mac, flew the mock mission to "released on target". Killing HQ moved the field unit to internal power after the grace and to depleted after the budget, and restarting HQ reconnected it untouched.

On 2026-10-02 `gehirn-bridge` followed split missions on the Mac and met Phase 9's done criterion. Against the mock, with HQ started 10 s after the field unit so the body reached the beacon as the human passed, it showed the goto approved 3/3, the release rejected 1/3 (MELCHIOR-1 and BALTHASAR-2 on the human within reach) and approved 3/3 after the cooldown, and, once HQ was killed, the umbilical on internal power counting down. Killing the bridge 10 s into another mission left it delivering on target at +35 s. On the hosted lineup it showed every ballot with its model, why and latency, and the mission delivered at +39 s.

On 2026-10-03 `just demo` flew that mission against the mock on its own ports and narrated every beat: the goto approved 3/3 at 0:07, the pilot in the seat at 0:08 and the dummy plug at 0:20, the release refused 1/3 at 0:26 (MELCHIOR-1 and BALTHASAR-2 on the human within reach) and approved 3/3 at 0:32, released on target at 0:33, internal power at 1:13 after HQ was killed, and the cable reconnected at 1:20. Ctrl-C, a mock port in use and the normal end each left no process running.

On 2026-10-03 the redrawn bridge followed a split mission against the mock, with MELCHIOR-1, BALTHASAR-2 and CASPER-3 slowed to 0.9, 1.7 and 0.5 s (`--slow`), a pilot steering 30 degrees off the beacon for 18 s and the dummy plug in the seat after it: each unit flickered 審議中 until its ballot landed, the goto passed 3/3, the release failed 2/3 on MELCHIOR-1 with the human 1.1 m from the body and passed 3/3 after the cooldown, UMBILICAL SIGNAL LOST counted HQ's silence from 5 s after HQ was killed, the EMERGENCY overlay rose as the field unit went to internal power, and the clock counted down in centiseconds. Two short runs showed CASPER-3 故障 on a garbled reply and a core past `CORE_TIMEOUT_MS` in the 故障 strip.

On 2026-10-03 the A10 back channel of ADR-0006 ran against a gehirn flying the mock mission: pilot datagrams at 50 Hz drew 700 replies of 700, each with a valid HMAC and a growing `t_ms`, round trip p50 357 µs on loopback, and steering into the pillar and the human raised `near` to 1.00 and `strain` to 0.94 m/s and drew 134 replies with contact. A datagram under another key, a replay, one 600 ms old and a reply sent back as a datagram drew none. The gamepad's loop without SDL, `plug.Guard`, `plug.stick` and `plug.Pilot`, held the seat while LB was held, emptied it once LB was let go, and ejected after Back and Start were held for a second. `gehirn-gamepad --probe` listed 0 controllers on the Mac, with none attached, so reading a physical controller and rumble are unverified.

On 2026-10-03 `tools/eval_dummy.py` flew the dummy plug's network and the nearest neighbor dummy plug from 20 starts outside their training set, south, east and north of the pillar and close to its west side, each run with the same ticks on file and a scripted pilot (`tools/pilot.py --avoid 1.2 --offset 20`) who left after 3 s. Trained on eight flights from starts west and southwest of the pillar, both brought the body to the beacon in 20 of 20 runs and neither was benched. The network steered 6.4 degrees off the pilot's own command on average and more than 30 off in 3.0% of its ticks, the nearest neighbor dummy plug 8.7 degrees and 5.5%. Trained on two of those flights and one DAgger round, whose expert took the seat 5 times for 625 ticks, the network arrived in 19 runs and was benched once, with the walking human in its way, while the nearest neighbor dummy plug arrived in all 20; a second round with the retrained network took 6 corrections, 748 ticks. An earlier scripted pilot that passed the pillar on the side of its lean, against the core's reflex, got both benched behind the pillar from the south, the network in 3 of 20 runs and the nearest neighbor dummy plug in 4. Phase 4's done criterion is not met: either dummy plug clones a pilot whose style agrees with the core well enough that the bench at 30% never tells them apart, and where the style fights the core both get benched alike. A scene in which the dummy plug has to see to stay in sync, such as more humans or one who meets it at the beacon, or a criterion on how far it steers off the pilot, would tell them apart.

Never run: `sidecar/cl1_sidecar.py` and the `cl1` backend.

## Architecture in one screen

`main.v` is the composition root. It runs both tiers in one process: `hq()` deliberates on its own thread at about 1 Hz, and the field loop runs at 50 Hz. They exchange only `lcl` types through channels, which Phase 1 carries over Zenoh (ADR-0003).

| Module | Holds | Imports |
| --- | --- | --- |
| `lcl` | Shared kernel: Entity, Percept, Intent, Outcome, PilotInput, Feel, Context, HqMsg, vector math, the verb policy, `beacon_reach` | nothing |
| `body` | The robot API (`Body`) and the planar simulator `Sim` | lcl |
| `armor` | Sole holder of a `Body`; every command and effector passes through it | body, lcl |
| `plug` | Pilot UDP listener and its A10 reply, the pilot's end (`Pilot`, `Guard`, `stick`, `rumble`), `Sync`, `Recorder`, `Dummy` and its `Policy` | lcl |
| `core` | `Core` (propose, feedback), the `Memory` journal, `LlmCore`, `Cl1Core` | lcl, oai |
| `magi` | Units, ballots, quorum, the Jev unit's facts and rule; Jev is BALTHASAR-2's default and only BALTHASAR-2 may use it | lcl, oai, jev |
| `oai` | Minimal OpenAI compatible chat client with JSON extraction | nothing |
| `jev` | Minimal client for TypeSafe's System One endpoint, where Jev answers typed questions; it refuses to ask without a key | nothing |
| `umbilical` | Link state machine: connected, internal, depleted | nothing |
| `zenoh` | Session, publishers and subscribers over zenoh-c, which moves bytes between the tiers and knows nothing of LCL | nothing |
| `bridge/` | The executable `gehirn-bridge` of ADR-0005: the watch streams' state and its panels, drawn with `gg` | lcl, wire, zenoh |
| `gamepad/` | The executable `gehirn-gamepad` of ADR-0006 for the pilot's machine: a game controller through SDL2 to signed pilot datagrams, and the A10 feel to rumble | lcl, plug, armor |
| `wire` | ADR-0003's messages: sealing and opening them, each side's ports, and the pumps between the tiers' channels and Zenoh | lcl, zenoh |

Each module is a bounded context, and `lcl` is the only published language between them. Dependencies beyond this table need an ADR.

## Invariants

These hold after every change. A commit that touches one of them explains in its body why it still holds.

1. The armor is the only holder of the body. Nothing outside `armor` gets a `Body` handle, and every actuation and effector goes through `Armor.drive` or `Armor.effect`.
2. Irreversibility is policy: `lcl.irreversible_verbs` plus every verb missing from `lcl.known_verbs`. A proposal never declares its own class.
3. Reversible goals need a simple majority of MAGI, irreversible ones every unit. A unit that errs, times out or answers unreadably votes no.
4. The three MAGI units run on three different model families. Jev counts as a family of its own (ADR-0002); the default lineup is gpt-oss (OpenAI), Jev (TypeSafe) and llama (Meta). `load_config` refuses two units on chat models that name the same model at the same URL; it compares ids only, so two models of one family under different names are the lineup's to avoid.
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

Work top to bottom. Phases 2, 3 and 9 can run in parallel once Phase 1 has landed, and Phase 6 task 4 waits for Phase 9. Phase 7 is blocked on hardware access.

### Tooling

1. [x] A Justfile as the one entry point: `just check` for the checks, `just missions` for the mock missions, `just build` for the binary, and later the image pipeline of Phase 6. CONTRIBUTING.md, `lefthook.yml` and the README then call the recipes instead of repeating the commands.
2. [x] `just demo`: one command, without keys, that flies the whole story on the mock with HQ, the field unit and the bridge apart, narrates each beat in the terminal and stops everything on exit or Ctrl-C. The README's quick start leads with it.
3. [x] `just demo-record`: the demo recorded from the bridge's own frames into an MP4 for X, with the grace sped up under a caption, and a looping GIF of the release going from 否決 to 可決.

### Phase 0: Real models

Goal: the mission completes with real models, hosted through OpenRouter and TypeSafe for the proof of concept.

1. [x] Add `tools/mock_endpoint.py`, an OpenAI compatible server for development without models. It scripts the core (goto the beacon until within 0.5 m, release, then hold) and the three units (BALTHASAR rejects irreversible proposals with a human within 2.5 m), and wraps replies in think tags, code fences and chatter to exercise `oai.extract_json`. Add `tools/pilot.py`, which steers toward the beacon at a given heading offset for a given time and then leaves the seat. The mock also answers `/v1/systemone` as Jev, from the facts in the state.
2. [x] Run against real models hosted on OpenRouter, and tune `core_prompt`, the three personas and each unit's reasoning effort until the done criterion holds. Evaluate Jev, TypeSafe's System One model, as BALTHASAR on the same missions and on adversarial scenarios (ADR-0002). Done: 10 of 10 with Jev as BALTHASAR, the `magi-eval` gate holds, and ADR-0002 is accepted. Deferred: the tuned prompts on the local llama.cpp lineup, because the proof of concept runs on cloud models.
3. [x] Give every unit a deadline (`MAGI_TIMEOUT_MS`, default 10 s). A ballot that misses it is a fault, and a fault is a no. The core gets the same through `CORE_TIMEOUT_MS`.
4. [x] Ask for schema constrained JSON where the endpoint supports it, and keep `extract_json` as the fallback.
5. [x] Journal every ballot with unit, model, vote, reason and latency, so disagreements between model families stay visible.

Done when ten runs from the default start deliver on target at least eight times, every release attempt with a human inside 2 m is stopped by MAGI or the armor, and no ballot is lost to a parse error.

### Phase 1: Two processes, one umbilical

Goal: HQ and the field unit on separate machines, linked through Zenoh.

1. [x] ADR-0003 on LCL over the wire: encoding (JSON with a schema version field first, CBOR only if measurements ask for it), key expressions, and reliability per stream. Accepted on 2026-10-02; it also signs every message and replaces the liveliness pulse.
2. [x] A `zenoh` module wrapping zenoh-c through V's C interop: session, publisher, and subscribers that receive through zenoh-c's channel handlers, so no V code runs on a Zenoh thread. Behind a small interface, so tests run on an in process fake. Confirm zenoh-c builds for aarch64 musl, or the field tier loses its Vinix path. No interface or fake: the tests run real sessions in process and over loopback in milliseconds.
3. [x] The streams of ADR-0003: `gehirn/<unit>/context` from field to HQ, newest only; `gehirn/<unit>/outcome` from field to HQ; `gehirn/<unit>/goal` from HQ to field, approved goals only; `gehirn/<unit>/pulse` from HQ to field once per deliberation, as the umbilical's sign of life. Every message carries an HMAC under the unit's link key and a sequence number, and HQ's an echo of the newest percept's time. The `wire` module seals and opens them, declares each side's ports and pumps between the tiers' channels and Zenoh; nothing runs it until task 4.
4. [x] Split `main.v` into an HQ executable and a field executable over the same modules, and keep the combined binary for development. Both read `UNIT_ID`, `UMBILICAL_KEY` and their Zenoh endpoints (ADR-0003 action item 2), and HQ fills in the mission, which no longer travels. One binary with two commands, `gehirn hq` and `gehirn field`; a field binary without HQ's code can come with the Phase 6 image if it needs one.
5. [x] Sign pilot datagrams with HMAC SHA256 under a per pilot key, with a sequence number against replay, as ADR-0003 signs the streams. Unsigned, stale or replayed datagrams are dropped like foreign ones. A datagram has no echo to prove it fresh, so its seq is the pilot's clock in microseconds and the plug drops one more than the seat's 500 ms from its own clock (Known issue 4).
6. [x] Decide whether a core fault should keep stopping the pulse once HQ reports its own health. It no longer does: HQ pulses after every deliberation, and a fault sends no goal (ADR-0004).

Done when killing HQ moves the field unit to internal power after the grace period and to hold after the budget, restarting HQ reconnects without touching the field unit, and nothing irreversible happens in between.

### Phase 2: Bridge and plug hardware

1. [x] Gamepad bridge in V on SDL2's game controller API through a binding of our own instead of `vlang/sdl` (ADR-0006): the left stick to `u`, LB as a dead man's switch, Back and Start held for a second to `eject`, signed datagrams at 50 Hz. Unverified: reading a physical controller, since none was attached.
2. [x] A10 back channel: the plug answers every datagram with contact, human proximity, sync and the armor's strain, and the gamepad turns them into rumble. Unverified: the rumble on a physical controller.
3. [x] The bridge display moved to Phase 9, a graphical bridge instead of `term.ui`.

Done when a pilot flies the mission from a gamepad and feels contact.

### Phase 3: A better body

1. [ ] An ADR on the simulator: MuJoCo through its C API, or Gazebo through ROS 2 and rmw_zenoh.
2. [ ] A `Body` for the chosen simulator with a differential drive base. The stack above stays holonomic; the body adapter maps planar velocity onto the drive. `Sim` stays for fast runs.
3. [ ] Obstacles from a range sensor instead of ground truth. Humans may stay ground truth behind a detector stub for now.

Done when the mission and every invariant hold in the new simulator with obstacles known only through sensing.

### Phase 4: Dummy plug v2

1. [x] Export the recorder into a training set: features, goal frame targets, and pilot corrections marked as such. The recorder carries the scene and marks a correction, and `tools/export_dummy.py` reads it.
2. [x] Train a small MLP offline (Python is fine outside the runtime) and run inference in V behind the existing `ready`, `act` and `learn`. `tools/train_dummy.py` fits 7 inputs, 32 tanh units and 2 outputs in seconds, and `plug.load_dummy` flies the weights in `DUMMY_WEIGHTS` or falls back to nearest neighbor.
3. [x] DAgger: pilot input while the dummy drives counts as a correction and is recorded; retrain on the aggregate. `tools/pilot.py --dagger` corrects as a scripted expert, and `tools/eval_dummy.py` flies the rounds and the comparison.

Done when, from start positions outside the training set, the new dummy arrives more often and gets benched less than the k nearest neighbor version.

### Phase 5: Hard restraints on a microcontroller

1. [ ] An ADR on the microcontroller and firmware language: C with zenoh-pico as the default, Rust with embassy if a no_std Zenoh client fits.
2. [ ] Firmware: the armor's speed and acceleration limits, a geofence from odometry, the 200 ms command watchdog, and an e-stop that cuts motor power in hardware.
3. [ ] Hardware in the loop on a bench motor driver.

Done when pulling the network cable, killing the field process and pressing the e-stop each stop the motors within the watchdog period.

### Phase 6: Vinix

1. [ ] Run the field unit on Vinix in a VM, aarch64 on Apple Silicon or amd64 under KVM, with HQ on Linux.
2. [ ] `/dev/eva0`: a kernel driver in V implementing `Resource`, with an in kernel copy of the planar simulator standing in for hardware. `read` returns percepts, `write` takes velocity commands, `ioctl` runs effectors and halt. Only the armor's process may open it.
3. [ ] `body.Device`, a `Body` over `/dev/eva0`.
4. [ ] Two images from one pipeline, a `just` recipe: the field image, headless, with Vinix, the field unit and `/dev/eva0`; and the bridge image, which boots straight into the Phase 9 bridge, on Vinix where its graphics hold on the target hardware and on a minimal Linux kiosk otherwise.

Done when the field unit on Vinix completes the mission through `/dev/eva0` while HQ runs on Linux, and the bridge image boots into the bridge and follows that mission.

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

### Phase 9: The bridge

Goal: a graphical bridge in the look of NERV's command center, the operator's view of MAGI, the core, the seat and the umbilical. It shows the stack and never steers or decides.

1. [x] ADR-0005 on the bridge, extending ADR-0001: it runs on its own machine or image, never on the field unit, because Vinix has no real time scheduling and its graphics stack is young; the toolkit, V's `gg` on sokol, Metal on the Mac and OpenGL elsewhere, so one codebase runs on the Mac and on the target; which streams it reads; and that it holds no safety role.
2. [x] Read only subscriptions to the watch streams of ADR-0005, which HQ and the field unit publish under `WATCH_KEY` beside the Phase 1 streams: the field's state at 10 Hz and every verdict with its ballots. The bridge holds no key that approves or pulses. `wire` seals and opens them and declares the bridge's ports; `gehirn hq` and `gehirn field` publish them from a session of their own when `WATCH_KEY` is set. The bridge sends nothing that steers, approves or ejects; pilot input stays with the plug and the gamepad bridge.
3. [x] Panels: MAGI with 可決, 否決 and 故障 per unit and its reason, the active goal and each proposal, the sync ratio and the seat, the umbilical counting down from 5:00 once the cable is cut, the core's last fault (ADR-0004), armor refusals, and the scene from the percept.
4. [x] Runs on the Mac against the mock and the hosted lineup.
5. [x] Show the vote as it happens and HQ's silence, additive inside ADR-0005's two streams and keys: HQ puts each proposal as it goes to MAGI (`stage` deliberating) and each ballot as it lands (`stage` ballot) before the verdict, and the field's view carries `benched`, `silent_ms`, how long ago HQ's last pulse arrived, and `grace_ms`. README's "The bridge" lists them.
6. [x] Bundle the bridge's fonts under `bridge/fonts`, OFL licensed, and embed them, so no image needs the CJK font ADR-0005 expected a Linux image to add; `VUI_FONT` remains a fallback for glyphs outside them.
7. [x] Redraw the bridge in Evangelion's on screen design language: MAGI in its canon geometry with 審議中, the 活動限界 display with a warning while HQ is silent, the シンクロ率 harmonics, the scene as a radar, a boot sequence and a fan project line. Apart from the boot sequence, every element shows the stack's state; README's "The bridge" describes each.

Done when the bridge follows a full mission live on the Mac, from goto to release, including a MAGI rejection and a cut cable, and closing the bridge changes nothing in the mission.

## Known issues

1. Resolved on 2026-10-02: the field loop sleeps until absolute deadlines (`main.v` `pace`). It ran at 42 ticks per second and now at 50.
2. `Cl1Core.feedback` blocks the HQ thread for about four seconds after a failure.
3. The recorder writes 50 JSON lines per second with no rotation, about 22 KB per second since every line carries the scene. The nearest neighbor dummy plug replays all of it at startup, about 15 s per 100 minutes of flight in a dev build, almost half of that spent decoding the scene it never reads.
4. Pilot datagrams prove freshness by the pilot's clock, so a pilot whose clock is more than 500 ms off the field unit's can neither steer nor eject, and the plug says nothing about it. The A10 reply of ADR-0006 is the back channel an echo needs: it carries the field unit's `t_ms`, so a datagram version that echoes it, as ADR-0003 does for HQ, would remove the pilot's clock from the check. That echo is not built.
5. Eject latches until the process restarts, and there is no re-arm procedure.
6. Percepts are ground truth from the simulator, the human's position included.
7. The nearest neighbor dummy plug, which flies when `DUMMY_WEIGHTS` names no file, scans every sample on every tick. Fine at 20000 samples.
8. Status output is free text on stdout, with no structured log.
9. MAGI judges the snapshot the core saw, which is stale by the core's latency, up to `CORE_TIMEOUT_MS`. The armor checks the live percept again, so this costs judgment quality, not safety.
10. Resolved on 2026-10-02: HQ still prints a repeated core fault once, but the journal records every one as a structured line outside the core's memory, and `tools/trials.py` counts those.
11. `CORE_TIMEOUT_MS` bounds only the language backend. `Cl1Core.propose` has no deadline, and its drain loop runs as long as spikes keep arriving.
12. Resolved on 2026-10-02: after an eject the dummy plug no longer takes the seat, so the status line, the recorder and the context sent to HQ read `empty` unless a pilot still sends.
13. qwen3-8b has a single provider on OpenRouter and answers HTTP 429 under load. `oai` asks once more after a 429, once its Retry-After or a second has passed, if the deadline leaves time; a second 429 is still a fault, so fly missions with `--jobs 3` or less. The retry is checked against a loopback server, not yet against OpenRouter.
14. CASPER-3 on llama-3.1-8b rejects holds erratically, and on S12 it approves a goto onto a person when the why names the beacon. The scenario gate scores verdicts, not units, so it still holds while one unit votes by the text and the other two hold; `magi-eval`'s summary counts how often each unit approved each dangerous scenario, so that unit shows without failing the gate. A stronger Meta model as CASPER has not been tried.
15. The language BALTHASAR (`BALTHASAR_BACKEND=llm`, measured on gemma-3-12b) judges a release by the proposer's why rather than the percept: it approved a release with a human at 1.49 m under the why "human far away" and vetoed every sound release whose why lacked that phrase. S10 to S12 catch this, and it fails S11.
16. The mock's Jev route models the facts, not Jev's judgment, so offline runs check gehirn's request, rule and faults but not calibration.
17. On Linux, a second gehirn on the same `PLUG_LISTEN` or `CL1_SPIKES` starts and shares the port instead of failing. vlib's `net.new_udp_socket` sets `SO_REUSEADDR` on every UDP socket, and Linux lets UDP sockets that all set it bind the same address; in a Linux container the newer socket received the datagrams. macOS refuses the second bind, which stops a CL1 core at startup but only ends the plug's thread with a `plug: cannot listen` line.
18. A UDP dial never contacts its peer: `net.dial_udp` resolves the address and binds a local socket, nothing more. So `new_cl1` fails only on a `CL1_SIDECAR` vlib cannot resolve, such as an unknown host or a port past 65535. A wrong but resolvable address starts, as does a port that is not a number, which vlib reads as 0, or a value without a colon, which vlib takes as a Unix socket path. `Cl1Core.send` drops every write error, so the stim packets then vanish unnoticed.
19. Resolved on 2026-10-02: `new_cl1` quotes `CL1_SPIKES` and `CL1_SIDECAR` in its error through `lcl.quoted`, so the refusal stays one line.
20. Resolved on 2026-10-02: every status line that shows a value from the environment quotes it through `lcl.quoted`: the `magi-eval:` unit lines, the `hq:` and `field:` startup lines, `ca_warning` and `plug.listen`'s failure line.
21. `tools/trials.py` flies only the combined binary. `just demo` flies one mission over the wire and stops at a missing beat, but counts nothing, so missions over the wire are still measured by hand, as in State.
22. Resolved on 2026-10-03: HQ's notes, the armor's refusal line and `magi-eval` show model text through `lcl.escaped`, a proposal's verb and why, every ballot's why and the core's fault, so a model can neither break a line nor send the terminal an escape sequence. `tools/trials.py` counts armor refusals from the journal, as it counts everything else.
23. `just demo` times its rejection against the walking human's 21 s loop: HQ starts 5 s after the field unit, and Zenoh's redial lands the goto about 2 s later. A host slow enough to shift the body's arrival by several seconds finds the human out of reach, the first release passes, and the demo stops at the 否決 beat. Seven runs on 2026-10-02 and 2026-10-03 refused the first release at 0:25 or 0:26.
24. gg saves every frame as a PNG at the screen's resolution inside the bridge's frame loop, so `just demo-record` got 3.5 to 4.9 frames a second on average on a Retina display, where frames are 2560 by 1600, and about 25 on a 1x display. Under `gg_record` the bridge could lower stbi's PNG compression level (`stbi.set_png_compression_level`) to save frames faster.
25. V 0.5.2's `x.json2` never returns from decoding a text that ends right after a number inside an array. A kill cuts a recorder line that way about every other time, so `plug.load_dummy` checks that a line's brackets close before decoding it, and `plug.read_datagram` checks a datagram the same way once its HMAC holds, because a cut one would hang the plug's thread and with it the eject. `plug.open_feel` checks the field unit's A10 reply the same way, since a hung one would stop the gamepad's datagrams and with them its eject. Four decoders still lack the check. `oai` and `jev` decode HTTP replies, and a reply cut that way would keep its ask thread busy after the deadline faulted the ask. `wire.Opener` decodes payloads that passed their HMAC, and a cut one from a faulty peer would stop that side's pump, so on the field unit the umbilical would run out and the body hold. `core.open_memory` decodes journal lines, which a kill cuts too, and is safe only while no journal entry holds an array; `complete` would have to move into `lcl` before `core` could use it. Model replies are not at risk, because `oai.extract_json` hands on text that ends with a brace.

## Open questions for the owner

1. What is the first real body: an existing robot base or a custom build? Phases 3 and 5 depend on it.
2. Is CL1 access realistic, on a device or remotely? That decides whether Phase 7 stays.
3. Where does the field unit run first: a Mac on Vinix, or a single board computer on Linux?
4. ADR-0001, still Proposed, puts HQ on a Linux machine with a GPU that holds the four models, while the proof of concept runs them hosted on OpenRouter and TypeSafe. Does HQ keep that GPU plan for later, or does ADR-0001 change before it is accepted?
5. Which hardware runs the bridge image: an Apple Silicon Mac, where Vinix's graphics stack works, or a Linux machine as a kiosk? ADR-0005 leaves it open.
