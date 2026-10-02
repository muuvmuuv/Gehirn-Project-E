# ADR-0005: The bridge

**Status:** Accepted on 2026-10-02
**Date:** 2026-10-02
**Deciders:** repository owner

## Context

Phase 9 plans a graphical bridge in the look of NERV's command center: the operator's view of MAGI, the core, the seat and the umbilical. It shows the stack and never steers or decides. Its done criterion asks it to follow a full mission live on the Mac, from goto to release, including a MAGI rejection and a cut cable, and that closing it changes nothing in the mission. This ADR extends ADR-0001 with where the bridge runs, and decides how it is built, what it reads, and how it stays out of the safety path.

Four facts shape it. First, every stream between HQ and the field unit is sealed under the unit's `UMBILICAL_KEY` (ADR-0003). An HMAC proves a message to anyone who holds the key, and anyone who holds the key can also seal one, so a bridge that verifies those streams could mint a MAGI approval. Second, the streams lack what the bridge must show: the context carries no umbilical state, and no stream carries MAGI's ballots. Third, Zenoh peers do not forward for one another: a session that dials HQ never hears the field unit, checked on 2026-10-02 with three sessions on zenoh-c 1.10.1, so a bridge linked to HQ alone goes blind exactly when the cable is cut. Fourth, V's `gg` draws on sokol, with Metal on macOS and OpenGL with X11 or Wayland on Linux; the field unit's static musl build (Invariant 9) must not link any of it.

## Decision

**Where.** The bridge is its own executable, `gehirn-bridge`, built from `bridge/`, and runs on its own machine or image, never on the field unit: Vinix has no real time scheduling and a young graphics stack, and the field binary stays free of sokol and its libraries. Which hardware runs the bridge image stays PLAN's open question 5.

**Toolkit.** V's `gg` on sokol: Metal on the Mac, OpenGL on Linux, one codebase. 可決, 否決 and 故障 need a font with CJK glyphs: macOS ships them, and a Linux image adds one such as Noto Sans CJK; `VUI_FONT` overrides the choice, as `gg` already reads it.

**What it reads.** Two watch streams, made for display, beside the control streams of ADR-0003:

| Key | From | Carries | Rate |
| --- | --- | --- | --- |
| `gehirn/<unit>/watch/field` | field unit | percept, active goal, seat, sync, the core's authority, the umbilical's state and internal time left, and the outcomes since the last one, armor refusals included | 10 Hz |
| `gehirn/<unit>/watch/hq` | HQ | each proposal with MAGI's verdict and every ballot (unit, model, vote, why, latency), and each new core fault | per event |

Both are sealed as ADR-0003 seals its streams, JSON with `v` and `seq` and an HMAC SHA256, but under a separate key, `WATCH_KEY`. HQ and the field unit hold both keys; the bridge holds only `WATCH_KEY`. A watch message carries no echo, since nothing acts on it; the bridge shows how long ago each arrived.

**Topology.** The bridge listens on `BRIDGE_ENDPOINT`, and HQ and the field unit each dial it as well as their link. Zenoh redials an absent bridge, so either tier starts without it. The field unit still listens nowhere.

**No safety role.** The bridge declares no publisher. Nothing in HQ or the field unit subscribes to a watch stream. Watch puts drop on congestion at background priority, so a slow or absent bridge never holds up the control streams. Without `WATCH_KEY`, HQ and the field unit publish no watch streams and dial no bridge. The combined binary publishes none either: it has no link to cut, so the done criterion runs against `gehirn hq` and `gehirn field`.

## Options Considered

### How the bridge trusts what it shows

#### Option A: The bridge verifies the control streams with UMBILICAL_KEY

| Dimension | Assessment |
| --- | --- |
| New code in the tiers | None |
| What a stolen bridge key does | Approves goals and keeps the cable connected |
| What the bridge can show | Only what the control streams carry: no ballots, no umbilical state |

**Pros:** the least code, and the bridge sees exactly what the field unit sees.
**Cons:** a display machine holds the key that stands in for MAGI's approval, so Invariant 3 would rest on the bridge machine's security, and the streams still lack the ballots and the cable's state.

