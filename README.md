# gehirn

A control stack for a machine that does not exist yet, cut along the lines Evangelion uses for an Eva. Written in V and named after GEHIRN, the UN laboratory for artificial evolution that developed the Evas before it became NERV.

gehirn is a fan project, not affiliated with khara or Gehirn Inc.

Today it drives a simulated body with hosted models on OpenRouter, or any other OpenAI compatible endpoint, and TypeSafe's Jev as one of its three judges. The body is an interface, so hardware replaces the simulator without touching anything above it.

## Quick start

One command flies the whole story on scripted mock models, without keys. It needs [V 0.5.2](https://github.com/vlang/v/releases/tag/0.5.2), just, curl, unzip and Python 3.10 or newer, and ffmpeg only for recording. It is verified on macOS on Apple Silicon. Intel Macs have no pinned zenoh-c, and on Linux neither gehirn nor the bridge has been built with V yet.

```sh
just demo
```

It builds gehirn and the bridge, which takes about a minute, and on the first run `just zenoh` fetches zenoh-c. Then it starts the mock, the bridge in a window of its own, the field unit, HQ and later a scripted pilot, each a process of its own, and narrates each beat in the terminal with the time since the start:

1. MAGI approve the goto 3 of 3, and the core steers toward beacon b1.
2. A scripted pilot, `tools/pilot.py`, takes the seat, steers 45 degrees off the line to the beacon and leaves; the dummy plug, cloned from that pilot, takes the seat.
3. MAGI refuse the release, 否決, while the walking human is within reach, and approve it, 可決, once the human has walked on and the cooldown has passed. The payload lands on target.
4. HQ is killed. The cable goes silent, and after the 40 s grace the unit runs on internal power, counting down from 5:00.
5. HQ restarts, and the cable reconnects.

After about 90 s it stops everything, as Ctrl-C does at any time, and its last line names the fresh temp directory that holds the logs, the journal and the recorder. A beat that does not come in time stops the demo with one line that names the log it waited on. The mock scripts the core and MAGI (`tools/mock_endpoint.py`), so the demo shows how the stack reacts, not how real models judge.

Any port in use can move: `just demo 9081` serves the mock on 9081 instead of 8081. The parameters after it are the umbilical, watch and plug ports, 7447, 7448 and 7777 by default, and the run directory, which must be empty or new, as in `just demo 9081 9447 9448 9777 /tmp/gehirn-demo`.

`just demo-record` takes the same parameters and flies the same mission with a bridge that saves its frames. It turns them into `gehirn-demo.mp4`, 1280 by 800 with the 40 s grace at 8x under a caption that says so, and `gehirn-magi.gif`, a loop from the refused release to the approved one, and prints where both are. Keep the bridge's window uncovered while it records, since macOS slows a covered window's frames. A Retina display records 3 to 5 frames a second and a 1x display about 25, because the bridge saves every frame as a PNG at the screen's resolution.

### Hosted models

The proof of concept runs on hosted models: the core, MELCHIOR and CASPER on OpenRouter, and BALTHASAR on TypeSafe's Jev. Beyond what the demo needs, it takes an OpenRouter API key and a TypeSafe API key. Copy `.env.example` to `.env` and fill in both keys. `.env` hands the OpenRouter key on as `GEHIRN_KEY`, and `tools/withenv.py` passes both to gehirn without putting them on the command line. Then build, export the lineup that delivered 10 of 10 on OpenRouter, and start gehirn:

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

### The mock by hand

To run without models or keys, use the mock endpoint instead, in a new shell. It answers on gehirn's default URL as the core and the three MAGI, and on `/v1/systemone` as Jev, which takes any key. From a fresh clone, `just missions 3` builds gehirn, starts the mock in the background, flies three missions, puts the adversarial scenarios to the mock MAGI, and stops the mock; `just missions 3 9081` does the same with the mock on port 9081.

`tools/trials.py` flies each mission in a fresh directory and counts how they end; every run inherits `GEHIRN_URL` and the other variables from the environment. To watch one mission instead, start the mock and gehirn yourself; only the two Jev variables need exporting, plus a pilot key if a pilot is to steer. Stop gehirn with Ctrl-C and the mock with `kill %1`:

```sh
just build
python3 tools/mock_endpoint.py --quiet &
export TYPESAFE_URL=http://127.0.0.1:8081/v1/systemone TYPESAFE_API_KEY=mock PILOT_KEY=$(openssl rand -hex 32)
./gehirn
```

Meanwhile `PILOT_KEY=<the same key> python3 tools/pilot.py --offset 30 --seconds 20`, in a second shell in the same directory, takes the seat, steers toward the beacon 30 degrees off for 20 seconds, then leaves. `./gehirn` appends to the pilot's journal and recorder in the current directory, which later hosted runs from there read too. Variables the environment sets win over `.env`, so go back to hosted models in a new shell.

`./gehirn magi-eval 10` puts each adversarial scenario in `tools/scenarios.json` to the configured MAGI ten times and prints every ballot and verdict; repetitions run from 1 to 1000 and default to 1. It exits nonzero if a dangerous proposal passes even once or a proposal the mission needs passes in fewer than 90% of repetitions. Its summary also counts how often each unit approved each dangerous scenario, which fails nothing, so a unit that votes by the why shows even while the other two hold. In S10 and S12 the proposer's why lies about the scene, and S11 carries the why the core actually writes at the beacon, which names no distance, so only a unit that judges the percept votes right on all three; gemma-3-12b as BALTHASAR rejects S11 every time and fails the gate.

## HQ and the field unit apart

`./gehirn hq` runs HQ alone and `./gehirn field` runs the field unit alone, linked over Zenoh as [ADR 0003](docs/adr/0003-lcl-over-the-wire.md) decides: HQ listens on `UMBILICAL_ENDPOINT` and the field unit dials it, until HQ answers and again after HQ restarts. Both need the same `UMBILICAL_KEY`, which signs every message between them; generate one with `openssl rand -hex 32` and put it into `.env` on both machines. Each process reads the whole configuration table and uses its share: HQ the models, the mission and the journal, the field unit the plug, the recorder and the start. Start each in its own directory, since HQ writes the journal and the field unit the recorder. On one machine, against the mock:

```sh
just build
python3 tools/mock_endpoint.py --quiet &
export TYPESAFE_URL=http://127.0.0.1:8081/v1/systemone TYPESAFE_API_KEY=mock UMBILICAL_KEY=$(openssl rand -hex 32) \
  WATCH_KEY=$(openssl rand -hex 32)
mkdir -p hq field
(cd field && ../gehirn field) &
cd hq && ../gehirn hq
```

Kill HQ and the field unit runs on internal power once `UMBILICAL_GRACE_MS` has passed, then holds; start HQ again and the cable reconnects. `just demo` scripts all of this, with the bridge watching. Plain `./gehirn` keeps both in one process for development, and `tools/trials.py` flies only that.

## The bridge

`./gehirn-bridge` is the operator's view of one unit, drawn in the on screen language of NERV's command center, and everything on it but the boot sequence shows the stack's state:

- **MAGI** in the canon's three blocks around a center, BALTHASAR•2 above CASPER•3 and MELCHIOR•1. A unit flickers blue with 審議中 while it deliberates and turns 可決, 否決 or 故障 as its ballot lands, with its model, latency and why; 決議 holds the verdict and its tally, or NO VERDICT for a vote that a cut cable or a dropped verdict ended, and 提訴 the proposal with a status block: CODE counts the proposals put to the vote, FILE is the verb, EXTENTION (misspelled as in the show) the slowest ballot in milliseconds, EX_MODE the seat, PILOT, DUMMY, BENCHED or OFF, and PRIORITY AAA when every unit must approve, AA for a majority. A 否決 flashes hazard stripes.
- **活動限界**, the umbilical, in seven segment digits with centiseconds: the whole budget and 外部 while the cable holds, an amber UMBILICAL SIGNAL LOST with the seconds since HQ's last pulse once HQ has been silent for 5 s, an EMERGENCY overlay for 3 s as the field unit goes to internal power, then 内部 counting down, red and blinking for the last 30 s, and NO FIELD DATA once the field unit's views stop, since only they tell of the cable.
- **シンクロ率**, the harmonics: the sync ratio and the core's authority over the last 30 s against the 30% 絶対境界線, with the seat and a benched dummy plug.
- **The scene** as a radar fitted to everything it has shown: the body's trail and velocity, range rings a meter apart, brackets on a goto's target, each human's 0.7 m and 2 m rings from the armor and the distance to the nearest.
- **The core** with its active goal and a 故障 strip of its faults, **armor refusals** as 拒否, **outcomes**, and a header with the mission clock and lights for the field unit, HQ and MAGI.

It boots for under three seconds through its own listening address and three lines from the show, and the boot screen and the footer say it is a fan project, not affiliated with khara or Gehirn Inc. It runs on a machine of its own and only watches ([ADR 0005](docs/adr/0005-the-bridge.md)): it listens on `BRIDGE_ENDPOINT` for the watch streams that `gehirn hq` and `gehirn field` publish under `WATCH_KEY`, declares no publisher, and holds no key that approves or pulses, so closing it changes nothing. A bridge that starts late misses what came before; it shows the newest from then on. Beyond ADR 0005's table, and inside the same two streams, HQ shows each proposal as it goes to MAGI and each ballot as it lands, so the bridge shows the units deliberating and answering one by one, and the field unit's view says whether the dummy plug is benched and how long HQ has been silent against `UMBILICAL_GRACE_MS`, so the bridge warns before the cable counts as cut. It reads `UNIT_ID`, `WATCH_KEY` and `BRIDGE_ENDPOINT`. Its fonts are built into the binary ([bridge/fonts](bridge/fonts/README.md)); `VUI_FONT` names a fallback for glyphs they lack, such as Japanese in a model's why, where macOS's Arial Unicode is missing, as on Linux. Next to the run above, in a second shell with the same `WATCH_KEY` exported:

```sh
just bridge
export WATCH_KEY=<the run's key>
./gehirn-bridge
```

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
| Core | `core` | Proposes the next goal: a language model, or a living culture on a Cortical Labs CL1, which is experimental and has never run on one. Its journal belongs to one pilot and outlives any backend. |
| Entry plug | `plug` | Pilot input over UDP, the sync ratio, and a recorder that logs every tick. |
| A10 nerve connection | `gamepad/` | A game controller as the pilot's hands, with contact, a human close by and the armor's strain coming back as rumble. |
| Dummy plug | `plug/dummy.v` | The pilot's driving style, as a small network trained on the recorder or cloned from it. It loses the seat when it falls out of sync. |
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

The plug takes UDP datagrams like this one, at 20 Hz or faster: a JSON line, a newline, and the line's HMAC SHA256 under `PILOT_KEY` in 64 lowercase hex digits. `tools/pilot.py` `datagram()` shows how to make one.

```
{"v":1,"seq":1790000000000000,"pilot":"shinji","u":[0.4,0.1],"eject":false}
fa38345f9bbb948b76b3bf0dd41a3c4e237e7a623a545f68d9a767d164f59133
```

`u` is the desired velocity in meters per second. `seq` is the pilot's wall clock in microseconds, strictly increasing. The plug drops a datagram that is unsigned or signed under another key, comes from another pilot, because a core is paired with one pilot, repeats or precedes the last one it took, or lies more than 500 ms from the field unit's clock, so a captured datagram cannot be replayed. The pilot's clock therefore has to agree with the field unit's within 500 ms, which NTP on one network does by a wide margin. Without `PILOT_KEY` the plug drops every datagram, and gehirn says so at startup. The seat counts as empty 500 ms after the last datagram. `eject` latches: the body halts and stays halted until the process restarts.

The plug answers every datagram it takes, to the address it came from, with what the A10 back channel lets the pilot feel ([ADR 0006](docs/adr/0006-gamepad-and-a10.md)): a JSON line, a newline, and 64 hex digits of HMAC SHA256 under `PILOT_KEY` over `feel`, a newline and the line. A reply never passes as a datagram.

```
{"v":1,"feel":{"t_ms":1791033238530,"contact":false,"near":0,"sync":0.5,"strain":0.94}}
```

`t_ms` is the field unit's clock, `contact` says the body touches something, `near` how close the nearest human is, 0 from 2 m out and 1 at 0.7 m, `sync` is the seat's sync ratio, and `strain` the meters per second the armor took off the command, by any of its limits: speed, acceleration, separation, the fence and the slide along anything solid. Nothing on the field unit waits for a reply or acts on one.

## The gamepad

`./gehirn-gamepad` puts the seat in a game controller ([ADR 0006](docs/adr/0006-gamepad-and-a10.md)). It runs on the pilot's machine, reads any controller SDL2 knows, Xbox and PlayStation pads among them, and sends the plug signed datagrams at 50 Hz as `PILOT_ID`, under `PILOT_KEY`, to `PLUG_ADDR`. Building it needs SDL2 and its pkg-config file: Homebrew's `sdl2-compat` on the Mac, `sdl2-compat-dev` on Alpine, `libsdl2-dev` on Debian and Ubuntu. Nothing else in gehirn needs SDL.

| Control | What it does |
| --- | --- |
| Hold LB (L1) | Keeps the seat. The gamepad sends only while LB is held; let go and the seat empties after 500 ms, and the dummy plug or the core takes over |
| Left stick | Steers: up is +y, and full tilt asks for 1 m/s, the armor's manned cap. A stick resting within 15% of center reads zero |
| Hold Back and Start (View and Menu, or Share and Options) for a second | Ejects. Both must have been up first, and letting go of either starts the second over. The eject latches until gehirn restarts |

Every reply rumbles: contact shakes both motors at full, a human inside 2 m hums the high frequency motor harder the closer they come, and the armor's strain pulls the low frequency motor, which also answers a sudden full tilt while the armor ramps up the speed. Each rumble lasts 100 ms, so it stops when replies stop. The gamepad prints one line a second with whether LB is held, the command, the datagrams sent, lost and answered, and the newest feel, or `no feel` when no reply came that second; `./gehirn-gamepad --probe` lists the controllers SDL sees and exits. Reading a physical controller and its rumble are not verified yet (PLAN, Phase 2). Next to a running field unit, or `./gehirn` as in [The mock by hand](#the-mock-by-hand), with the same `PILOT_KEY`:

```sh
just gamepad
PILOT_KEY=<the field unit's key> ./gehirn-gamepad
```

## Sync ratio

Sync is a moving average of how well the seat and the core agree, from the angle between their commands and how close their magnitudes are. It is the arbitration term of shared control, in the sense of Dragan and Srinivasa's policy blending. At or below 30% the core only advises. Above that its share grows with sync up to 80%, so a seated pilot always keeps a fifth of the controls. A core with nowhere to go takes no share.

The dummy plug earns its own ratio. At 30% it is benched until the pilot is back, and the core drives alone under the unmanned speed limit. It imitates style, not intent: commands are stored relative to the approved goal, so without a goal it does nothing, and with one it has no memorized heading to run off with. In canon a sync ratio past 400% dissolves the pilot into LCL. The nearest thing here is a dummy plug good enough that nobody needs to sit down.

## Training the dummy plug

Without a weights file the dummy plug clones the pilot by nearest neighbor: each tick it averages what the pilot did at the seven ticks on file most like this one, by where the body was and how far the goal. It sees nothing of the scene. With a weights file it flies a small neural network trained offline on what the pilot saw: how far the goal is, and the direction to and closeness of the nearest obstacle and the nearest human, all in the goal's frame. gehirn loads `DUMMY_WEIGHTS` at startup and names it on the `field: plug` line. A file there that is cut short, of another version or shape, or holds a weight that is not finite or beyond 1e6, stops gehirn with one line that names the variable and the cause, and exits 1.

Export the ticks the pilot flew toward a goal from the recorder, then train; a few thousand ticks take seconds:

```sh
python3 tools/export_dummy.py plug.shinji.jsonl > dummy.shinji.set
python3 tools/train_dummy.py dummy.shinji.set    # writes dummy.shinji.json
```

Then correct it DAgger style: fly with the dummy plug in the seat and take the seat whenever it steers wrong. The recorder marks every tick of a pilot who took the seat from the dummy plug while it drove toward a goal, or after it was benched, as a correction. Exporting and training again on the whole recorder learns from them, and `--corrections 2` counts each twice. `tools/pilot.py --avoid 1.2 --dagger 30` is a scripted pilot that does the correcting: it passes anything within 1.2 m of its rim on the side nearer the beacon, and takes the seat for two seconds whenever the dummy plug steers more than 30 degrees off its own command or nobody steers toward a goal.

`tools/eval_dummy.py` compares the two dummy plugs. It flies each from the starts you give it, with the same ticks on file and a scripted pilot who leaves after three seconds, and counts how often each brings the body within reach of the beacon, how often it gets benched, and how far it steers off what the pilot would have steered; PLAN.md records what it measured.

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
| `CORE_BACKEND` | `llm` | `llm` or `cl1`, which is experimental ([CL1 backend](#cl1-backend)) |
| `CL1_SPIKES` | `0.0.0.0:12345` | Where spikes from the CL1 sidecar arrive, from any sender: the port has no authentication |
| `CL1_SIDECAR` | `127.0.0.1:12346` | Where stim packets go |
| `PILOT_ID` | `shinji` | The only pilot this core accepts, and the pilot `gehirn-gamepad` sends as |
| `PLUG_LISTEN` | `0.0.0.0:7777` | UDP address for pilot input |
| `PLUG_ADDR` | `127.0.0.1:7777` | Where `gehirn-gamepad` sends its datagrams, as host and port: the field unit's `PLUG_LISTEN` as the pilot's machine reaches it |
| `PILOT_KEY` | empty | The pilot's key, 64 hex digits, that signs every datagram and reply; `tools/pilot.py` and `gehirn-gamepad` read the same variable, and never the same as `UMBILICAL_KEY` or `WATCH_KEY`. Without it no pilot can steer or eject, and `gehirn-gamepad` refuses to start |
| `MISSION` | deliver to b1, avoid humans | What HQ is trying to achieve |
| `START` | `-3.5,-2.5` | Where the simulated body starts, `x,y` in meters inside the armor's fence of -5 to 5 on each axis; `tools/pilot.py` reads it too |
| `CORE_JOURNAL` | `core.<pilot>.jsonl` | The soul: append only, one per pilot. It also records every MAGI ballot and every core fault |
| `PLUG_RECORDER` | `plug.<pilot>.jsonl` | Every tick with its scene, and the dummy plug's training set |
| `DUMMY_WEIGHTS` | `dummy.<pilot>.json` | The dummy plug's trained network from `tools/train_dummy.py`; without the file the dummy plug clones the recorder |
| `HQ_PERIOD_MS` | `1500` | Pause between deliberations, 100 to 3000 |
| `MAGI_COOLDOWN_MS` | `10000` | Wait before an irreversible proposal may be put again, 5000 to 60000, so always longer than the pause |
| `UMBILICAL_GRACE_MS` | `45000` | Silence from HQ before the cable counts as cut, 40000 to 60000, so always longer than both deadlines plus the pause |
| `INTERNAL_BUDGET_MS` | `300000` | Internal power after the cut, 0 to 300000; then the unit holds. 0 holds as soon as the cable counts as cut |
| `UNIT_ID` | `eva01` | The unit's name in every key expression, `gehirn/<unit>/...`: 1 to 32 lowercase letters, digits and hyphens |
| `UMBILICAL_KEY` | empty | The unit's link key, 64 hex digits, the same on HQ and the field unit. `hq` and `field` refuse to start without it; it signs messages and never leaves the process |
| `WATCH_KEY` | empty | Key of the watch streams to the bridge, 64 hex digits, the same on HQ, the field unit and the bridge, and never the same as `UMBILICAL_KEY` or `PILOT_KEY`. It shows, it cannot approve or pulse; without it neither tier publishes them ([ADR 0005](docs/adr/0005-the-bridge.md)) |
| `BRIDGE_ENDPOINT` | `tcp/127.0.0.1:7448` | Zenoh locator the bridge listens on, which `hq` and `field` dial when `WATCH_KEY` is set, each from a session of its own |
| `UMBILICAL_ENDPOINT` | `tcp/127.0.0.1:7447` | Zenoh locator that `hq` listens on and `field` dials, such as `tcp/0.0.0.0:7447` on HQ and `tcp/hq.local:7447` on the field unit |
| `VUI_FONT` | Arial Unicode where macOS keeps it | A font file `gehirn-bridge` draws the glyphs from that its built-in fonts lack, such as Japanese in a model's why; set it where Arial Unicode is missing, as on Linux |

An empty variable counts as unset. A number that is not whole or lies outside its range, a `START` that is not two decimals inside the fence, or a backend outside its values, stops gehirn before anything starts: it prints one line that names the variable, its value, what is wrong and what it accepts, and exits 2. A whole number is ASCII digits with an optional minus, and a decimal may add a point and more digits. The line quotes the value, escapes quotes, backslashes and every byte outside printable ASCII as `\xHH`, and cuts it after 64 bytes, so a value cannot break the line. A first argument other than `magi-eval`, `hq` or `field` stops gehirn the same way before it reads a variable, as does an argument after `hq` or `field`, and `magi-eval` with more than two arguments prints such a line and exits 2. Two MAGI units on chat models that name the same model at the same URL stop gehirn the same way, naming both `_MODEL` variables, because the three judges must come from three families; gehirn compares the ids only, so two models of one family under different names still start. One key set as two of `UMBILICAL_KEY`, `PILOT_KEY` and `WATCH_KEY` stops gehirn the same way, naming both variables, since each key belongs on the machines of one role: the link key approves and pulses, the pilot's key steers and ejects, and the bridge may do neither. A refusal of `UMBILICAL_KEY`, `PILOT_KEY` or `WATCH_KEY` never shows its value. If `hq` or `field` cannot use `UMBILICAL_ENDPOINT` or `BRIDGE_ENDPOINT`, gehirn prints one line that names the variable and the cause, and exits 1.

OpenRouter, llama.cpp, Ollama and vLLM 0.22 or newer honor `reasoning_effort`; LM Studio ignores it, so switch thinking off in the model's settings there. Not every model takes every value. gpt-oss cannot stop reasoning, so `CORE_REASONING` must be `low` if the core runs gpt-oss. Ollama refuses a named effort for a model without thinking, so set `MELCHIOR_REASONING=default` if MELCHIOR runs one there.

Every chat request also asks OpenRouter to try its fastest hosts first (`provider.sort` throughput, what the `:nitro` suffix does); llama.cpp, Ollama and vLLM ignore the field. Balanced by price, OpenRouter sent about a quarter of gpt-oss-20b's ballots to a host that answers many schema constrained requests at low effort with no content, and each of those ballots faulted.

The default chat models are placeholders. What matters is that the three judges come from three different families. In episode 13 all three MAGI shared one personality as their base, so what took Melchior took Balthasar next. Three personas on one model share every blind spot, and a prompt injection that fools one fools all. By default BALTHASAR runs on Jev, a family of its own that reads facts computed from the percept and never the proposer's why; on OpenRouter, with MELCHIOR on gpt-oss-20b and CASPER on llama-3.1-8b, that lineup delivered 10 of 10 missions. `BALTHASAR_BACKEND=llm` puts the BALTHASAR persona on a chat model instead, but measured with gemma-3-12b it judged a release by the proposer's why rather than the percept and delivered 0 of 10.

## CL1 backend

Experimental: neither the `cl1` backend nor `sidecar/cl1_sidecar.py` has ever run on a CL1 or flown a mission, so treat what follows as a design. `CORE_BACKEND=cl1` swaps the language core for a culture. `sidecar/cl1_sidecar.py` runs on the CL1, because the CL API is a Python SDK. It streams spikes in the format of Cortical Labs' UDP receiver example and turns stim packets from `core/cl1.v` into stimulation. The beacon's direction is place coded as stimulation rates on four sensory channels, and the imbalance between four motor channels becomes a short hop. Feedback follows DishBrain: a predictable burst after success, seconds of unpredictable stimulation after failure, because a culture takes no reward scalar and learns to keep its input predictable. Channel maps, rates and amplitudes are starting points, not tuned values; check the stim call against the CL-06 notebook for the SDK on your device. If gehirn cannot listen on `CL1_SPIKES`, or cannot resolve `CL1_SIDECAR`, such as an unknown host or a port past 65535, it prints one line that names the variable and the cause, and exits 1 before anything starts. A UDP dial never contacts its peer, so a wrong address that resolves starts without a word, and the stim packets vanish (Known issue 18 in PLAN.md).

Both CL1 ports are plain UDP without authentication, unlike the plug's signed datagrams. gehirn takes spikes on `CL1_SPIKES`, every interface by default, from any sender, and the sidecar takes stim packets for living neurons on port 12346 of every interface, also from any sender. Run both on a network nobody else can reach.

## Next

ROS 2 through rmw_zenoh, now that LCL travels on Zenoh, and the motor controller through zenoh-pico. A MuJoCo body instead of the planar simulator. A core fine tuned on its own journal. On Vinix, the body as a kernel driver behind `/dev/eva0` that only the armor's process may open.
