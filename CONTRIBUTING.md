# Contributing

A commit here needs three things: the checks green, a subject in the Conventional Commits style, and a body that says why every invariant it touches still holds. This file is the contract for every contributor, human or agent. PLAN.md says where the project stands and what comes next, the topic docs that docs/README.md lists say how to run gehirn, and docs/adr why it is built this way.

Rules are numbered per section, so a review can cite one: Errors 2, Tests 3. The hooks enforce some of them; review enforces the rest.

## Set up

gehirn builds with V 0.5.2 from Homebrew, commit 45ae01d. The tools under `tools/` need Python 3.10 or newer and nothing else. `just assets`, which renders the brand's raster files, needs uv and rsvg-convert, and runs when the brand, the README's first sentence or the bridge's `fan_line` changes. The `justfile` is the one entry point for the checks, the build and the mock missions, so it needs just. `just zenoh` fetches zenoh-c, pinned to 1.10.1 and checked against its sha256, into `thirdparty/zenoh-c`, which git ignores; it needs curl and unzip, runs before `just test`, and covers macOS on Apple Silicon and Linux on aarch64 and x86_64, with musl or glibc. Moving the pin is its own commit that updates the version and every checksum in `scripts/zenoh.sh` and runs every check. `just mujoco` builds MuJoCo, pinned to 3.14.0 and checked against the sha256 of its source tarball, as one static library into `thirdparty/mujoco`, with the patch and the configure line of ADR-0008; the first build needs curl, patch, cmake, Ninja, a C and a C++ compiler, git and the network, takes about 30 s on the Mac, and covers macOS and Linux with musl or glibc. Moving the pin is its own commit, as for zenoh-c, that runs the `-d mujoco` tests. `just check` never needs it; `just test-mujoco` and `just body=mujoco build` run it first. `just gamepad` builds the gamepad bridge, the one part that needs SDL2's headers and library, which it finds through pkg-config: Homebrew's sdl2-compat on the Mac, `sdl2-compat-dev` on Alpine, `libsdl2-dev` on Debian and Ubuntu. `gamepad/` holds no tests, because its logic lives in `plug/pilot.v`, so `just check` never compiles it and passes without SDL; only `v -W -check gamepad/` and the build need SDL2. The scripts under `scripts/` run on bash 3.2, the one macOS ships, and `just shell` needs shellcheck and shfmt. Every recording, `*.mp4`, is a Git LFS object (`.gitattributes`), so a clone needs git-lfs to fetch them, and a push uploads them through the `pre-push` hook. The git hooks need lefthook, gitleaks and, for the workflows of Continuous integration, actionlint; wire them once per clone, which also installs the four hooks git-lfs runs in:

```sh
lefthook install
```

## Checks

```sh
just check
```

Run it on the working tree before asking for a commit. It runs `just fmt`, `just vet`, `just test`, `just py` and `just shell` and checks the justfile's own format with `just --fmt --check`, and `just --list` says what each checks. The `pre-commit` hook in `lefthook.yml` calls the same recipes on what is staged, so unstaged work in progress cannot fail a commit: `fmt`, `vet`, `py` and `shell` on the staged files, `just --fmt --check` when the justfile is staged, `actionlint` when a workflow is staged, gitleaks on the staged diff, and `test` on a copy of the staged tree whenever a `.v` file is staged, which takes 10 to 11 seconds. Nothing scans the whole tree for keys. A command changes in the `justfile`, and both pick it up.

