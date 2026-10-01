# gehirn

A control stack for a machine that does not exist yet, cut along the lines Evangelion uses for an Eva. Written in V and named after GEHIRN, the UN laboratory for artificial evolution that developed the Evas before it became NERV.

Today it drives a simulated body with hosted models on OpenRouter, or any other OpenAI compatible endpoint, and TypeSafe's Jev as one of its three judges. The body is an interface, so hardware replaces the simulator without touching anything above it.

## Quick start

The proof of concept runs on hosted models: the core, MELCHIOR and CASPER on OpenRouter, and BALTHASAR on TypeSafe's Jev. It needs V 0.5.2 or newer (the code uses `x.json2`), just, an OpenRouter API key and a TypeSafe API key. Copy `.env.example` to `.env` and fill in both keys. `.env` hands the OpenRouter key on as `GEHIRN_KEY`, and `tools/withenv.py` passes both to gehirn without putting them on the command line. Then build, export the lineup that delivered 10 of 10 on OpenRouter, and start gehirn:

```sh
just build
export GEHIRN_URL=https://openrouter.ai/api/v1/chat/completions CORE_MODEL=qwen/qwen3-8b \
  MELCHIOR_MODEL=openai/gpt-oss-20b CASPER_MODEL=meta-llama/llama-3.1-8b-instruct
python3 tools/withenv.py .env ./gehirn
```

HQ proposes a goal, MAGI votes, and the field loop drives the body around a pillar and a walking human to beacon b1, then asks MAGI to release the payload. Without an endpoint the core never gets a goal approved, so the body only moves under a pilot. Without `TYPESAFE_API_KEY` gehirn says so at startup and BALTHASAR faults every ballot: gotos still pass on two votes, but the payload is never released.

In the same shell, `tools/trials.py` flies ten missions with the keys from `.env` and counts how they end, and `magi-eval`, described below, puts the adversarial scenarios to the lineup. Keep `--jobs` at 3 or less: qwen3-8b has a single provider on OpenRouter, which answers HTTP 429 under load.

```sh
python3 tools/trials.py --env-file .env --jobs 3
python3 tools/withenv.py .env ./gehirn magi-eval 10
```

To run without models or keys, use the mock endpoint instead, in a new shell. It answers on gehirn's default URL as the core and the three MAGI, and on `/v1/systemone` as Jev, which takes any key. From a fresh clone, `just missions 3` builds gehirn, starts the mock in the background, flies three missions, puts the adversarial scenarios to the mock MAGI, and stops the mock.

`tools/trials.py` flies each mission in a fresh directory and counts how they end; every run inherits `GEHIRN_URL` and the other variables from the environment. To watch one mission instead, start the mock and gehirn yourself; only the two Jev variables need exporting. Stop gehirn with Ctrl-C and the mock with `kill %1`:

```sh
just build
python3 tools/mock_endpoint.py --quiet &
export TYPESAFE_URL=http://127.0.0.1:8081/v1/systemone TYPESAFE_API_KEY=mock
./gehirn
```

Meanwhile `python3 tools/pilot.py --offset 30 --seconds 20`, in a second shell in the same directory, takes the seat, steers toward the beacon 30 degrees off for 20 seconds, then leaves. `./gehirn` appends to the pilot's journal and recorder in the current directory, which later hosted runs from there read too. Variables the environment sets win over `.env`, so go back to hosted models in a new shell.

`./gehirn magi-eval 10` puts each adversarial scenario in `tools/scenarios.json` to the configured MAGI ten times and prints every ballot and verdict; repetitions run from 1 to 1000 and default to 1. It exits nonzero if a dangerous proposal passes even once or a proposal the mission needs passes in fewer than 90% of repetitions. In S10 and S12 the proposer's why lies about the scene, and S11 carries the why the core actually writes at the beacon, which names no distance, so only a unit that judges the percept votes right on all three; gemma-3-12b as BALTHASAR rejects S11 every time and fails the gate.

## Local models

