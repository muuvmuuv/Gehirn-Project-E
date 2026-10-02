# ADR-0004: The pulse outlives a core fault

**Status:** Accepted on 2026-10-02
**Date:** 2026-10-02
**Deciders:** repository owner

## Context

The umbilical stays connected while HQ pulses it. ADR-0003 kept the rule of the single process: HQ pulses once per deliberation that ends in a proposal, so a core that faults sends no pulse. A core that keeps faulting therefore cuts the cable after `UMBILICAL_GRACE_MS`, and the unit holds once `INTERNAL_BUDGET_MS` is spent, although HQ, MAGI and the link all work. Phase 1 task 6 asked whether that should stay.

A core faults for reasons outside the stack: qwen3-8b's single OpenRouter provider answers HTTP 429 under load (Known issue 13), a hosted model misses `CORE_TIMEOUT_MS`, or a reply cannot be read. An outage of the core's provider longer than the grace cuts the cable today, and one longer than the grace plus the budget, under six minutes at the defaults, stops the unit.

What the umbilical guards is the unit acting without HQ's oversight. Without HQ there is no quorum, so nothing irreversible may happen (Invariant 6). A faulting core is a different failure: HQ is there and MAGI would judge any proposal, but no proposal comes.

## Decision

HQ pulses after every deliberation, including one in which the core faults. The pulse now means that HQ's deliberation ran on a fresh snapshot from the field; it no longer says that the core proposed anything. A faulting deliberation still sends no goal, so MAGI approves nothing and the unit keeps its last approved goal, which the armor still restrains. HQ still prints a fault once until the fault changes. A deliberation that hangs, such as a CL1 core without a deadline (Known issue 11), still stops the pulse, as does a dead HQ or a broken link.

This supersedes the part of ADR-0003's decision on the pulse that ties it to a proposal. The wire is unchanged: the same pulse message, sealed and checked the same way.

## Options Considered

### Option A: A core fault stops the pulse

| Dimension | Assessment |
| --- | --- |
| A provider outage of the core | Cuts the cable after the grace, holds the unit after the budget |
| A dead HQ | Cuts the cable |
| Signal to the operator | The unit itself holds |
| Code | As it is |

**Pros:** a core that stays broken forces the unit to hold, which fails toward the safest state without anyone watching.
**Cons:** it treats a missing proposal as missing oversight, so a rate limit at the core's provider stops a unit that HQ still supervises.

### Option B: HQ pulses after every deliberation

| Dimension | Assessment |
| --- | --- |
| A provider outage of the core | The unit keeps its last approved goal while HQ runs |
| A dead HQ | Cuts the cable |
| Signal to the operator | One `hq: core fault:` line per distinct fault |
| Code | One branch in `hq` |

**Pros:** the cable means what it guards, HQ's oversight, and an outage of one hosted model no longer stops the unit.
**Cons:** a core that stays broken leaves the unit on its last goal indefinitely, and the operator learns of it only from HQ's output.

### Option C: A separate health signal for HQ

| Dimension | Assessment |
| --- | --- |
| A provider outage of the core | As option B |
| A dead HQ | Cuts the cable |
| A hung deliberation | Keeps the cable connected |
| Code | A second thread or a liveliness token |

**Pros:** HQ's health is reported apart from any deliberation.
**Cons:** it reports the process rather than the deliberation, the weakness ADR-0003 rejected the liveliness token for.

## Trade-off Analysis

The pulse should mean what the umbilical guards. Option A makes the unit hold on a failure that leaves oversight intact, and option C keeps the cable connected on one that ends it. Option B ties the pulse to the deliberation itself, so it stops exactly when HQ can no longer judge, and keeps running when HQ judges but has nothing to judge.

The cost is the unattended case. Under option A a core that never recovers ends in a hold; under option B the unit stays on its last approved goal, a reversible one, since an irreversible act is never a standing goal, and the armor keeps limiting speed, separation and fence. That is acceptable while the body is a simulator and a person watches HQ's output, and it is the point to revisit once a real body runs unattended.

## Consequences

Easier: a rate limit or an outage at the core's provider no longer cuts the cable, and the cable's state means one thing, whether HQ still deliberates.

Harder: a core fault no longer shows in the unit's behavior, only in HQ's output. HQ prints a repeated fault once and the journal records none (Known issue 10), so a long outage is one line; the bridge of Phase 9 should show the core's state.

Invariant 6 holds: without HQ there is still no pulse and no quorum, and with HQ but without a proposal MAGI approves nothing. Invariant 3 and Invariant 5 are untouched. Invariant 8 holds: a core with nowhere new to go keeps no share beyond the last approved goal's. Phase 1's done criterion is unaffected, since killing HQ still cuts the cable.

Revisit when a real body runs without a person watching HQ, or when HQ gains a way to escalate a core that stays broken, such as a hold after a fault budget of its own.

## Action Items

1. [x] `hq` pulses after a deliberation in which the core faults, and a test shows that it approves nothing then (Phase 1 task 6).
2. [ ] The Phase 9 bridge shows the core's state, so a fault that lasts is seen.
