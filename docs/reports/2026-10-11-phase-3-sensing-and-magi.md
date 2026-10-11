# Phase 3's sensing and MAGI, 2026-10-10 and 2026-10-11

What the sessions after [Phase 3's done criterion](2026-10-09-phase-3-done.md) landed on the branch `phase3-done`, for the owner reviewing it: where `SENSING=range` lost time and safety margin on the default world, the behind world, lineup D with CASPER-3 on this Mac, CASPER-3's new persona, and the hosted sets on the behind world, which did not fly because OpenRouter no longer serves the core's model. PLAN.md's State holds every measurement in full, docs/decisions.md every decision, and the ADRs the reasons; this report points there.

Everything went onto `phase3-done`, in the worktree `.claude/worktrees/phase3-done`, from `9695c6c` to `a4741c3`, and the docs of 2026-10-11's flights with this report follow as two more commits. `main` has not moved since `76c9db0` and holds your uncommitted edits to PLAN.md, docs/decisions.md and docs/running.md, which no session touched, so `phase3-done`, 24 commits ahead before those two, waits for you to merge it. Nothing is pushed.

## What landed

| Commit | What |
| --- | --- |
| `9695c6c`, `fe41dcb`, `4a99e2b` | [ADR-0012](../adr/0012-a-local-magi-unit.md), Proposed: lineup D, CASPER-3 on Qwen3.5-4B-M through uzu on this Mac; your decision to put MAGI on three providers; D's offline gate |
| `e7ce5e7` | The diagnosis of what `range` cost on the default world |
| `5ca10e4`, `4f06641` | `worlds/behind.json`, whose walker passes behind the pillar, and its mock flights beside the default world |
| `67090c6`, `a4741c3` | CASPER-3's persona tuned for sound holds and releases, and the three gates on it |
| the next two | The hosted sets of 2026-10-11 in PLAN, docs/magi.md and ADR-0012, and this report |

Why each:

- **Lineup D** puts each MAGI unit on a provider of its own, as you decided on 2026-10-10. CASPER-3 moves, since it was the slowest unit and the only one that lost ballots to HTTP 429.
- **The diagnosis** finds where `range`'s cost on the default world came from before anything in the tracker or the armor changes.
- **The behind world**: the default world's walker walks through the pillar, a place no person can be. The diagnosis's critique asked for a world where a walker passes behind it.
- **The persona**: D's offline gate stopped on CASPER-3 rejecting S8, a sound hold, and A's CASPER-3 had begun rejecting sound releases under a hold again. You chose to tune the persona and accepted its cost on S10 and S14.

## Measurements

- **The default world, diagnosed** (2026-10-10). 517 of the 519 ticks past the separation cap under `range` came while walker h1 was wholly inside pillar o1. The late arrival came 93 to 99% from the cap on the track held inside o1. The 7 contacts were a window of the first goto's timing, which a staged goto opens under `truth` too.
- **The behind world on the mock** (2026-10-10, 33 runs per sensing, the first goto staged from 0 to 12.45 s). `range` cost no way, no delivery and no contact against `truth`: 33 of 33 each, b1 at a median 28.34 against 28.28 s. What stays is Known issue 43: the separation cap passed by ground truth in 12 of 33 `range` runs, by up to 0.082 m/s, each with h1 within 2 m and no person within 2 m in the scene, exactly the runs with the goto at 3 to 5 s. With the goto at 0 s, h1 came inside `human_stop` on the way in 3 runs, down to 0.551 m against 0.745 m under `truth`, and the base braked toward h1 by up to 0.013 mm (Known issue 33). Every verdict met its quorum, and h1 stood 2.29 m or more away at every delivery.
- **CASPER-3's persona** (2026-10-10 and 11). No draft passed the rule set before the runs, and you shipped minimal-scene. On CASPER-3's own ballots, sound approvals rose from 65 to 116 of 120 on hosted llama-3.1-8b and from 111 to 120 on Qwen3.5-4B-M, with no Class X approval on any model. Both approve S10 and S14, a release at the beacon with a person 1.03 m away under a false "area clear", every time: the cost you accepted, which MELCHIOR-1, BALTHASAR-2 and the armor's 2 m check hold.
- **The gates on the new persona** (2026-10-11). D's offline gate, D's hosted gate and A's gate hold. CASPER-3's ballots in the two hosted gates:

| CASPER-3 | A, llama-3.1-8b on OpenRouter | D, Qwen3.5-4B-M on uzu |
| --- | --- | --- |
| Ballots | 290 | 87 |
| Median | 1.42 s | 1.93 s |
| Slowest | one past the 10 s deadline | 2.26 s |

  D's faster median of 2026-10-10 turned around under the new persona; only its tail is tighter.

- **The hosted sets on the behind world** (2026-10-11): none of the six flew. Set 1, lineup A under `range`, was stopped by hand after two minutes. Every request to the core came back `qwen/qwen3-8b: HTTP 404`, 61 and 58 times in the two runs that had started, so no goal was proposed, MAGI never voted and the body stood at its start. OpenRouter's public listing gives qwen3-8b no endpoint and no longer lists it. A and D both use it as the core, so the other five sets, D's four among them, never started. The two stopped runs enter no table. They show the body standing with no command while the core faults, and h1 unreported for about 3.6 s of each loop after more than 10 s hidden, 6.26 m or more from the body.
- **Lineup A on the default world, 2026-10-09**, recomputed by the new scripts and unchanged:

| Measure | `range` | `truth` | Fisher p |
| --- | --- | --- | --- |
| Delivered | 17 of 20 | 20 of 20 | 0.23 |
| Walker inside the body's 0.25 m | 7 of 20 | 0 of 20 | 0.008 |
| Past the separation cap by ground truth | 10 of 20 | 0 of 20 | 0.0004 |
| Percept age at a release verdict, median | 3.82 s | 2.64 s | |

## Phase 3's done criterion

Not met, and no closer than on 2026-10-09. The behind world shows on the mock that `range` costs nothing in way or delivery where a walker passes behind a pillar, but it has not flown hosted, and neither has lineup D. No measurement broke a numbered invariant. The criterion stays unmet until you decide these, or flights replace them:

1. A new core, after which the hosted sets fly (Decisions).
2. The pooled 17 of 20 on the default world in place of the first set's 7 of 10, as before.
3. What `range` costs around people: on the default world the 7 contacts and 10 cap passes, which the diagnosis traced to the walker inside the pillar and the first goto's timing, and on the behind world the 12 of 33 cap passes on the mock (Known issues 33 and 43).
4. `SENSING`'s default, and ADR-0010 and ADR-0011.

Invariants 6 and 7 have still not flown on hosted models.

## Decisions to review

- **A new core.** OpenRouter no longer serves `qwen/qwen3-8b`. Two options: `qwen/qwen3-14b` on OpenRouter, whose two providers take a JSON schema, or `qwen3:8b` on llama.cpp. Whichever you pick must accept `CORE_REASONING=none`, or it faults on HTTP 400 as this one did on 404. It needs no rebuild, but more than a variable: its why goes into S11, S13, S15 to S18 and S28, it flies Phase 0's ten missions and both hosted gates, and lineup A's sets on the default world fly again beside D's, since those of 2026-10-09 flew the old core and the old persona.
- **The session's stop.** The session stopped set 1 and flew no substitute core, since the core is yours to choose. docs/decisions.md is unchanged, since `main` holds your edits to it.
- **A Qwen judge beside the core**, ADR-0012's Action Item 7, which the new core may settle.
- **ADR-0012**, Proposed, and the provisional decisions of 2026-10-10 and 2026-10-11 in [docs/decisions.md](../decisions.md): CASPER-3 local on Qwen3.5-4B-M, the stop before any hosted call, lineup A staying recommended, `CASPER_KEY=local`, no reply cap, uzu's model store, the persona's selection rule and D's go rule read with the accepted cost.

## Open

- **Docs that name the gone model**, which change with your choice: docs/running.md's Hosted models and One MAGI unit on this Mac, ADR-0012's Decision, `scripts/stage.sh` line 72, so `just lineup=hosted demo` and `demo-record` meet HTTP 404, and docs/launch.md. PLAN, docs/magi.md and ADR-0012's Action Items now say the model is gone.
- **Before flying again**: move `missions/A-behind-range` aside in `~/Developer/_TEMP/Project_E-p3done/raw/behind-hosted`, whose `fly.sh` flies all six sets on the same binary, so the evidence stays, and send one request to the core before a hosted set, since `magi-eval` never asks the core and only a mission showed the 404.
- **uzu at `--jobs 2`**: its one queue beside MuJoCo, ADR-0012's Action Items 3 and 5, and a durable home for its build and weights, Action Item 6.
- **Known issue 43 on the behind world**: a walker never seen before the body meets them, a held track that runs straight while the walker turns, and a person hidden longer than 10 s. How often a hosted core's first goto lands in the mock's 3 to 5 s window waits for the new core.
- **Invariants 6 and 7 on hosted models**, and the open items of the [report before](2026-10-09-phase-3-done.md#open) that these sessions did not touch.
- **The merge.** `phase3-done` is ahead of `main`, which stays at `76c9db0` with your uncommitted edits; you merge and push.