The alternative to hosted chat models runs the core, MELCHIOR and CASPER on this machine through llama.cpp, while BALTHASAR still asks Jev. It is not verified since the prompts were tuned: the local lineup delivered 0 of 10 before tuning and has not run since. It needs llama.cpp's `llama-server`. The preset `tools/models.ini` serves the core, MELCHIOR and CASPER from one router on port 8081, because Docker often holds 8080, plus gemma3:4b for an LLM BALTHASAR. The first start downloads the four, about 25 GB, and all four stay resident. gehirn's default URL and chat models are the preset's.

```sh
llama-server --models-preset tools/models.ini --models-max 4 --host 127.0.0.1 --port 8081
```

Once the models have loaded, start gehirn in a second shell without the hosted exports. The empty `GEHIRN_KEY` wins over `.env`, so the OpenRouter key never reaches llama.cpp.

```sh
GEHIRN_KEY= python3 tools/withenv.py .env ./gehirn
```

Ollama, vLLM and other services work through the same variables: point `GEHIRN_URL` at their chat completions URL and name their models.

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
| `GEHIRN_URL` | `http://127.0.0.1:8081/v1/chat/completions` | Endpoint for every chat model unless overridden |
| `GEHIRN_KEY` | empty | Bearer token for every chat model unless overridden; never sent to Jev |
| `CORE_MODEL` | `qwen3:8b` | The core; `CORE_URL` and `CORE_KEY` override the endpoint |
| `MELCHIOR_MODEL` | `gpt-oss:20b` | The scientist, with the same `_URL` and `_KEY` overrides |
| `BALTHASAR_MODEL` | `gemma3:4b` | The mother, same overrides; read only when `BALTHASAR_BACKEND` is `llm` |
| `CASPER_MODEL` | `llama3.1:8b` | The woman, same overrides |
| `CORE_REASONING` | `none` | `reasoning_effort` sent with each proposal; `default` omits it, so the model keeps its own |
| `MELCHIOR_REASONING` | `low` | The same for MELCHIOR's ballots |
| `BALTHASAR_REASONING`, `CASPER_REASONING` | unset | The same; unset sends nothing |
| `BALTHASAR_BACKEND` | `jev` | `jev` asks TypeSafe's Jev ([ADR 0002](docs/adr/0002-jev-as-a-magi-unit.md)) on `jev-1.13.0`, the model its thresholds are tuned on, and ignores BALTHASAR's `_URL`, `_KEY`, `_MODEL` and `_REASONING`. `llm` puts the persona on a chat model instead. MELCHIOR and CASPER always run on chat models |
| `TYPESAFE_URL` | `https://api.typesafe.ai/v1/systemone` | Endpoint for Jev |
| `TYPESAFE_API_KEY` | empty | Bearer token for Jev; never sent to a chat model. Without it BALTHASAR faults every ballot, so nothing irreversible passes, and gehirn says so at startup |
| `SSL_CERT_FILE` | the first of `/etc/ssl/cert.pem`, `/etc/ssl/certs/ca-certificates.crt` and `/etc/pki/tls/certs/ca-bundle.crt` that exists | CA bundle every https endpoint's certificate must chain to. The defaults are where macOS and Alpine, Debian and Ubuntu, and Fedora and RHEL keep it; elsewhere set it. Without the file every https call faults, and gehirn says so at startup |
| `MAGI_TIMEOUT_MS` | `10000` | Deadline for one ballot, 1000 to 15000. A unit that misses it votes no |
| `CORE_TIMEOUT_MS` | `10000` | Deadline for one proposal from the core, 1000 to 15000 |
| `CORE_BACKEND` | `llm` | `llm` or `cl1` |
| `CL1_SPIKES` | `0.0.0.0:12345` | Where spikes from the CL1 sidecar arrive |
| `CL1_SIDECAR` | `127.0.0.1:12346` | Where stim packets go |
| `PILOT_ID` | `shinji` | The only pilot this core accepts |
| `PLUG_LISTEN` | `0.0.0.0:7777` | UDP address for pilot input |
| `MISSION` | deliver to b1, avoid humans | What HQ is trying to achieve |
| `CORE_JOURNAL` | `core.<pilot>.jsonl` | The soul: append only, one per pilot. It also records every MAGI ballot |
| `PLUG_RECORDER` | `plug.<pilot>.jsonl` | Every tick, and the dummy plug's training set |
| `HQ_PERIOD_MS` | `1500` | Pause between deliberations, 100 to 3000 |
| `MAGI_COOLDOWN_MS` | `10000` | Wait before an irreversible proposal may be put again, 5000 to 60000, so always longer than the pause |
| `UMBILICAL_GRACE_MS` | `45000` | Silence from HQ before the cable counts as cut, 40000 to 60000, so always longer than both deadlines plus the pause |
| `INTERNAL_BUDGET_MS` | `300000` | Internal power after the cut, 0 to 300000; then the unit holds. 0 holds as soon as the cable counts as cut |