Any change to a `.v` file outside tests, or to `tools/mock_endpoint.py`, also flies the mock missions, and the commit body reports the result. `just missions` builds gehirn, starts the mock on port 8081, the port of the llama.cpp preset, flies ten missions, puts the adversarial scenarios to the mock MAGI and stops the mock; `just missions 3` flies three, and `just missions 3 9081` flies them on a mock on port 9081, clear of a llama.cpp server or another session's missions. The build takes 30 to 75 seconds, ten missions about two and a half minutes, the scenario gate under a second. Run it in a shell without the hosted exports of docs/running.md: the recipe points `GEHIRN_URL` at the mock, but every mission inherits the other model variables, such as `CORE_URL`. A change to the `mujoco` module, a `_d_mujoco` file or `scripts/mujoco.sh` also runs `just test-mujoco` and flies the mock missions with `BODY=mujoco`, as `just body=mujoco missions` does. A change to `scripts/stage.sh` also flies `just demo`, a change to a scene in `scripts/scenes` or to the world in `worlds/` it plays flies that scene, and the commit body reports the beats. A change to `scripts/record.sh` records the demo with `just demo-record`, and the commit body reports the MP4 and the GIF. Run by hand, a scene or `scripts/record.sh` flies the `./gehirn` that is there, and a scene the `./gehirn-bridge` too, so `just build bridge` comes first.

A failing check is never unrelated. Fix it, or stop and report it.

## Continuous integration

GitHub Actions runs the two workflows in `.github/workflows`, which the `pre-commit` hook checks with `actionlint`.

`check.yml` runs on every push to main and every pull request. Its `linux` job, on Ubuntu 24.04 on x86_64, installs SDL2 and the bridge's X11 and OpenGL development libraries from apt, runs `just check` and then builds gehirn, the bridge and the gamepad, which `just check` does not. Its `mujoco` job, on the same runner, runs what `just check` never compiles (ADR-0008): it installs CMake, Ninja, patch, GCC and G++ for `just mujoco` and the X11, OpenGL, EGL and Xrandr development libraries that the bridge's tests compile against, the last two of which the `linux` job gets with SDL2, restores `thirdparty/mujoco` from GitHub's cache under the hash of `scripts/mujoco.sh`, runs `just mujoco` and saves a fresh build to the cache before the tests run, so MuJoCo builds again only when that script changes or GitHub has evicted the cache, as it does one unused for a week. Then it runs `just test-mujoco` and builds gehirn with `just body=mujoco build`. Its `macos` job runs `just check` on macOS 15 on Apple Silicon, unless the `changes` job finds that the push or pull request touches nothing but `docs/`, `assets/`, `website/`, Markdown files and the license. No check reads those, the `linux` and `mujoco` jobs run anyway, and a macOS minute counts ten against a private repository's free minutes. A push git cannot diff, such as a force push, runs the `macos` job too. A newer push to the same branch or pull request cancels the older run, so a cancelled run is no failure.

`release.yml` runs on a tag `v*`. It builds gehirn, gehirn-bridge and gehirn-gamepad for macOS on Apple Silicon and for Linux with glibc on x86_64 and aarch64, and gehirn as a static musl binary for both Linux architectures, compiled on Alpine (PLAN, Invariant 9). It packs each target with `LICENSE` and the bridge's font licenses into `gehirn-<tag>-<target>.tar.gz` and attaches the archives with their `SHA256SUMS` to a draft release, which the owner publishes. [Running gehirn](docs/running.md#prebuilt-binaries) says how to use them.

Both install their tools with `scripts/toolchain.sh`, each pinned and checked against its sha256 as `scripts/zenoh.sh` pins zenoh-c: V 0.5.2 from its release archive, built from 7647ce1, which is 45ae01d plus V's changelog, and just 1.58.0, shellcheck 0.11.0 and shfmt 3.14.1, the versions on the owner's Mac on 2026-10-05. A newer just or shfmt can format differently from CI's, so a format check that passes locally and fails there points at the version. Moving a pin is its own commit that updates the version and every checksum in `scripts/toolchain.sh` and runs every check. The archive's V carries tcc, which V tries first for a test on Linux, so `warning: tcc compilation failed, falling back to cc` is no failure.

