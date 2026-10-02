# ADR-0003: LCL over the wire

**Status:** Accepted on 2026-10-02; the pulse's tie to a proposal superseded by ADR-0004, and the bridge's use of these streams by ADR-0005
**Date:** 2026-10-02
**Deciders:** repository owner

## Context

`main.v` runs HQ and the field loop in one process, and three kinds of value cross between them on V channels. The field loop pushes the newest `lcl.Context` (capacity 1, a new one replaces the stale one) and every `lcl.Outcome` (capacity 32, dropped when full). HQ sends `lcl.HqMsg` (capacity 8): a goal with MAGI's verdict, the `alive` flag that pulses the umbilical, and a note for the field loop to print. Phase 1 puts HQ and the field unit on separate machines linked through Zenoh, as ADR-0001 plans, so these channels become network streams. [zenoh-c](https://github.com/eclipse-zenoh/zenoh-c) is the client library, release 1.10.1 as of 2026-10-02, reached through V's C interop.

Measured on 2026-10-02 with `x.json2`: a Context of the default scene, with a goto and a why of 76 characters, encodes to 495 bytes, and an Outcome to 66. At the field's 50 Hz that is about 25 KB/s from field to HQ. HQ sends under one message per second.

Four things change once a channel is a link:

1. Anyone can write. Only the two tiers can write a channel inside one process, but any session that reaches the network can put on a Zenoh key. A goal on the wire says MAGI approved it, so an open goal stream lets anyone mint an approval, and Invariant 3 would rest on the armor alone. A pulse keeps the umbilical connected, so a forged one keeps the unit going past its budget, against Invariant 6.
2. The tiers stop sharing a clock. Every `t_ms` is the clock of the side that set it. No code compares a timestamp from one side with the other side's clock (checked on 2026-10-02), and that has to stay so.
3. Messages arrive late, in a burst after a stall, or as a replay, and the two sides may run different builds during an update.
4. Zenoh runs its callbacks on its own threads. V 0.5.2 links the Boehm collector, which has to know every thread that allocates: V registers the threads it spawns, and a foreign thread has to register itself, as `vlib/coroutines` does with `GC_register_my_thread`. A V callback that allocates on a Zenoh thread races the collector.

The field loop never waits on the network (CONTRIBUTING, Concurrency 4), field tier code follows Invariant 9, and the Python tools use the standard library only (CONTRIBUTING, Python tools 2).

## Decision

**Encoding.** A message is one JSON object, encoded and decoded with `x.json2` and put with the Zenoh encoding `application/json`. Its first field is `v`, the schema version, now 1, and its second is `seq`; the stream's fields follow under the names of the `lcl` types. A receiver drops a message with a `v` it does not know and says so once per version. A field that a receiver may ignore can be added under the same `v`; removing, renaming or redefining a field bumps it. A payload over 64 KiB is dropped unread.

**Key expressions.** Every stream lives under `gehirn/<unit>/`. `<unit>` comes from a new variable, `UNIT_ID`, default `eva01`: 1 to 32 lowercase ASCII letters, digits and hyphens, refused at startup otherwise, because `*`, `$`, `?`, `#` and `/` are syntax in a key expression and a unit named `*` would hear every unit.

| Key | From, to | Fields after `v` and `seq` | Congestion | Priority | Receiver queue |
| --- | --- | --- | --- | --- | --- |
| `gehirn/<unit>/context` | field to HQ | `percept`, `goal`, `seat`, `sync` | drop | data | ring of 1, the newest |
| `gehirn/<unit>/outcome` | field to HQ | `outcome` | drop | data high | 32, in order |
| `gehirn/<unit>/goal` | HQ to field | `goal`, `echo_ms` | block | interactive high, express | 8, shared with the pulse, in order |
| `gehirn/<unit>/pulse` | HQ to field | `echo_ms` | drop | interactive high | 8, shared with the goal |

Every stream uses Zenoh's default reliable channel; zenoh-c 1.10.1 still marks the per publisher reliability option unstable. Reliable means hop to hop over a reliable link: Zenoh resends nothing after a reconnect, so what was queued when a link dropped is lost. Loss is decided by congestion control and the receiver's queue, which repeat the channels of today: the field drops a context or an outcome rather than wait, and HQ, which may wait, blocks on a goal, until Zenoh closes a session that stays blocked for 5 s. A goal outranks the 50 Hz context in the send queue.

The context leaves out `mission` and `memory`, because HQ owns both: `MISSION` becomes an HQ variable and the journal is HQ's. Only approved goals travel, because the field acts on nothing else; a rejected one, and every note, stay on HQ as its own status output. Phase 9 adds `gehirn/<unit>/verdict` for the bridge.

