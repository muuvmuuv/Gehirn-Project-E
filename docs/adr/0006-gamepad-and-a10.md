# ADR-0006: The gamepad and the A10 back channel

**Status:** Proposed
**Date:** 2026-10-03
**Deciders:** repository owner

## Context

Phase 2 is done when a pilot flies the mission from a gamepad and feels contact. Today a pilot is `tools/pilot.py`: it sends UDP datagrams to the field unit's `PLUG_LISTEN`, each a JSON line signed with HMAC SHA256 under `PILOT_KEY` (ADR-0003, action item 3), and hears nothing back. In canon the A10 nerve connection carries feeling both ways between pilot and Eva; here the pilot has eyes on the bridge at best and nothing in the hands. Phase 2 task 1 names the game controller API of `vlang/sdl`, and task 2 asks the field unit to send contact, human proximity and sync back for the gamepad to turn into rumble.

Five facts shape the decision, measured on 2026-10-02 unless they say otherwise.

1. `vlang/sdl` has no tags, only one branch per SDL minor version. Branch 2.32.0, at a65140b, holds about 23.4k lines of V under MIT; master tracks SDL3. A game controller with rumble needs 14 functions of SDL2's API, from SDL 2.0.9 on. A binding of our own of those 14, 113 lines, `vlang/sdl` 2.32.0 and SDL3's Gamepad API each built with `v -W` without a warning and listed 0 controllers on the Mac, where Homebrew's sdl2-compat runs SDL2 programs on SDL3, and on Alpine 3.22 aarch64 musl with `sdl2-compat-dev`. Starting and stopping SDL's controller subsystem took 0.165 s.
2. The plug is the one door for pilot input. Outside tests only `plug` and `core/cl1.v` import `net` (CONTRIBUTING, Modules 3), and the field unit listens on `PLUG_LISTEN` and dials nothing toward the pilot. A reply from that listening socket to a datagram's source address came back 200 times out of 200 on loopback, p50 80 µs and p99 147 µs.
3. `body.Sim` reports contact within 0.25 m of anything but a beacon, while the armor takes away all motion toward a solid within 0.35 m (`solid_keep`). So a pilot leaning into the pillar almost never touches it; the walking human running into the body is what sets contact. What the pilot runs into is the armor, measurable as the gap between the command into `Armor.drive` and the velocity it sends. Human proximity lives in the armor's private `nearest_human`, judged against `human_slow` and `human_stop`.
4. A pilot who sends zero still holds the seat, and while the seat is held the core's share stays at or below the ceiling of 80%. A gamepad left on the desk would hold the seat for good. An eject latches until the process restarts (Known issue 5), so an eject by mistake ends the mission.
5. The plug judges a datagram's freshness by the pilot's clock (Known issue 4). An echo needs a channel back to the pilot, which does not exist yet.

## Decision

**The gamepad.** A second executable for the pilot's machine, `gehirn-gamepad`, built from `gamepad/`. It reads a game controller through SDL2's game controller API and a binding of our own, `gamepad/pad.c.v`, the only file that links SDL. It starts SDL with no window and without SDL's signal handlers (`SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS`, `SDL_NO_SIGNAL_HANDLERS`), so it runs in a terminal and Ctrl-C ends it. At 50 Hz the left stick becomes `u`: zero inside a deadzone of 0.15, then rising to the armor's manned cap, `armor.Limits.v_max`, at full tilt, with SDL's downward y axis flipped. The datagrams are those of `tools/pilot.py`, sealed under `PILOT_KEY` for `PILOT_ID` and sent to `PLUG_ADDR`. Everything but the SDL calls lives in `plug/pilot.v` as pure functions with table tests, so no test needs SDL, and `plug.Pilot` holds the gamepad's socket, so `net` stays inside `plug`.

**The guard.** LB is a dead man's switch: the gamepad sends only while it is held. Let go and the field unit sees no datagram for 500 ms, empties the seat, and the dummy plug or the core takes over, as when any pilot leaves. Back and Start held together for one second eject; the count starts over whenever either is let go, and it starts only after both have been seen up, so a button stuck down from the start never ejects. An eject sends whether LB is held or not.

**The back channel.** `plug.listen` answers every datagram it accepts with the newest `lcl.Feel`, from its listening socket to the datagram's source:

| Field | Meaning |
| --- | --- |
| `t_ms` | the field unit's clock |
| `contact` | the body touches something |
| `near` | 0 with no human inside `human_slow`, 1 at `human_stop`, from `Armor.closeness`, so no limit is copied |
| `sync` | the seat's sync ratio |
| `strain` | m/s the armor took off the blended command |

A reply is a JSON line `{"v":1,"feel":{...}}`, a newline and 64 hex digits of HMAC SHA256 under `PILOT_KEY` over `feel`, a newline and the line. The prefix keeps a datagram from ever verifying as a reply under the one key. A reply never reads as a datagram: as sent it fails a datagram's HMAC, and with the prefix moved into its line it verifies, but that line is no datagram. The field loop pushes a `Feel` every tick into a channel of capacity 1 with `try_push` and `try_pop`, newest wins, so it never waits on the plug (CONTRIBUTING, Concurrency 4). The gamepad drops a reply that fails its HMAC or whose `t_ms` does not grow.

**No safety role.** The gamepad turns a feel into rumble: contact runs both motors at full, a human's closeness the high frequency motor up to three quarters, and strain the low frequency motor up to half. Each rumble request lasts 100 ms, so rumble stops by itself once replies stop. Nothing on the field unit waits for or acts on a reply, and a reply that cannot be sent is dropped.

## Options Considered

### The controller library

#### Option A: `vlang/sdl` 2.32.0