To read a failure, open the failed job and its first red step. In `just check` the last line names the recipe, as in ``error: recipe `test` failed``, and the lines above it say why; `v test` names each failed test with the command that reproduces it. Run that recipe locally first. A failure on Linux alone reproduces in `docker run --platform linux/amd64 ubuntu:24.04` with the job's steps. `toolchain: checksum mismatch`, `zenoh: checksum mismatch` or `mujoco: checksum mismatch` means a pinned download changed under its URL: stop and report it, and never update the checksum to make it pass. CI runs the checks, not the hooks, so gitleaks scans only what a committer stages.

## V code

### Comments

1. A comment adds what the code cannot say: a behavior that is not obvious, or a reason the reader cannot derive, such as a domain rule, an external constraint or a V 0.5.2 bug. It never narrates a change ("now", "used to"), records where code came from, or restates the next line. The commit message holds that.
2. A comment directly above a declaration is its doc comment: `//` lines, no blank line before the declaration, starting with the symbol's name in present tense, as in `// restrain takes the body.` V has no other doc form. `v doc` drops `/* */` and `/** */`, and `v vet` rejects them. A test function's comment may open with the behavior it pins instead, since `v doc` skips tests.
3. A comment about a situation (a reason, a gotcha, context for a few lines) sits inside the body above the lines it explains, or trails its line. It never sits above a declaration: `v doc` publishes it as that symbol's doc (a private symbol's with `-all`), even across a blank line, and the blank line also stops `v vet` from checking that function. A reason that belongs to the whole symbol follows the name sentence in its doc comment, as in `armor.Limits`.
4. Every `pub` symbol has a doc comment: functions, methods, structs, enums, interfaces, sum types, aliases and consts. It says what the symbol is and who uses it, not how it works. `v vet -W` checks functions only; review checks the rest. A field whose unit or range is not obvious states it in a trailing comment, as `armor.Limits` does.
5. Each module has one overview comment above the `module` line of its main file: what the module is and where it sits in the canon.
6. A value that lives in two places, V and a Python tool or a constant and a prompt's prose, has a comment on each side that names the other file and symbol, and one commit changes both. `armor.Limits` and `FENCE` in `tools/mock_endpoint.py` are the model. Where a test can compare the two sides, write the test, because comments alone drift.
7. A deliberate simplification carries a `ponytail:` comment that names its limit and what to do once the limit is hit. One that covers a whole symbol goes into its doc comment after the name sentence (rule 3). A workaround for a V bug names the bug and when to remove the workaround.
8. One blank line sits above every comment block, except at the start of a block, and never between a doc comment and its declaration. Inside an array or map literal no blank line sits above a comment, because `v fmt` deletes blank lines there.

### Naming

1. A module's name equals its directory. V 0.5.2 compiles a mismatch without a word.
2. Receivers are one or two letters from the type, as in `a Armor` and `c Cable`. Never `self` or `this`.
3. A table test takes the name of the function it covers, as `test_tally` does. Any other test is a sentence about behavior: `test_unreachable_unit_votes_fault`, not `test_vote_2`.

### Types and structs

1. A field fixed after construction is `pub:`. A field that changes after construction and is read outside its module is `pub mut:`. V 0.5.2 has no modifier for "read outside, write inside", so review checks that no other module writes it. Internal state is `mut:`, as in `umbilical.Cable`.
2. A closed set inside the stack is an `enum` or a sum type, and a `match` on it has no `else`, so a new variant breaks the build wherever it needs handling. `umbilical.State` is the model.
3. A set that crosses the model boundary stays a string, checked against a const list where it enters. Verbs are the case in point: Invariant 2 needs an unknown verb to stay representable, so it counts as irreversible.
4. A sum type or interface is narrowed with `match` or `if x is T`. `x as T` panics on the wrong variant.
5. An index that comes from input (a datagram, a model reply, a journal line) is length checked first, as `lcl.Intent.label` does, or read with `or {}`. A map key from input is read with `or {}`. An index out of range panics the process, and a missing map key silently returns zero.

