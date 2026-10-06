# Configuration

Every variable gehirn, `gehirn-bridge` and `gehirn-gamepad` read, with its default, then what makes gehirn refuse to start and what the reasoning efforts do on each provider.

Each binary reads its variables from the environment. Keys go into `.env`, which `python3 tools/withenv.py .env <command>` hands to the command without printing them ([Hosted models](running.md#hosted-models)), and a variable the shell sets wins over `.env`. Adding or changing a variable follows CONTRIBUTING's [Configuration and secrets](../CONTRIBUTING.md#configuration-and-secrets): gehirn keeps each default in `load_config` in `main.v`.

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
| `BALTHASAR_BACKEND` | `jev` | `jev` asks TypeSafe's Jev ([ADR 0002](adr/0002-jev-as-a-magi-unit.md)) on `jev-1.13.0`, the model its thresholds are tuned on, and ignores BALTHASAR's `_URL`, `_KEY`, `_MODEL` and `_REASONING`. `llm` puts the persona on a chat model instead. MELCHIOR and CASPER always run on chat models |
| `TYPESAFE_URL` | `https://api.typesafe.ai/v1/systemone` | Endpoint for Jev |
| `TYPESAFE_API_KEY` | empty | Bearer token for Jev; never sent to a chat model. Without it BALTHASAR faults every ballot, so nothing irreversible passes, and gehirn says so at startup |
| `SSL_CERT_FILE` | the first of `/etc/ssl/cert.pem`, `/etc/ssl/certs/ca-certificates.crt` and `/etc/pki/tls/certs/ca-bundle.crt` that exists | CA bundle every https endpoint's certificate must chain to. The defaults are where macOS and Alpine, Debian and Ubuntu, and Fedora and RHEL keep it; elsewhere set it. Without the file every https call faults, and gehirn says so at startup |
| `MAGI_TIMEOUT_MS` | `10000` | Deadline for one ballot, 1000 to 15000. A unit that misses it votes no |
| `CORE_TIMEOUT_MS` | `10000` | Deadline for one proposal from the core, 1000 to 15000 |
| `CORE_BACKEND` | `llm` | `llm` or `cl1`, which is experimental ([CL1 backend](cl1.md)) |
| `CL1_SPIKES` | `0.0.0.0:12345` | Where spikes from the CL1 sidecar arrive, from any sender: the port has no authentication |
| `CL1_SIDECAR` | `127.0.0.1:12346` | Where stim packets go |
| `PILOT_ID` | `shinji` | The only pilot this core accepts, and the pilot `gehirn-gamepad` sends as |
| `PLUG_LISTEN` | `0.0.0.0:7777` | UDP address for pilot input |
| `PLUG_ADDR` | `127.0.0.1:7777` | Where `gehirn-gamepad` sends its datagrams, as host and port: the field unit's `PLUG_LISTEN` as the pilot's machine reaches it |
| `PILOT_KEY` | empty | The pilot's key, 64 hex digits, that signs every datagram and reply; `tools/pilot.py` and `gehirn-gamepad` read the same variable, and never the same as `UMBILICAL_KEY` or `WATCH_KEY`. Without it no pilot can steer or eject, and `gehirn-gamepad` refuses to start |
| `MISSION` | deliver to b1, avoid humans | What HQ is trying to achieve |
| `START` | `-3.5,-2.5` | Where the simulated body starts, `x,y` in meters inside the armor's fence of -5 to 5 on each axis; `tools/pilot.py` reads it too |
| `DRIVE` | `holonomic` | How the simulated body moves: `holonomic` slides in any direction, `differential` turns in place and drives only along its heading, like a robot on two wheels ([Safety](safety.md#how-the-body-moves)). The demo and the scenes pass it through |
| `CORE_JOURNAL` | `core.<pilot>.jsonl` | The soul: append only, one per pilot. It also records every MAGI ballot and every core fault |
| `PLUG_RECORDER` | `plug.<pilot>.jsonl` | Every tick with its scene, and the dummy plug's training set |
| `DUMMY_WEIGHTS` | `dummy.<pilot>.json` | The dummy plug's trained network from `tools/train_dummy.py`; without the file the dummy plug clones the recorder |
| `HQ_PERIOD_MS` | `1500` | Pause between deliberations, 100 to 3000 |
| `MAGI_COOLDOWN_MS` | `10000` | Wait before an irreversible proposal may be put again, 5000 to 60000, so always longer than the pause |
| `UMBILICAL_GRACE_MS` | `45000` | Silence from HQ before the cable counts as cut, 40000 to 60000, so always longer than both deadlines plus the pause |
| `INTERNAL_BUDGET_MS` | `300000` | Internal power after the cut, 0 to 300000; then the body stands still, whoever sits in the seat, until HQ's pulse reconnects the cable. 0 stops it as soon as the cable counts as cut |
| `UNIT_ID` | `eva01` | The unit's name in every key expression, `gehirn/<unit>/...`: 1 to 32 lowercase letters, digits and hyphens |
| `UMBILICAL_KEY` | empty | The unit's link key, 64 hex digits, the same on HQ and the field unit. `hq` and `field` refuse to start without it; it signs messages and never leaves the process |
| `WATCH_KEY` | empty | Key of the watch streams to the bridge, 64 hex digits, the same on HQ, the field unit and the bridge, and never the same as `UMBILICAL_KEY` or `PILOT_KEY`. It shows, it cannot approve or pulse; without it neither tier publishes them ([ADR 0005](adr/0005-the-bridge.md)) |
| `BRIDGE_ENDPOINT` | `tcp/127.0.0.1:7448` | Zenoh locator the bridge listens on, which `hq` and `field` dial when `WATCH_KEY` is set, each from a session of its own |
| `UMBILICAL_ENDPOINT` | `tcp/127.0.0.1:7447` | Zenoh locator that `hq` listens on and `field` dials, such as `tcp/0.0.0.0:7447` on HQ and `tcp/hq.local:7447` on the field unit |
| `VUI_FONT` | Arial Unicode where macOS keeps it | A font file `gehirn-bridge` draws the glyphs from that its built-in fonts lack, such as Japanese in a model's why; set it where Arial Unicode is missing, as on Linux |

## Refusals

An empty variable counts as unset. A number that is not whole or lies outside its range, a `START` that is not two decimals inside the fence, or a backend or `DRIVE` outside its values, stops gehirn before anything starts: it prints one line that names the variable, its value, what is wrong and what it accepts, and exits 2. A whole number is ASCII digits with an optional minus, and a decimal may add a point and more digits. The line quotes the value, escapes quotes, backslashes and every byte outside printable ASCII as `\xHH`, and cuts it after 64 bytes, so a value cannot break the line. A first argument other than `magi-eval`, `hq` or `field` stops gehirn the same way before it reads a variable, as does an argument after `hq` or `field`, and `magi-eval` with more than two arguments prints such a line and exits 2. Two MAGI units on chat models that name the same model at the same URL stop gehirn the same way, naming both `_MODEL` variables, because the three judges must come from three families; gehirn compares the ids only, so two models of one family under different names still start. One key set as two of `UMBILICAL_KEY`, `PILOT_KEY` and `WATCH_KEY` stops gehirn the same way, naming both variables, since each key belongs on the machines of one role: the link key approves and pulses, the pilot's key steers and ejects, and the bridge may do neither. A refusal of `UMBILICAL_KEY`, `PILOT_KEY` or `WATCH_KEY` never shows its value. If `hq` or `field` cannot use `UMBILICAL_ENDPOINT` or `BRIDGE_ENDPOINT`, gehirn prints one line that names the variable and the cause, and exits 1.

## Reasoning and providers

OpenRouter, llama.cpp, Ollama and vLLM 0.22 or newer honor `reasoning_effort`; LM Studio ignores it, so switch thinking off in the model's settings there. Not every model takes every value. gpt-oss cannot stop reasoning, so `CORE_REASONING` must be `low` if the core runs gpt-oss. Ollama refuses a named effort for a model without thinking, so set `MELCHIOR_REASONING=default` if MELCHIOR runs one there.

Every chat request also asks OpenRouter to try its fastest hosts first (`provider.sort` throughput, what the `:nitro` suffix does); llama.cpp, Ollama and vLLM ignore the field. Balanced by price, OpenRouter sent about a quarter of gpt-oss-20b's ballots to a host that answers many schema constrained requests at low effort with no content, and each of those ballots faulted.