#### Option B: Ed25519 signatures on the control streams

| Dimension | Assessment |
| --- | --- |
| New code in the tiers | Signing and verifying in `wire`, two key pairs per unit |
| What a stolen bridge key does | Nothing, it holds only public keys |
| What the bridge can show | As option A |

**Pros:** any number of observers verify and none can forge.
**Cons:** it replaces the integrity scheme of an accepted ADR for the sake of a display, doubles the keys per unit, and still leaves the ballots and the cable's state off the wire.

#### Option C: Watch streams under their own key

| Dimension | Assessment |
| --- | --- |
| New code in the tiers | Two publishers and two message types in `wire` |
| What a stolen bridge key does | Forges what a bridge displays, nothing that acts |
| What the bridge can show | Everything Phase 9 lists |

**Pros:** the bridge stays outside the control path by construction, and each tier publishes what the operator needs, shaped for display.
**Cons:** a third key, and a second copy of the field's state on the network at a fifth of the context's rate.

### How the bridge reaches both tiers

#### Option A: The bridge dials HQ

**Pros:** one endpoint to configure.
**Cons:** HQ does not forward the field unit's messages, so the bridge loses the field when HQ dies, the one moment the cable's countdown matters.

#### Option B: A Zenoh router between the three

**Pros:** each process dials one router, and Zenoh routes.
**Cons:** a new service to install and run, and a failed router blinds the bridge and cuts the cable at once.

#### Option C: The bridge listens and both tiers dial it

**Pros:** the bridge hears each tier directly, whatever happens to the other, the field unit keeps listening nowhere, and nothing new needs installing.
**Cons:** one more endpoint in each tier's configuration.

### Toolkit

#### Option A: V's gg on sokol

**Pros:** in vlib, so nothing to install; native on the Mac and on Linux, and drawn by the same V code.
**Cons:** immediate mode drawing, so every panel is laid out by hand.

#### Option B: A browser page served by a tier

**Pros:** any device with a browser shows it.
**Cons:** an HTTP server becomes a new door into a tier, and a kiosk image needs a browser.

## Trade-off Analysis

The bridge is worth having only if it can never become a way to act. Option C for trust keeps every key that stands for an approval or a pulse off the display machine, and option C for topology keeps the field unit from listening for anyone, so the bridge adds no path into either tier. What it costs is configuration: a third key and an endpoint on each tier, and a watch copy of the field's state on the network.

The watch streams also decouple the display from the control format. The control streams can change for safety reasons without breaking the bridge, and the bridge can ask for more, such as the core's last fault or the dummy plug's sync, without touching what the field unit acts on.

## Consequences

Easier: the operator sees MAGI's ballots and the cable's countdown, which no log shows in one place today; a bridge crash, a slow bridge or no bridge at all changes nothing in a mission.

Harder: three new variables, `WATCH_KEY` and `BRIDGE_ENDPOINT` on HQ and the field unit and both on the bridge, plus `UNIT_ID` there. The field loop has to hand the pump its umbilical state and authority, which the control stream does not carry. A second executable joins the build and the checks, and it is the first code here that opens a window, so its rendering is checked from frames that `gg` saves (`VGG_SCREENSHOT_FRAMES`) rather than by a person watching.

Invariant 1, Invariant 3 and Invariant 6 hold: the bridge holds no body, no key that approves and no key that pulses. Invariant 9 holds: the field binary links nothing new, and the bridge runs elsewhere. Invariant 10 holds: nothing safety relevant waits on the bridge.

Revisit when an operator needs to act from the bridge, such as an e-stop or a re-arm after an eject (Known issue 5). That is a control path with its own key and its own ADR, never a change to this one's read-only bridge.

## Action Items

1. [x] `wire` seals and opens the two watch messages under `WATCH_KEY`; HQ and the field unit publish them and dial `BRIDGE_ENDPOINT` when the key is set (Phase 9 task 2).
2. [ ] `gehirn-bridge` in `bridge/`, with its panels drawn from a state that table tests cover (Phase 9 task 3).
3. [ ] Follow a mission on the Mac against the mock, with a rejection and a cut cable, then against the hosted lineup (Phase 9 task 4).