### Errors

1. `!T` marks an operation that can fail, `?T` a value that may be absent.
2. A fault is a no. On every path to a vote, a goal or an actuation, an error is caught with `or {}` and becomes the safe outcome: a fault ballot, a halt, a missed pulse. `panic` is for startup only, in `main()` before any `spawn`. Following ADR-0008, MuJoCo's error and a step that leaves the model unstable end the field unit through `mujoco`'s log handler instead (Logging 1), since MuJoCo's error path must not return and no halt repairs an unstable model.
3. An error message is lowercase and starts with what failed, a unit, a model or a module: `armor: release not permitted here`, `${e.model}: HTTP 429`. It names the operation and its input. It never carries a key or a reply body. A json2 decode error starts with a newline and carries color codes, so replace it with a fixed text, as `magi.read_reply` and `core.read_proposal` do. `err.msg().all_before('\n')` suits `net.http` errors, as in `oai.post` and `jev.post`.
4. Code that branches on the kind of an error matches a type, never the text. The error is a struct that embeds `Error` and overrides `msg()`, and the caller tests `err is T`. Tests may assert on text.

### Modules and boundaries

1. The module table in PLAN.md is the dependency rule, and an import outside it needs an ADR. V rejects import cycles but not a forbidden edge, so review compares every new `import` line with the table.
2. What one bounded context hands another while running (percepts, goals, outcomes, pilot input, context) is an `lcl` type. A module's own API (config structs, clients, results such as `magi.Verdict`) is used by `main.v`, `eval.v` and the modules the table lets import it. A model reply, a Jev answer, a datagram or a message from the other tier is decoded into a typed struct inside the module that received it, by that module's one parser (`oai.extract_json`, `magi.read_reply`, `plug.listen`, `wire.Opener`). A `json2.Any` never leaves the function that decoded it.
3. Each boundary has one door. Only `oai` and `jev` import `net.http`. Outside tests, only `plug` and `core/cl1.v` import `net`. Only `zenoh` links zenoh-c, only `mujoco` links MuJoCo (ADR-0008), and only `gamepad/pad.c.v` links SDL. Only `armor` holds a `Body` (Invariant 1). A new door is a new row in the module table.
4. C interop (`C.` declarations, `#flag`, `#include`) lives only in `.c.v` files, and field tier code follows Invariant 9.

### Concurrency

1. Threads start with `spawn`, never `go`.
2. Threads share no mutable state. HQ and the field tier exchange `lcl` values over channels. Introducing `shared` and `lock` is a decision with alternatives, so it needs an ADR.
3. Every channel has a fixed capacity. A sender that must not wait uses `try_push`, and on a full channel it drops a value, the stale one or the new one. The doc of the sending function says which, as `plug.listen` does.
4. The 50 Hz field loop never waits on a channel, on HQ or on the network. Its channel operations are `try_push` and `try_pop`. Slower work runs on its own thread and hands back a value.
5. A call that can hang gets a deadline. Spawn it and wait on a `chan T{cap: 1}` in a `select` with a timeout branch, as `oai.Endpoint.exchange` does. The capacity of 1 lets a late answer land without blocking the abandoned thread.
6. A type that `x.json2` encodes or decodes on more than one thread is warmed in its module's `init()`, as in `oai/oai.v`. V 0.5.2 fills json2's per type cache without a lock, and two threads on a cold type can panic the process.

### Tests