**The pulse.** HQ puts a pulse wherever `hq` sets `alive` today, once per deliberation that ends in a proposal, and the field pulses the cable for each pulse it accepts. No Zenoh liveliness token stands in for it. Phase 1 task 6, whether a core fault should keep stopping the pulse, stays open and changes nothing on the wire.

**Integrity and freshness.** Each unit has a link key, a new variable `UMBILICAL_KEY` of 64 hex digits (32 random bytes), set on both machines and kept in `.env`. Every message carries an HMAC SHA256 under that key as its Zenoh attachment, computed over the key expression, a newline and the payload. A receiver checks it with `hmac.equal` before anything else and drops a message that fails, as `plug.listen` drops a foreign pilot, so JSON from the network is parsed only once it is authenticated. A tier that talks to the other over Zenoh refuses to start without a valid key (CONTRIBUTING, Configuration 2).

`seq` grows by one per message and starts at the sender's start time in microseconds, so it keeps growing across restarts. A receiver drops a `seq` at or below the last one it accepted on that key. HQ's messages also carry `echo_ms`, the `t_ms` of the newest percept HQ has received, and the field drops a goal or a pulse whose `echo_ms` lies in its future or more than `UMBILICAL_GRACE_MS` in its past. The field judges freshness by its own clock, so the machines need no clock sync, and a message captured more than a grace ago cannot be replayed.

**Threads.** `hq` and the field loop keep their channels and capacities. On each side a transport moves values between those channels and Zenoh: it encodes, signs and puts what its loop pushed, and checks, decodes and pushes what Zenoh delivered. Subscribers receive through zenoh-c's channel handlers, a ring for the context and FIFOs otherwise, which a V thread drains, so no V code runs on a Zenoh thread. That thread hands each value on with `try_push` and drops it when the loop's channel is full, as today's senders do, because a full FIFO blocks the Zenoh thread that feeds it. The field loop's channel operations stay `try_push` and `try_pop`.

## Options Considered

### Encoding

#### Option A: JSON with a version field

| Dimension | Assessment |
| --- | --- |
| Size | 495 bytes per context, about 25 KB/s at 50 Hz |
| New code | None: `x.json2` already encodes every `lcl` type |
| Python tools | Read it with the standard library |
| In a capture | Readable as is |

**Pros:** no new codec on the safety path, the parser the stack already trusts, and a capture reads as text.
**Cons:** the largest encoding of the three, and every decode allocates.

#### Option B: CBOR

| Dimension | Assessment |
| --- | --- |
| Size | Smaller, not measured |
| New code | vlib 0.5.2 ships `encoding.cbor`, untried here |
| Python tools | No CBOR in the standard library, so a tool needs a package |
| In a capture | Needs a decoder |

**Pros:** smaller messages and binary floats.
**Cons:** an untried codec on the safety path, and the tools could no longer read a stream without breaking their standard library rule.

#### Option C: Protocol Buffers or FlatBuffers

| Dimension | Assessment |
| --- | --- |
| Size | Smallest |
| New code | Code generation or a C library, since vlib has neither |
| Python tools | Need a package |
| In a capture | Needs the schema |

**Pros:** typed schema evolution and compact messages.
**Cons:** a generator or a C library for five small structs, plus a package for every tool.

### The pulse

#### Option A: A Zenoh liveliness token

| Dimension | Assessment |
| --- | --- |
| Reports | That HQ's Zenoh session lives |
| Hung deliberation | Token stays, cable stays connected |
| Core fault | Token stays, unless HQ undeclares it on every fault |
| Traffic | None while nothing changes |

**Pros:** no periodic messages, and Zenoh notices a dead session by itself, within its default lease of 10 s.
**Cons:** it reports the process, not the deliberation, so a hung `hq` thread or a faulting core keeps the cable connected exactly when it should run down. Fixing that means declaring and undeclaring the token per deliberation, a message stream with extra steps.

#### Option B: A pulse message per deliberation

| Dimension | Assessment |
| --- | --- |
| Reports | That a deliberation ended in a proposal, as `alive` does today |
| Hung deliberation | No pulse, cable runs down |
| Core fault | No pulse, as today |
| Traffic | One small message per deliberation |

**Pros:** today's meaning of a sign of life, so the umbilical, its spans and its tests stay as they are. The bridge reads the same stream.
**Cons:** periodic traffic, and a reader that joins late waits up to one period.

### Trust on the link

#### Option A: Trust the network

**Pros:** nothing to build.
**Cons:** anyone who reaches the network can approve a goal or keep the cable connected. Rejected.

#### Option B: Zenoh's TLS with mutual authentication and access control

| Dimension | Assessment |
| --- | --- |
| Integrity | Per hop, on every node configured for it |
| Without its configuration | Accepts everything |
| Confidentiality | Yes |
| In process fake | Cannot exercise it |

