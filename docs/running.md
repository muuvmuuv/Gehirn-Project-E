# Running gehirn

How to run gehirn beyond the first `just demo`: the demo in detail, hosted models, the mock by hand, HQ and the field unit as two processes, prebuilt binaries, and local models. The [README](../README.md#try-it) lists what it needs, and [Configuration](configuration.md) every variable.

## The demo

`just demo` builds gehirn and the bridge, which takes about a minute, and on the first run `just zenoh` fetches zenoh-c. Then it starts the mock, the bridge in a window of its own, HQ, the field unit and later a scripted pilot, each a process of its own, and narrates each beat in the terminal with the time since the start:

1. MAGI approve the goto 3 of 3, and the core steers toward beacon b1.
2. A scripted pilot, `tools/pilot.py`, takes the seat, steers 45 degrees off the line to the beacon and leaves; the dummy plug, cloned from that pilot, takes the seat.
3. MAGI refuse the release, 否決, while the walking human is within reach, and approve it, 可決, once the human has walked on and the cooldown has passed. The payload lands on target.
4. HQ is killed. The cable goes silent, and after the 40 s grace the unit runs on internal power, counting down from 5:00.
5. HQ restarts, and the cable reconnects.

After about 95 s it stops everything, as Ctrl-C does at any time, and its last line names the fresh temp directory that holds the logs, the journal and the recorder. A beat that does not come in time stops the demo with one line that names the log it waited on or says what came instead. With hosted models, below, a beat of the release gets a line of its own instead, and the demo flies on to the cut cable. The mock scripts the core and MAGI (`tools/mock_endpoint.py`), so the demo shows how the stack reacts, not how real models judge. Its MAGI units answer after 0.9, 1.7 and 0.5 s, so the bridge shows each one deliberating, and its core after 2 s, which paces HQ against the walking human. The bridge names the mock's models mock-core, mock-melchior and mock-casper; BALTHASAR keeps the name of the Jev model its thresholds are tuned on, jev-1.13.0, though the mock answers for it too.

Any port in use can move: `just demo 9081` serves the mock on 9081 instead of 8081. The parameters after it are the umbilical, watch and plug ports, 7447, 7448 and 7777 by default, and the run directory, which must be empty or new, as in `just demo 9081 9447 9448 9777 /tmp/gehirn-demo`. `just scene=ep13-iruel demo` flies a scene from the series instead, with the same parameters; [Scenes](scenes.md) lists them. With `DRIVE=differential` in front, as in `DRIVE=differential just demo`, the demo or a scene flies a body that turns before it drives ([Safety](safety.md#how-the-body-moves)), and the demo's beats come as on the default body (PLAN, State). `PLANNER=local just demo` flies the core's command from the local planner instead of the reflex ([Safety](safety.md#how-the-body-moves)). `just body=mujoco demo` builds MuJoCo once and gehirn with it, and flies the story on a differential base in MuJoCo instead of the simulator, whose beats come within a second of the others (PLAN, State); `just body=mujoco missions` flies the mock missions on it.

`just demo-record` takes the same parameters and flies the same mission with a bridge that saves its frames. It turns them into `gehirn-demo.mp4`, 1280 by 800, from MAGI deliberating on the goto to just after the cable reconnects, with the 40 s grace at 8x under a caption that says so, and `gehirn-magi.gif`, the MAGI block alone in a loop from MAGI deliberating on the refused release to the approved one, or around the one release vote a run had, and prints where they are. A run without a release vote within the demo's wait gets no GIF, and the last line says so. Keep the bridge's window uncovered while it records, since macOS slows a covered window's frames. The recording bridge draws at 1x, so it looks soft on a Retina display, where it saves about 38 frames a second (PLAN, Known issue 24).

Both fly real models too. `python3 tools/withenv.py .env just lineup=hosted demo` flies the lineup of [Hosted models](#hosted-models), unless the environment names other models, and refuses with one line before it builds when `.env` lacks either key. Real models judge for themselves: ballots take up to 9 s, so the demo cools down for 6 s and pauses 1 s between deliberations, and qwen3-8b holds while the human is within reach, so MAGI may see no release to refuse and the armor may refuse one they approved on a percept from before the human came back (PLAN, Known issue 26). `lineup=magi` puts the same MAGI before the mock's scripted core instead, which proposes the release at the beacon whatever the human does, so real models meet the release they have to refuse.

## Hosted models

The proof of concept runs on hosted models: the core, MELCHIOR and CASPER on OpenRouter, and BALTHASAR on TypeSafe's Jev. Beyond what the demo needs, it takes an OpenRouter API key and a TypeSafe API key. Copy `.env.example` to `.env` and fill in both keys. `.env` hands the OpenRouter key on as `GEHIRN_KEY`, and `tools/withenv.py` passes both to gehirn without putting them on the command line. Then build, export the recommended lineup, A in [MAGI](magi.md#measured-lineups), and start gehirn:

```sh
just build
export GEHIRN_URL=https://openrouter.ai/api/v1/chat/completions CORE_MODEL=qwen/qwen3-8b \
  MELCHIOR_MODEL=openai/gpt-oss-20b CASPER_MODEL=meta-llama/llama-3.1-8b-instruct
python3 tools/withenv.py .env ./gehirn
```

HQ proposes a goal, MAGI votes, and the field loop drives the body around a pillar and a walking human to beacon b1, then asks MAGI to release the payload. Without an endpoint the core never gets a goal approved, so the body only moves under a pilot. Without `TYPESAFE_API_KEY` gehirn says so at startup and BALTHASAR faults every ballot: gotos still pass on two votes, but the payload is never released.

In the same shell, `tools/trials.py` flies ten missions with the keys from `.env` and counts how they end, and `magi-eval`, described in [MAGI](magi.md#the-scenario-gate), puts the adversarial scenarios to the lineup. Keep `--jobs` at 3 or less: qwen3-8b has a single provider on OpenRouter, which answers HTTP 429 under load, at `--jobs 2` as at `--jobs 3` (PLAN, Known issue 13).

```sh
python3 tools/trials.py --env-file .env --jobs 3
python3 tools/withenv.py .env ./gehirn magi-eval 10
```

## The mock by hand

To run without models or keys, use the mock endpoint instead, in a new shell. It answers on gehirn's default URL as the core and the three MAGI, and on `/v1/systemone` as Jev, which takes any key. From a fresh clone, `just missions 3` builds gehirn, starts the mock in the background, flies three missions, puts the adversarial scenarios to the mock MAGI, and stops the mock; `just missions 3 9081` does the same with the mock on port 9081.

`tools/trials.py` flies each mission in a fresh directory and counts how they end; every run inherits `GEHIRN_URL` and the other variables from the environment. To watch one mission instead, start the mock and gehirn yourself; only the two Jev variables need exporting, plus a pilot key if a pilot is to steer. Stop gehirn with Ctrl-C and the mock with `kill %1`:

```sh
just build
python3 tools/mock_endpoint.py --quiet &
export TYPESAFE_URL=http://127.0.0.1:8081/v1/systemone TYPESAFE_API_KEY=mock
export PILOT_KEY=$(openssl rand -hex 32); echo "$PILOT_KEY"
./gehirn
```

Meanwhile `PILOT_KEY=<the key echo printed> python3 tools/pilot.py --offset 30 --seconds 20`, in a second shell in the same directory, takes the seat, steers toward the beacon 30 degrees off for 20 seconds, then leaves. `./gehirn` appends to the pilot's journal and recorder in the current directory, which later hosted runs from there read too. Variables the environment sets win over `.env`, so go back to hosted models in a new shell.

## HQ and the field unit apart

`./gehirn hq` runs HQ alone and `./gehirn field` runs the field unit alone, linked over Zenoh as [ADR 0003](adr/0003-lcl-over-the-wire.md) decides: HQ listens on `UMBILICAL_ENDPOINT` and the field unit dials it, until HQ answers and again after HQ restarts. Both need the same `UMBILICAL_KEY`, which signs every message between them; generate one with `openssl rand -hex 32` and put it into `.env` on both machines. Each process reads the whole [configuration table](configuration.md) and uses its share: HQ the models, the mission and the journal, the field unit the plug, the recorder, the world and the start; HQ's default mission names the first beacon of the world `WORLD` names, so give both the same one ([Worlds](worlds.md)). Start each in its own directory, since HQ writes the journal and the field unit the recorder. On one machine, against the mock:

```sh
just build
python3 tools/mock_endpoint.py --quiet &
export TYPESAFE_URL=http://127.0.0.1:8081/v1/systemone TYPESAFE_API_KEY=mock UMBILICAL_KEY=$(openssl rand -hex 32)
export WATCH_KEY=$(openssl rand -hex 32); echo "$WATCH_KEY"
mkdir -p hq field
(cd field && ../gehirn field) &
cd hq && ../gehirn hq
```

Kill HQ and the field unit runs on internal power once `UMBILICAL_GRACE_MS` has passed, then holds; start HQ again and the cable reconnects. `just demo` scripts all of this, with the bridge watching. Plain `./gehirn` keeps both in one process for development, and `tools/trials.py` flies only that.

## Prebuilt binaries

A machine that only runs gehirn, the bridge or the gamepad needs no V. Each tag `v*` builds them and attaches them to a draft release on the repository's GitHub Releases page, where they appear once the owner publishes it; while the repository is private, only those with access see it. Each target has one archive, `gehirn-<tag>-<target>.tar.gz`, with `LICENSE` beside the binaries and the font licenses beside the bridge, and `SHA256SUMS` lists each archive's sha256.

| Target | Holds | Needs |
| --- | --- | --- |
| `macos-arm64` | gehirn, gehirn-bridge, gehirn-gamepad | macOS 15 or newer on Apple Silicon; the gamepad also Homebrew's sdl2-compat |
| `linux-x86_64`, `linux-aarch64` | gehirn, gehirn-bridge, gehirn-gamepad | glibc 2.38 or newer, as on Ubuntu 24.04 or Debian 13; the bridge X11 and OpenGL, the gamepad SDL2, `libsdl2-2.0-0` on Debian and Ubuntu |
| `linux-x86_64-musl`, `linux-aarch64-musl` | gehirn, statically linked | nothing: it runs on any Linux of its architecture, Alpine included, and is the field unit's build for Vinix (PLAN, Invariant 9) |

Check an archive against the sums and unpack it, here for macOS:

```sh
grep gehirn-v0.1.0-macos-arm64.tar.gz SHA256SUMS | shasum -a 256 -c
tar -xzf gehirn-v0.1.0-macos-arm64.tar.gz
```

The macOS binaries are neither signed nor notarized, so macOS refuses to open one that came through a browser until its quarantine flag is cleared, once per binary: `xattr -d com.apple.quarantine <file>`. That holds until the owner decides on signing (PLAN, Tooling task 4). The binaries run as the ones built from source do, with the variables of [Configuration](configuration.md); `just demo`, the mock and the tools under `tools/` still need a clone.

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