1. Tests sit beside their module as `<file>_test.v` in the same module, so they reach private functions.
2. Tests are table driven where the code carries an invariant or reads outside input: `armor`, the MAGI quorum, `umbilical.Cable`, `plug.Sync`, and every parser of model replies, Jev answers, messages from the other tier, datagrams or journal lines. A table is a slice of a `Case` struct, a slice of arrays or a map literal. The first `assert` in its loop names the case in its message, unless its two sides already show it; a failed `assert` prints both. `magi/magi_test.v` is the model.
3. A change to the code of an invariant adds the case that shows the violation refused.
4. Network faults are tested against a loopback listener the test opens itself, as in `jev/jev_test.v`. No test reaches a real endpoint. Behavior over HTTP beyond that belongs to the mock missions.
5. `assert` belongs in tests only. `v -prod` removes every assert, so a check the running stack needs is an `if` that returns an error or a fault.
6. A test that needs MuJoCo sits in a `$if mujoco ? {}` block of an ordinary `_test.v` file, as `body/mujoco_test.v` does, so `just check` passes it without MuJoCo and `just test-mujoco` runs it. `v test .` compiles a `_d_mujoco_test.v` file without the define and fails (ADR-0008).

### Configuration and secrets

1. Every variable a binary reads has its default where that binary reads it, `load_config` for gehirn, and a row in the table of docs/configuration.md. A default that `gehirn-bridge` or `gehirn-gamepad` repeats names `load_config` as its counterpart (Comments 6). One commit changes all of them.
2. Unset means the default. Set but invalid means gehirn refuses to start and names the variable: a number that does not parse or is out of range, and a choice such as `CORE_BACKEND` or `BALTHASAR_BACKEND` outside its values. Parse a number with `whole` in `main.v`: it accepts an optional minus and ASCII digits only, parses them with `strconv.atoi(s)!` and checks the range, so every refusal reads either not a whole number or out of range. Never use `s.int()` or `s.i64()`: `'10s'.int()` is 10, `'abc'.int()` is 0 and `'99999999999'.int()` is 2147483647. Never use `strconv.parse_int(s, 10, 64)` either: V 0.5.2 returns the i64 limit without an error for any value from 2^63 to 2^64 - 1 and reads an empty string as 0. A decimal, such as each half of `START`, passes `is_decimal` before `strconv.atof64`, which also reads exponents. A refusal, and any status line, shows a value from the environment through `lcl.quoted`, so it stays one line of printable ASCII. Command line arguments follow the same rule, such as the repetitions of `magi-eval`.
3. A value read from the environment is a `Config` field, never a `const`. A `const` is a fact fixed at compile time.
4. A key goes to its own endpoint only, in the `Authorization` header only. `UMBILICAL_KEY`, `PILOT_KEY` and `WATCH_KEY` go nowhere: they sign and check messages inside each process. It never appears in a URL, a log line, the journal, an error message or a commit.
5. Keys live in `.env`, which git ignores, and `.env.example` lists the names. Nothing prints `.env`. Anything that needs a key runs as `python3 tools/withenv.py .env <command>`, which hands the values to the command without printing them.

### Logging

1. Only `main.v`, `eval.v`, `bridge/main.v` and `gamepad/main.v` print, and the bridge draws. Modules return values and errors, and the caller that decides logs once. A thread with nothing to return to, such as `plug.listen`, logs its own failure once and ends. So does MuJoCo's log handler in `mujoco` (ADR-0008): it prints MuJoCo's error as one line that starts with `field: mujoco:` and ends the process.
2. A status line starts with its source and a colon: `hq:`, `field:`, `armor:`, `magi:`. A line that `tools/trials.py` or a script in `scripts/` parses or waits on names its reader in a comment, the reader names the line, and one commit changes both.
3. The journal and the recorder are data, not logs. Only `core.Memory` writes the journal and only `plug.Recorder` writes the recorder, both by appending (Invariant 11). No tool and no person edits a `.jsonl` file.
4. Text from a model or a server, such as a proposal, a ballot's why or a fault, reaches a status line through `lcl.escaped`, so a model can neither break the line nor forge another. `lcl.quoted` does the same for a value from the environment and cuts it after 64 bytes.

### V 0.5.2

