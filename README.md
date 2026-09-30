# gehirn

A control stack for a machine that does not exist yet, cut along the lines Evangelion uses for an Eva. Written in V and named after GEHIRN, the UN laboratory for artificial evolution that developed the Evas before it became NERV.

Today it drives a simulated body with any OpenAI compatible endpoint, Ollama by default. The body is an interface, so hardware replaces the simulator without touching anything above it.

## Quick start

Needs V 0.5.2 or newer (the code uses `json2`) and an endpoint serving the four default models, or your own picks set through the variables below.

```sh
v -prod -o gehirn .
./gehirn
```

HQ proposes a goal, MAGI votes, and the field loop drives the body around a pillar and a walking human to beacon b1, then asks MAGI to release the payload. Without an endpoint the core never gets a goal approved, so the body only moves under a pilot.

To run without models, start the mock endpoint in the background. It answers on the default URL as the core and as all three MAGI.

```sh
python3 tools/mock_endpoint.py &
./gehirn
```

`python3 tools/pilot.py --offset 30 --seconds 20` takes the seat, steers toward the beacon 30 degrees off for 20 seconds, then leaves. `python3 tools/trials.py --runs 10` flies ten missions with `./gehirn` and counts how they end; every run inherits `GEHIRN_URL` and the other variables from the environment.

## The parts

| Canon | Module | Here |
| --- | --- | --- |
| MAGI | `magi` | Three judges on three different model families. Reversible goals pass with two votes, irreversible ones need all three, like special order 582. A unit that errs or answers nonsense votes no. |
| Core | `core` | Proposes the next goal: a language model, or a living culture on a Cortical Labs CL1. Its journal belongs to one pilot and outlives any backend. |
| Entry plug | `plug` | Pilot input over UDP, the sync ratio, and a recorder that logs every tick. |
| Dummy plug | `plug/dummy.v` | The pilot's driving style, cloned from the recorder. It loses the seat when it falls out of sync. |
| Restraint armor | `armor` | The only thing that holds the body: speed, acceleration, geofence, human separation, capabilities, eject. No model inside. |
| Umbilical cable | `umbilical` | The link to HQ. Cut it and the unit runs five minutes on internal power, then holds. |
| LCL | `lcl` | Plain data every layer is immersed in, so any transport can carry it. |
| Eva | `body` | The robot API: sense, actuate, effect, halt. |

## One tick

HQ thinks about once a second on its own thread. The field loop runs at 50 Hz and never waits for it.

```
  HQ, about 1 Hz           field unit, 50 Hz
┌──────────────────┐     ┌───────────────────────┐
│ core proposes    │ <── │ sense                 │
│ a goal           │ ctx │ reflex toward goal    │
│ MAGI votes       │ ──> │ seat: pilot or dummy  │
│                  │ goal│ sync and blend        │
└──────────────────┘     │ armor, body, recorder │
                         └───────────────────────┘
```

MAGI's approval is necessary, never sufficient. An approved goal still has to pass the armor, and a refusal goes back to the core as an outcome it gets to feel.

## Piloting

The plug takes UDP datagrams like this one, at 20 Hz or faster:

```json
{"pilot": "shinji", "u": [0.4, 0.1], "eject": false}
```

`u` is the desired velocity in meters per second. Datagrams from any other pilot are dropped, because a core is paired with one pilot. The seat counts as empty 500 ms after the last datagram. `eject` latches: the body halts and stays halted until the process restarts.

## Sync ratio

Sync is a moving average of how well the seat and the core agree, from the angle between their commands and how close their magnitudes are. It is the arbitration term of shared control, in the sense of Dragan and Srinivasa's policy blending. At or below 30% the core only advises. Above that its share grows with sync up to 80%, so a seated pilot always keeps a fifth of the controls. A core with nowhere to go takes no share.

The dummy plug earns its own ratio. At 30% it is benched until the pilot is back, and the core drives alone under the unmanned speed limit. It imitates style, not intent: commands are stored relative to the approved goal, so without a goal it does nothing, and with one it has no memorized heading to run off with. In canon a sync ratio past 400% dissolves the pilot into LCL. The nearest thing here is a dummy plug good enough that nobody needs to sit down.

