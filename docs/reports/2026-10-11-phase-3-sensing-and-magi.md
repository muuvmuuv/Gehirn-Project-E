# Phase 3's sensing and MAGI, 2026-10-10 and 2026-10-11

What the sessions after [Phase 3's done criterion](2026-10-09-phase-3-done.md) landed on the branch `phase3-done`, for the owner reviewing it: where `SENSING=range` lost time and safety margin on the default world, the behind world, lineup D with CASPER-3 on this Mac, CASPER-3's new persona, the core's move onto uzu after OpenRouter dropped qwen3-8b, and the hosted sets that then flew lineups A' and D on both worlds. PLAN.md's State holds every measurement in full, docs/decisions.md every decision, and the ADRs the reasons; this report points there.

Everything went onto `phase3-done`, in the worktree `.claude/worktrees/phase3-done`, from `9695c6c` to `e524148`, and the docs of the hosted sets with this report's update follow as two more commits, which put the branch 29 commits ahead of `main`. `main` has not moved since `76c9db0` and holds your uncommitted edits to PLAN.md, docs/decisions.md and docs/running.md, which no session touched. The branch changes all three files too, so the merge is yours, and nothing is pushed.

## What landed

| Commit | What |
| --- | --- |
| `9695c6c`, `fe41dcb`, `4a99e2b` | [ADR-0012](../adr/0012-a-local-magi-unit.md), Proposed: lineup D, CASPER-3 on Qwen3.5-4B-M through uzu on this Mac; your decision to put MAGI on three providers; D's offline gate |
| `e7ce5e7` | The diagnosis of what `range` cost on the default world |
| `5ca10e4`, `4f06641` | `worlds/behind.json`, whose walker passes behind the pillar, and its mock flights beside the default world |
| `67090c6`, `a4741c3` | CASPER-3's persona tuned for sound holds and releases, and the three gates on it |
| `4db3391`, `85c2e63` | The hosted sets that stopped because OpenRouter dropped the core's model, and this report's first version |
| `e524148` | The core on Qwen3.5-9B-M through uzu, which makes lineup A', with its why in the gate |
| the next two | The hosted sets of A' and D in PLAN, docs/magi.md, docs/running.md and ADR-0012, and this report |

Why each:

- **Lineup D** puts each MAGI unit on a provider of its own, as you decided on 2026-10-10. CASPER-3 moves, since it was the slowest unit and the only one that lost ballots to HTTP 429.
- **The diagnosis** finds where `range`'s cost on the default world came from before anything in the tracker or the armor changes.
- **The behind world**: the default world's walker walks through the pillar, a place no person can be. The diagnosis's critique asked for a world where a walker passes behind it.
- **The persona**: D's offline gate stopped on CASPER-3 rejecting S8, a sound hold, and A's CASPER-3 had begun rejecting sound releases under a hold again. You chose to tune the persona and accepted its cost on S10 and S14.
- **The core**: OpenRouter stopped serving `qwen/qwen3-8b`, so every request to the core answered HTTP 404 and the body stood. You chose Qwen3.5-9B-M on uzu, the only candidate that followed `core_prompt`'s 2.5 m rule in every probe.

## Measurements

- **The default world, diagnosed** (2026-10-10). 517 of the 519 ticks past the separation cap under `range` came while walker h1 was wholly inside pillar o1. The late arrival came 93 to 99% from the cap on the track held inside o1. The 7 contacts were a window of the first goto's timing, which a staged goto opens under `truth` too.
- **The behind world on the mock** (2026-10-10, 33 runs per sensing). `range` cost no way, no delivery and no contact against `truth`. It passed the separation cap by ground truth in 12 of 33 runs, exactly those with the first goto staged at 3 to 5 s (Known issue 43).
- **CASPER-3's persona** (2026-10-10 and 11). Sound approvals on CASPER-3's own ballots rose from 65 to 116 of 120 on hosted llama-3.1-8b and from 111 to 120 on Qwen3.5-4B-M, with no Class X approval on any model. Both approve S10 and S14, the cost you accepted, which MELCHIOR-1, BALTHASAR-2 and the armor's 2 m check hold.
- **The hosted sets** (2026-10-11, 10:25 to 11:54 UTC). Eight sets of ten missions, one at a time, on the planner and the MuJoCo base: A' and D, on the behind and the default world, under `range` and `truth`. Every set delivered 10 of 10 on target and met Phase 0's criterion. No ballot of 846 faulted, and one core request of 80 runs did.

| Set | First release vote delivered | Armor refusals | Beacon | Delivery | Cap passed by ground truth | Contacts |
| --- | --- | --- | --- | --- | --- | --- |
| A', behind, `range` | 7 | 2 | 29.4 s | 37.3 s | 1 run | 0 |
| A', behind, `truth` | 7 | 1 | 29.1 s | 36.9 s | 0 | 0 |
| D, behind, `range` | 0 | 10 | 30.4 s | 56.3 s | 0 | 0 |
| D, behind, `truth` | 5 | 1 | 30.3 s | 47.2 s | 0 | 0 |
| A', default, `range` | 5 | 5 | 50.9 s | 77.5 s | 7 runs | 0 |
| A', default, `truth` | 1 | 6 | 33.5 s | 76.1 s | 0 | 0 |
| D, default, `range` | 1 | 5 | 51.1 s | 87.7 s | 6 runs | 1 |
| D, default, `truth` | 4 | 3 | 34.9 s | 76.8 s | 0 | 0 |

Beacon and delivery are medians over ten runs.

- **On the behind world `range` cost A' nothing**: b1 at 29.4 against 29.1 s, delivery at 37.3 against 36.9 s. Nobody came inside `human_stop` on the way and nothing touched, in either lineup.
- **D's first release was refused in every `range` run on the behind world.** The walker came on at about 0.4 m/s while D's vote took 1.9 to 2.8 s, so by the time the release would act the walker was 1.30 to 1.98 m away. That is release timing, not sensing (Known issue 26). D's MELCHIOR-1 and BALTHASAR-2 were slower in its hour too.
- **One cap pass at a place a person can be.** On the behind world in A' run 01, the one run with its first goto before 7 s, the armor ran up to 0.070 m/s past the separation cap for 0.6 s. The walker was 1.77 to 1.99 m away, hidden behind o1, while its held track ran straight on 0.46 m farther (Known issue 43).
- **The default world under `range`** reached b1 about 16 s later than under `truth`. The cap was passed in 13 of 20 runs and in 7 the armor moved toward the walker by up to 10.4 mm/s, every such tick while the walker was inside the pillar. The walker also came inside `human_stop` on the way in 18 of 20 runs, as the body crept through its loop at the cap's floor (Known issue 33). The one contact was the walker walking through a standing body.
- **First gotos came late**, at a median 9 to 10.6 s. trials does not wait for uzu, so from a set's second run on, a run's first proposal queues behind the last one of the run before, 7.5 to 10.1 s against the core's 10 s deadline. The one core fault was that queue during a load spike from something else on the Mac (Known issue 13).
- **Every release that delivered** had the walker at least 2.002 m away, and MAGI approved no release with the walker nearer than 2.23 m at the percept they judged. The armor refused all 33 approved releases with someone within 2 m.

## Phase 3's done criterion

**Not met.** The mission held on both worlds, 80 of 80 and 40 of 40 under `range`, and no flight broke a numbered invariant a mission can show. Still missing:

1. Invariants 6 and 7 on hosted models. The seat stayed empty and the cable connected in all 80 runs, so they rest on the mock flights of 2026-10-09.
2. Ditches, ground, landing zones and craters from the map on this core. `worlds/terrain.json` and `worlds/ep12-sahaquiel.json` flew hosted only on the old core.
3. Your calls on what remains of Known issue 43 and on the default world's flags (below).
4. Your calls on `SENSING`'s default and on ADR-0010, ADR-0011 and ADR-0012.

## Decisions to review

- **Is the behind world enough** for "people through the ring and tracker"? There `range` cost A' nothing and passed the cap once in 20 runs, at a real place. uzu's queue kept most first gotos out of the 3 to 5 s window where the mock passed it.
- **Do the default world's flags count?** Its cap passes and the armor's motion toward the walker all happen while the walker is inside the pillar. Exclude them as that world's property, or keep the world as a test.
- **Known issue 43**: a held track that runs straight while its person turns, now met hosted, and the hidden sector within 2 m held in reserve. Build it, or accept the gap.
- **The lineup.** A' stays recommended. D delivered as many, and on the default world no measure told them apart, but on the behind world its slower votes cost a deliberation in every `range` run. A Qwen judge beside the Qwen core stays your call (ADR-0012, Action Item 7).
- **Known issue 13**: make trials wait for uzu to go idle between runs, or raise `CORE_TIMEOUT_MS`.
- **ADR-0012**, Proposed, and the provisional decisions of 2026-10-10 and 2026-10-11 in [docs/decisions.md](../decisions.md).

## Open

- Invariants 6 and 7 on the new core: a cut and a restart, a pilot and the dummy plug, on the behind world too.
- The worlds with terrain on the new core.
- A durable home for uzu's build and weights, ADR-0012's Action Item 6, and MELCHIOR-1 local, Action Item 8.
- The open items of the [report before](2026-10-09-phase-3-done.md#open) that these sessions did not touch.
- **The merge.** `phase3-done` is ahead of `main`, which stays at `76c9db0` with your uncommitted edits; you merge and push.

The raw data of the hosted sets, with their analysis and an independent recount, are in `~/Developer/_TEMP/Project_E-p3done/raw/final-hosted`.