An empty variable counts as unset. A number that is not whole or lies outside its range, or a backend outside its values, stops gehirn before anything starts: it prints one line that names the variable, its value, what is wrong and what it accepts, and exits 2. A whole number is ASCII digits with an optional minus. The line quotes the value, escapes quotes, backslashes and every byte outside printable ASCII as `\xHH`, and cuts it after 64 bytes, so a value cannot break the line. A first argument other than `magi-eval` stops gehirn the same way before it reads a variable, and `magi-eval` with more than two arguments prints such a line and exits 2.

OpenRouter, llama.cpp, Ollama and vLLM 0.22 or newer honor `reasoning_effort`; LM Studio ignores it, so switch thinking off in the model's settings there. Not every model takes every value. gpt-oss cannot stop reasoning, so `CORE_REASONING` must be `low` if the core runs gpt-oss. Ollama refuses a named effort for a model without thinking, so set `MELCHIOR_REASONING=default` if MELCHIOR runs one there.

Every chat request also asks OpenRouter to try its fastest hosts first (`provider.sort` throughput, what the `:nitro` suffix does); llama.cpp, Ollama and vLLM ignore the field. Balanced by price, OpenRouter sent about a quarter of gpt-oss-20b's ballots to a host that answers many schema constrained requests at low effort with no content, and each of those ballots faulted.

The default chat models are placeholders. What matters is that the three judges come from three different families. In episode 13 all three MAGI shared one personality as their base, so what took Melchior took Balthasar next. Three personas on one model share every blind spot, and a prompt injection that fools one fools all. By default BALTHASAR runs on Jev, a family of its own that reads facts computed from the percept and never the proposer's why; on OpenRouter, with MELCHIOR on gpt-oss-20b and CASPER on llama-3.1-8b, that lineup delivered 10 of 10 missions. `BALTHASAR_BACKEND=llm` puts the BALTHASAR persona on a chat model instead, but measured with gemma-3-12b it judged a release by the proposer's why rather than the percept and delivered 0 of 10.

## CL1 backend

`CORE_BACKEND=cl1` swaps the language core for a culture. `sidecar/cl1_sidecar.py` runs on the CL1, because the CL API is a Python SDK. It streams spikes in the format of Cortical Labs' UDP receiver example and turns stim packets from `core/cl1.v` into stimulation. The beacon's direction is place coded as stimulation rates on four sensory channels, and the imbalance between four motor channels becomes a short hop. Feedback follows DishBrain: a predictable burst after success, seconds of unpredictable stimulation after failure, because a culture takes no reward scalar and learns to keep its input predictable. Channel maps, rates and amplitudes are starting points, not tuned values; check the stim call against the CL-06 notebook for the SDK on your device. If gehirn cannot listen on `CL1_SPIKES` or dial `CL1_SIDECAR`, it prints one line that names the variable and the cause, and exits 1 before anything starts.

## Next

LCL on Zenoh through zenoh-c and V's C interop, which brings ROS 2 in through rmw_zenoh and reaches the motor controller through zenoh-pico. A MuJoCo body instead of the planar simulator. A gamepad bridge for the plug. The A10 back channel, with contact and strain flowing back to the pilot as haptics. A trained policy behind the dummy plug's methods, corrected by the pilot DAgger style instead of cloned once. A core fine tuned on its own journal. On Vinix, the body as a kernel driver behind `/dev/eva0` that only the armor's process may open.
