# gehirn

An Evangelion themed control stack in V 0.5.2: a core proposes goals, MAGI judge them, a pilot or the dummy plug steers, and the restraint armor holds a simulated body. Python under `tools/` drives and measures it from outside. This file holds what a session needs beyond the docs.

## Read first

- `PLAN.md` in full, before any task: state, invariants, phases, known issues.
- `CONTRIBUTING.md` in full, before the first commit of a session: the coding guide, the checks and the commit rules.
- The topic doc that `docs/README.md` lists before touching its part or a tool it documents: `docs/configuration.md` before configuration, `docs/running.md` before how gehirn runs and the tools that fly it, `docs/piloting.md` before the pilot and dummy plug tools, `docs/magi.md` before `magi-eval` and `tools/scenarios.json`.
- The ADR that covers an area before touching it: ADR-0001 for where the tiers run, ADR-0002 for Jev as BALTHASAR-2.
- `docs/decisions.md` before reopening something the owner decided, and `docs/research/` before researching the series again.

## Rules

- **Keys** follow CONTRIBUTING.md, Configuration 5. Ask Marvin for a variable `.env.example` does not list.
- **Fly missions through `tools/trials.py`, not `./gehirn` in the repo root.** gehirn appends to `core.<pilot>.jsonl` and `plug.<pilot>.jsonl` in its working directory, and those are the pilot's journal and the dummy plug's training set (Invariant 11). trials.py gives every run a fresh directory. `./gehirn magi-eval` writes neither file.
- **V 0.5.2 is the compiler, not V master.** `.prototools` pins it, and `proto use` installs it once per machine; inside the repository proto's shim runs it. Online docs, examples and agent skills track master or older releases, and none of it counts until it compiles here. Look things up in the release itself:
  - `v where fn restrain -mod armor` finds a definition in a project module.
  - `v where fn get -dir ~/.proto/tools/v/0.5.2/vlib/net/http` finds one in vlib; `-mod` panics on vlib modules such as `x.json2`.
  - `v where` misses generic functions, so search for those: `rg -n '^pub fn decode' ~/.proto/tools/v/0.5.2/vlib/x/json2`.
  - `v doc -f md -o - <module>` renders a module's docs, and `-all` adds its private symbols.
- **The edit loop**, unless a PostToolUse hook in `.claude/settings.json` runs it: after each edit, `v fmt -w <file>`, then `v -W -check .`, or `v -W -check <file>` for a `_test.v` file, which `.` skips. Before asking for a commit, the Checks of CONTRIBUTING.md.
- **Code search.** ripwire skips `.v` files, so for V use `rg`, `v where` and the language server if it is set up. ripwire still maps `tools/` and the docs.
- **Commits** follow CONTRIBUTING.md, and `lefthook.yml` checks them.