| Dimension | Assessment |
| --- | --- |
| Code | About 23.4k lines from a third party |
| Pin | No tags; a tarball of a65140b checked by sha256, though GitHub does not promise stable archives |
| Build | A `just sdl` recipe into `thirdparty/`, and `-path` on every build |

**Pros:** the whole of SDL2 in V, kept by the V organization, with examples.
**Cons:** two orders of magnitude more code than the 14 functions in use, a pin that may break when GitHub rebuilds an archive, and an upstream whose master has moved on to SDL3.

#### Option B: Our own binding of SDL2's game controller API

| Dimension | Assessment |
| --- | --- |
| Code | About 110 lines, read in one review |
| Pin | None; SDL2 comes from the system: Homebrew sdl2-compat, Alpine `sdl2-compat-dev`, Debian `libsdl2-dev` |
| Build | `v -prod -o gehirn-gamepad gamepad/` |

**Pros:** nothing to fetch, SDL2's API is frozen, and sdl2-compat carries it onto SDL3 where a system has only SDL3.
**Cons:** we keep the binding, and every SDL feature beyond controllers and rumble, such as touchpads or trigger rumble, means binding more.

#### Option C: SDL3's Gamepad API

**Pros:** the current API, and it built on Alpine.
**Cons:** fewer distributions ship SDL3 than SDL2, for example Ubuntu 24.04 (not checked), and SDL3 runs SDL2 programs through sdl2-compat anyway, so SDL2's API reaches more systems.

### The back channel

#### Option A: A signed UDP reply from `plug.listen`

| Dimension | Assessment |
| --- | --- |
| New sockets or ports | None |
| New importers of `net` | None |
| Latency | 80 µs p50 on loopback |
| Who hears it | The source of an accepted datagram, nobody else |

**Pros:** it uses the one door the pilot already has, reaches the pilot through NAT because it answers the pilot's own datagram, and needs vlib only on the field unit. It answers only datagrams that passed the HMAC, the pilot ID, the replay and the freshness checks, so without the key nobody can make the field unit send anything anywhere.
**Cons:** it comes only as often as the pilot sends, and only the seated pilot hears it.

#### Option B: A Zenoh stream, `gehirn/<unit>/feel`

**Pros:** the transport the tiers already use, with a subscriber per listener.
**Cons:** the field unit would need a third endpoint and the gamepad would link zenoh-c, and a key to seal it with: `UMBILICAL_KEY` approves goals and must not reach a pilot's machine.

#### Option C: The watch stream of ADR-0005

**Pros:** it exists and carries contact, the percept and sync.
**Cons:** 10 Hz is coarse for contact, it needs `WATCH_KEY` on the pilot's machine, and ADR-0005 rests on nothing acting on it.

### Keeping the seat honest

#### Option A: Send all the time

**Pros:** the simplest gamepad.
**Cons:** a gamepad on the desk holds the seat and caps the core's share for good, as fact 4 says.

#### Option B: Send while the stick is off center

**Pros:** no button to hold.
**Cons:** a pilot who centers the stick to stop the body leaves the seat, and the dummy plug or the core starts moving it.

#### Option C: LB as a dead man's switch

**Pros:** holding the seat is a deliberate act, and letting go hands over through the seat's existing 500 ms timeout, with no new rule on the field unit.
**Cons:** one finger is always busy.

## Trade-off Analysis

The gamepad is a pilot, nothing more, so it should reach the field unit the way a pilot already does and change nothing there that safety rests on. The UDP reply does that: no new door, no new key, and nothing on the field unit acts on it. Our own binding costs a hundred lines we keep, against twenty thousand we would pin by an archive's checksum; SDL2's API is frozen, so the hundred lines will not drift. The dead man's switch and the strict eject cost the pilot a finger and a second, and protect the two outcomes that are hard to undo here: a seat held by nobody, and an eject that latches.

## Consequences

Easier: a pilot flies with a stock controller and feels the armor push back. Every reply carries the field unit's clock, so the echo that removes the pilot's clock from the freshness check (Known issue 4) needs no new channel: a later datagram version can echo `t_ms` and the plug can judge it on its own clock. That change is out of scope here and would supersede ADR-0003's action item 3.

Harder: building the gamepad needs SDL2's headers and library, which `just check` never builds, so the checks still run without SDL. Reading a real controller and its rumble cannot be tested without one; on 2026-10-03 no controller was attached, so both are unverified, as is whether macOS hands controller input to a process without a window. On Linux the user needs access to `/dev/input` and hidraw for input and rumble, which udev rules grant (not checked). A plug that drops replies under load costs rumble, nothing else.

Invariant 1 holds: `Armor.closeness` reads a percept and returns a number, and the gamepad holds no body. Invariants 7 and 8 hold: the seat, the dummy plug's bench and the core's share follow the same rules; the dead man's switch only makes an idle pilot leave the seat sooner. Invariant 9 holds: the field unit's part uses vlib only, and the gamepad runs on the pilot's machine; SDL2 builds for aarch64 musl as well. Invariant 10 holds: rumble expires on its own, and the seat's timeout and the eject remain the field unit's rules on its own clock.

Revisit when a pilot needs more than rumble, such as force feedback on triggers, or when Known issue 4's echo lands.

## Action Items

1. [x] `lcl.Feel`, `Armor.closeness`, `plug.listen`'s reply and the field loop's push (Phase 2 task 2).
2. [ ] `plug/pilot.v`: sealing datagrams, opening replies, the stick, the guard and rumble, with table tests.
3. [ ] `gehirn-gamepad` in `gamepad/`, the `just gamepad` recipe, and `--probe` to list controllers (Phase 2 task 1).
4. [ ] Fly the mission from a physical controller and feel contact, Phase 2's done criterion.