1. The compiler is the source of truth. The language docs for this release are at https://github.com/vlang/v/blob/0.5.2/doc/docs.md, and vlib's source ships in `/opt/homebrew/opt/vlang/libexec/vlib`.
2. Examples on the web and in agent skill packs often target V master or older releases. Check each against 0.5.2: interpolation is only `'${x}'`, attributes are `@[...]`, generics are `[T]`, and neither `-race` nor `import json2` exists yet. `'$x'` is the literal text `$x`, and the compiler only notices when that leaves `x` unused.
3. JSON goes through `x.json2`. The cJSON `json` module still ships with 0.5.2 but is removed upstream, so nothing imports it.
4. In a generic function, a `defer` after an `or { return }` trips the 0.5.2 checker ("too many expr levels"). Move both into a non generic helper, as `core.Memory.append` does.
5. A suspected race is checked with ThreadSanitizer: build with `-cflags -fsanitize=thread -gc none`.
6. The bridge's frames are checked from PNGs that `gg` saves: build with `-d gg_record -d darwin_sokol_glcore33` and run with `VGG_SCREENSHOT_FOLDER`, `VGG_SCREENSHOT_FRAMES` and `VGG_STOP_AT_FRAME`. On Metal, sokol's screenshot readback fails with code -100, hence OpenGL; macOS also slows the frames of a covered window, so a frame number is not a time. Pass the bridge `-NSAppSleepDisabled YES` too, an argument AppKit reads for that process only: without it App Nap slows a window nobody sees, as behind a locked screen, to a few frames a second after about 30 s. `scripts/record.sh`, which saves every frame, adds `-d bridge_1x`, because writing every frame as a PNG at Retina size held it to 7 frames a second, so its frames are 1280 by 800 on any display and come about 38 a second on a Retina Mac (PLAN, Known issue 24). A build without it draws at the display's scale, so only its frames show the 2x path, such as `text`'s anchor.
7. Upgrading V is its own commit. It updates every mention of the release (`rg -n '0\.5\.2|45ae01d'`), runs every check and the mock missions, retests the json2 warm up (Concurrency 6), the generic `defer` (rule 4) and the cut array (rule 8), and moves `x.json2` to `json2` if the new release deprecates the old path.
8. `x.json2` never returns from decoding a text that ends right after a number inside an array, such as `{"pose":[0.5`. Text that a kill, a crash or a faulty peer can cut, such as a recorder line, a weights file or a signed datagram, passes `lcl.complete`, the check that its brackets close, before it is decoded. `x.json2` also decodes each level of nesting in a call of its own, so a text nested some thousands deep overflows the stack, and `lcl.complete` refuses one nested deeper than `lcl.max_depth`, 32. PLAN's Known issue 25 lists the decoders that still lack it.
9. When a C build fails, V 0.5.2 uploads the failing C line and the V source around it, up to 40 lines on each side, to bugs.vlang.io unless `V_C_ERROR_BUG_REPORT_DISABLED` is set, so the `justfile` exports it as 1 for every recipe and the hooks, a script that runs `v` exports it itself, since the justfile's export reaches only what just starts, and a shell that runs `v` by hand sets it too.

## Python tools

1. Python stays outside the runtime. The tools drive, mock and measure gehirn from outside. `sidecar/cl1_sidecar.py` runs on the CL1 because its SDK is Python.
2. Standard library only. The sidecar's `cl` SDK is the one import from outside it. `assets/build.py` is no tool but a design time generator: it declares its third party packages, pinned exactly, as inline script metadata for `uv run --script`, and nothing in the checks, the missions or the runtime runs it.
3. A script opens with a docstring that says what it does and shows how to call it. Functions have type hints, and a function another tool imports has a docstring, as `withenv.load_env` does.
4. A constant copied from V is an UPPER_CASE module constant with the comment of Comments 6.
5. A function another tool imports, and every new parser or loader, has a self check, `tools/test_<name>.py`, that runs under plain `python3` and asserts, as `tools/test_withenv.py` does. `just py` runs every one.

## Shell scripts