## Safety

The armor owns the body, and `main` never gets a handle to it. Every command passes a speed cap (1.0 m/s manned, 0.4 unmanned), an acceleration limit that never limits braking, a geofence, and speed and separation monitoring: slower from 2 m to a human, and inside 0.7 m nothing moves toward them. Nothing pushes into anything solid either; what remains of a command slides along the surface. Irreversible effectors need all three MAGI and no human within 2 m.

That is a soft layer on operating systems without real time guarantees. On hardware the same limits run again on the motor controller behind a physical e-stop, and the controller zeroes its outputs when commands go stale, as the simulator does after 200 ms. The reasoning is in [ADR 0001](docs/adr/0001-where-it-runs.md).

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `GEHIRN_URL` | `http://127.0.0.1:11434/v1/chat/completions` | Endpoint for every model unless overridden |
| `GEHIRN_KEY` | empty | Bearer token for every model unless overridden |
| `CORE_MODEL` | `qwen3:8b` | The core; `CORE_URL` and `CORE_KEY` override the endpoint |
| `MELCHIOR_MODEL` | `gpt-oss:20b` | The scientist, with the same `_URL` and `_KEY` overrides |
| `BALTHASAR_MODEL` | `gemma3:12b` | The mother, same overrides |
| `CASPER_MODEL` | `llama3.1:8b` | The woman, same overrides |
| `MAGI_TIMEOUT_MS` | `10000` | Deadline for one ballot. A unit that misses it votes no |
| `CORE_TIMEOUT_MS` | `10000` | Deadline for one proposal from the core |
| `CORE_BACKEND` | `llm` | `llm` or `cl1` |
| `CL1_SPIKES` | `0.0.0.0:12345` | Where spikes from the CL1 sidecar arrive |
| `CL1_SIDECAR` | `127.0.0.1:12346` | Where stim packets go |
| `PILOT_ID` | `shinji` | The only pilot this core accepts |
| `PLUG_LISTEN` | `0.0.0.0:7777` | UDP address for pilot input |
| `MISSION` | deliver to b1, avoid humans | What HQ is trying to achieve |
| `CORE_JOURNAL` | `core.<pilot>.jsonl` | The soul: append only, one per pilot. It also records every MAGI ballot |
| `PLUG_RECORDER` | `plug.<pilot>.jsonl` | Every tick, and the dummy plug's training set |
| `HQ_PERIOD_MS` | `1500` | Pause between deliberations |
| `MAGI_COOLDOWN_MS` | `10000` | Wait before an irreversible proposal may be put again |
| `UMBILICAL_GRACE_MS` | `45000` | Silence from HQ before the cable counts as cut |
| `INTERNAL_BUDGET_MS` | `300000` | Internal power after the cut, then hold |

The default models are placeholders. What matters is that the three judges come from three different families. In episode 13 all three MAGI shared one personality as their base, so what took Melchior took Balthasar next. Three personas on one model share every blind spot, and a prompt injection that fools one fools all.

## CL1 backend

`CORE_BACKEND=cl1` swaps the language core for a culture. `sidecar/cl1_sidecar.py` runs on the CL1, because the CL API is a Python SDK. It streams spikes in the format of Cortical Labs' UDP receiver example and turns stim packets from `core/cl1.v` into stimulation. The beacon's direction is place coded as stimulation rates on four sensory channels, and the imbalance between four motor channels becomes a short hop. Feedback follows DishBrain: a predictable burst after success, seconds of unpredictable stimulation after failure, because a culture takes no reward scalar and learns to keep its input predictable. Channel maps, rates and amplitudes are starting points, not tuned values; check the stim call against the CL-06 notebook for the SDK on your device.

## Next

LCL on Zenoh through zenoh-c and V's C interop, which brings ROS 2 in through rmw_zenoh and reaches the motor controller through zenoh-pico. A MuJoCo body instead of the planar simulator. A gamepad bridge for the plug. The A10 back channel, with contact and strain flowing back to the pilot as haptics. A trained policy behind the dummy plug's methods, corrected by the pilot DAgger style instead of cloned once. A core fine tuned on its own journal. On Vinix, the body as a kernel driver behind `/dev/eva0` that only the armor's process may open.