**Pros:** encryption as well, no cryptography in gehirn, and every node enforces its own rules, so the field's session can admit goals only from HQ's certificate.
**Cons:** the forged approval is closed only while certificates and access rules are right on every node, routers included, and a node without them accepts everything. The in process fake of Phase 1 task 2 cannot test it, and zenoh-pico, for the Phase 5 microcontroller, has TLS only as a build option.

#### Option C: An HMAC per message, with a sequence and an echo

| Dimension | Assessment |
| --- | --- |
| Integrity | End to end, whatever routers sit between |
| Without its configuration | Refuses to start |
| Confidentiality | No |
| In process fake | Table tests cover every check |

**Pros:** it fails closed, it holds end to end, it needs only `crypto.hmac` and `crypto.sha256` from vlib, and the same scheme signs the pilot datagrams of Phase 1 task 5.
**Cons:** percepts, including where people are, cross the network in the clear. Two machines hold the same key. Right after a receiver restarts, a replay of a message from within the last grace passes once.

#### Option D: Ed25519 signatures

**Pros:** only HQ holds the signing key, and the field holds a public key.
**Cons:** each unit has its own link key anyway, so a key taken from one field unit forges nothing for another. Signatures cost more than an HMAC and buy nothing with one HQ per unit.

## Trade-off Analysis

The wire must not change what the invariants rest on, and each choice follows from that. The pulse keeps the meaning the umbilical was built and tested for, where a liveliness token would report a weaker fact under the same name. The HMAC closes the forged approval end to end and fails closed, where Zenoh's access control closes it per hop and fails open. JSON keeps the one parser the stack already trusts, and the version field sits in the payload rather than the key, so a peer on another version is heard and says why it drops, instead of hearing nothing.

The cost is confidentiality. Percepts say where people are, and they cross the link in the clear. On a private field network that is acceptable for the proof of concept, and Zenoh's TLS can be added under the HMAC later without changing a byte of the payload. The other cost is a replay right after a restart. The echo bounds it to one grace for HQ's messages, and the armor checks every goal against the live percept, so a replayed release still needs the scene to allow it.

## Consequences

Easier: `hq` and the field loop stay as they are, and the in process fake of Phase 1 task 2 is the channels they use today. The bridge of Phase 9 subscribes to the same keys. Topology, peer to peer or through a router once the bridge joins, is configuration and plays no part in safety, because every message is checked end to end. The field can measure how old a goal's percept is on its own clock, which gives Known issue 9 a number.

Harder: two new variables, `UNIT_ID` and `UMBILICAL_KEY`, on both machines, with rows in the README and `.env.example` once Phase 1 task 3 reads them. Whoever holds a unit's link key can put goals to it, and only the armor stands in the way. Two processes print two logs, while `tools/trials.py` reads one, so trials keep flying the combined binary (Phase 1 task 4). A Python tool cannot subscribe without a Zenoh package, so a capture tool is written in V or uses Zenoh's own tools. A sender whose clock jumps back across a restart starts below its last `seq`, and its messages are dropped until the receiver restarts too; for HQ that cuts the cable, which fails toward hold.

Invariant 3 holds: only a holder of the link key can put a goal. Invariant 5 holds: the field runs `Armor.permits` on every goal it accepts. Invariant 6 holds: the pulse keeps its meaning, and a forged, replayed or stale pulse is dropped. Invariant 9 needs zenoh-c on aarch64 musl: release 1.10.1 ships builds for `aarch64-unknown-linux-musl`, and on 2026-10-02 the `zenoh` module's tests passed as a static aarch64 musl binary on Alpine. The HMAC uses vlib only. Invariant 10 holds: a late or lost message makes the field hold, never act.

Revisit when a measurement makes JSON too costly, such as CPU on the field computer or bandwidth on a radio link; when the link leaves a private network, which adds Zenoh's TLS; or when more than one HQ may serve a unit, since `seq` assumes one sender per key.

## Action Items

1. [x] Phase 1 task 2: the `zenoh` module receives through zenoh-c's channel handlers, never through V callbacks on Zenoh threads, and links zenoh-c for aarch64 musl. V names zenoh-c's structs without laying them out, so the C compiler takes their layout, unstable fields included, from the header shipped with the library.
2. [x] Phase 1 task 3: the four streams of the table; `UNIT_ID` and `UMBILICAL_KEY` in `load_config`, the README and `.env.example`; table tests for the HMAC, `seq`, `echo_ms`, version and size checks; and `lcl.HqMsg`'s doc, which still names liveliness.
3. [x] Phase 1 task 5: pilot datagrams carry the same HMAC and `seq`, under each pilot's key. Without an echo, their `seq` is the pilot's clock, which the plug checks against its own within 500 ms.