1. A recipe body longer than a few lines lives in `scripts/`. The recipe passes its parameters as positional arguments, and the script gives each one a default and changes to the repository root itself, so it also runs by hand from anywhere.
2. A script in `scripts/` starts with `#!/usr/bin/env bash` and `set -euo pipefail` and carries the executable bit. A sourced file, such as `scripts/stage.sh`, has no shebang and names its shell in `# shellcheck shell=bash`. A script that runs `v` exports `V_C_ERROR_BUG_REPORT_DISABLED` (V 0.5.2 rule 9).
3. The scripts run on bash 3.2, the one macOS ships: under `set -u` an empty array is unbound, and `declare -A`, `mapfile`, `${x,,}` and `wait -n` do not exist. A list goes into a function as its arguments, which may be empty.
4. Every `.sh` file passes `just shell`: shellcheck at its default severity, following `source` (`-x`), and the format of `shfmt -i 4 -ci`, which `shfmt -i 4 -ci -w` applies. A script that sources another names it in `# shellcheck source=`, a path from the repository root.

## Commits

```
<type>[(scope)][!]: <subject>

type   build chore ci docs feat fix perf refactor style test
scope  optional: a module (lcl body armor plug core magi oai jev umbilical zenoh wire),
       or bridge, gamepad,
       or eval, tools, scripts, sidecar, adr, vscode, assets
```

1. The `commit-msg` hook checks the type, the scope's form and the colon, and rejects the trailers of rule 7. Review checks the rest: after the colon the subject is lowercase and imperative, and names keep their case, as in `feat: tune MAGI for hosted models and make Jev BALTHASAR`.
2. One concern per commit, and no refactoring outside the task at hand. A mechanical sweep, such as `v fmt -w .` or a comment cleanup, is a commit of its own.
3. The body is prose wrapped at 72 columns: why, any external constraint, and what was verified (the checks, the mock missions, real models). A change across modules gives one bullet per module.
4. A commit that touches an invariant says in its body why each one it touches still holds: `Invariant 3 holds: ...`.
5. A commit that changes a safety number (an `armor.Limits` field, the quorum, a deadline, the umbilical's grace or budget) lists each old and new value in its body.
6. Docs the change makes false are fixed in the same commit: the table of docs/configuration.md, the topic docs, PLAN's state, tasks and known issues, an ADR's consequences.
7. No `Co-authored-by` and no `Signed-off-by` trailers.

## ADRs

1. A decision with real alternatives gets an ADR in `docs/adr`: a dependency outside the module table, a new external service or C library, a new way threads share state, a change to an invariant. PLAN's phases name the ones already planned.
2. Files are `NNNN-slug.md`, numbered in order, in the format of ADR-0001: Status, Date and Deciders, then Context, Decision, Options Considered with pros and cons per option, Trade-off Analysis, Consequences and Action Items.
3. An ADR starts as Proposed. The owner accepts it, and the status records the day: `Accepted on 2026-10-01`.
4. An accepted ADR is never deleted or rewritten. A changed decision is a new ADR, and the old one's status becomes `Superseded by ADR-NNNN`, naming the part when only part is superseded.

## Docs

1. US English in code, comments and docs. Prose uses no dashes as punctuation.
2. Each doc has one reader. README.md serves someone arriving at gehirn, docs/README.md someone looking for a doc, each topic doc it lists someone running or studying that part of gehirn, bridge/README.md someone changing how the bridge is drawn, assets/README.md anyone looking for or adding an image, a recording, an icon or a font, PLAN.md whoever works next, docs/adr anyone asking why, docs/decisions.md anyone reopening a decision of the owner's, docs/launch.md the owner taking gehirn public, docs/research/ anyone asking what the series shows, docs/reports/ the owner reviewing what a session landed, and this file anyone changing code. A fact lives in the doc that owns it, and the others point there.
3. Present tense. A date stands only beside a measurement or a status.
