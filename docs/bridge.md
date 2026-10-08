# The bridge

![The bridge during the refused release on 2026-10-05: MELCHIOR-1 on gpt-oss-20b and BALTHASAR-2 on Jev vote 否決 with the human 1.04 m from the body, while CASPER-3 on llama-3.1-8b-instruct votes 可決, and the mark's contacts in the header show the three votes](../assets/media/bridge.png)

The frame comes from a `just lineup=magi demo-record` run on 2026-10-05: MAGI on gpt-oss-20b, Jev and llama-3.1-8b-instruct, hosted on OpenRouter and TypeSafe, judging the mock's scripted core, which proposes the release whatever the human does.

`./gehirn-bridge` is the operator's view of one unit, drawn in the on screen language of NERV's command center. Everything on it but the boot sequence shows the stack's state.

## Run it

The bridge reads `UNIT_ID`, `WATCH_KEY` and `BRIDGE_ENDPOINT`. Next to a run of [HQ and the field unit apart](running.md#hq-and-the-field-unit-apart), in a second shell with the same `WATCH_KEY` exported:

```sh
just bridge
export WATCH_KEY=<the key the run printed>
./gehirn-bridge
```

Its window is its own: 1280 by 800, without the operating system's title bar or frame, and fixed in size. Drag it anywhere to move it, and quit it with Esc, or Cmd-Q on the Mac; on Linux the window manager moves it, most on Alt and drag. Its icon in the Dock or the task bar is gehirn's mark, whose contacts follow the votes as the header's do.

It boots for under three seconds through its own listening address and three lines from the show, and the boot screen and the footer say it is a fan project, not affiliated with khara or Gehirn Inc. Its fonts are built into the binary ([bridge/fonts](../bridge/fonts/README.md)); `VUI_FONT` names a fallback for glyphs they lack, such as Japanese in a model's why, where macOS's Arial Unicode is missing, as on Linux.

## The panels

- **MAGI** in the canon's three blocks around a center, BALTHASAR•2 above CASPER•3 and MELCHIOR•1. A unit flickers blue with 審議中 while it deliberates and turns 可決, 否決 or 故障 as its ballot lands, with its model, latency and why; 決議 holds the verdict and its tally, or NO VERDICT for a vote that a cut cable or a dropped verdict ended, and 提訴 the proposal with a status block: CODE counts the proposals put to the vote, FILE is the verb, EXTENTION (misspelled as in the show) the slowest ballot in milliseconds, EX_MODE the seat, PILOT, DUMMY, BENCHED or OFF, and PRIORITY AAA when every unit must approve, AA for a majority. A 否決 flashes hazard stripes. A vote staged live on the mock, a ballot it forced or a proposal it was told to make by `just stage`, reads STAGED ON THE MOCK between hazard stripes, between 提訴 and 決議 ([Scenes](scenes.md#staging-live)).
- **活動限界**, the umbilical, in seven segment digits with centiseconds: the whole budget and 外部 while the cable holds, a dim AWAITING HQ until HQ's first pulse reaches the field unit, an amber UMBILICAL SIGNAL LOST with the seconds since HQ's last pulse once HQ has been silent for 5 s, an EMERGENCY overlay for 3 s as the field unit goes to internal power, then 内部 counting down, red and blinking for the last 30 s, and NO FIELD DATA once the field unit's views stop, since only they tell of the cable.
- **シンクロ率**, the harmonics: the sync ratio and the core's authority over the last 30 s against the 30% 絶対境界線, with the seat and a benched dummy plug.
- **The scene** as a radar fitted to everything it has shown: the body's trail and velocity, range rings a meter apart, brackets on a goto's target, each human's 0.7 m and 2 m rings from the armor and the distance to the nearest, a thin line along each moving obstacle's velocity, each ditch as a dark pit, ground that slows the body as a blue wash with the share of its speed the body keeps there, as LAKE 50%, and where a falling object will land as a red ring counting down to its landing, which blinks through its last 5 s and then becomes the crater's pit.
- **The core** with its active goal and a 故障 strip of its faults, **armor refusals** as 拒否, **outcomes**, and a header with gehirn's mark, whose three contacts light up with each unit's ballot ([brand](brand.md#the-live-contacts)), the mission clock and lights for the field unit, HQ and MAGI.

[The website's bridge guide](../website/src/routes/bridge.tsx) explains every panel on an annotated frame, for anyone who watches the bridge rather than runs it, and [bridge/README.md](../bridge/README.md) how it is drawn: V's `gg` on sokol with no UI library, its layout, palette and type, and every technique and rate of motion.

## Reading closer

The mouse shows more of what the watch streams already carry, to the person at the bridge alone: nothing it does leaves the process, so the bridge still sends nothing ([ADR 0005](adr/0005-the-bridge.md)).

- **Hover over the radar** for a readout of the entity under the cursor: its kind and id, its distance from the body, center to center as the percept gives MAGI, the velocity of a walking human or a moving obstacle, or STANDING, the seconds until a falling object lands, and for ground the share of its speed the body keeps there. Where marks overlap, the smallest answers, and ground only where nothing else does. A readout waits 0.3 s on the first mark the cursor comes to, so a cursor on its way elsewhere shows none, and then follows from mark to mark at once.
- **Hover over a MAGI unit** once its ballot has landed for its model, latency and whole why, which the panel cuts after three lines. Behind a course veto, which binds the unit whatever its model votes ([ADR 0009](adr/0009-magi-judge-a-walking-humans-course.md)), the readout sets the fact apart from what the model voted and why. Jev gives no reasons, so BALTHASAR-2 on Jev shows the rule's own line.
- **Click MAGI's block** to pin the vote it shows, or nothing while MAGI deliberate. A press longer than 0.3 s pins nothing, since it may be a drag that moves the window. A tab between 提訴 and 決議 says PINNED with the vote's mission time, and the block holds that vote while new ones come, which the header's MAGI light and the mark's contacts still show. Click a verdict in 決議's list to pin that one, its first line to page one vote back, and the block anywhere else to follow the votes again. Esc still quits the bridge while a vote is pinned. The bridge keeps the last six verdicts, and EX_MODE shows --- for a pinned one, since the seat at that vote is not kept.

Without a mouse, which the bridge image of Phase 6 may lack, the bridge looks as before. On the Mac the bridge follows the cursor only while it is the key window, which a click makes it, and a readout goes as the bridge loses the keyboard. Keep the mouse off the window while `just demo-record` records, or the recording shows the readout.

## What it watches

The bridge runs on a machine of its own and only watches ([ADR 0005](adr/0005-the-bridge.md)): it listens on `BRIDGE_ENDPOINT` for the watch streams that `gehirn hq` and `gehirn field` publish under `WATCH_KEY`, declares no publisher, and holds no key that approves or pulses, so closing it changes nothing. A bridge that starts late misses what came before; it shows the newest from then on. Beyond ADR 0005's table, and inside the same two streams, HQ shows each proposal as it goes to MAGI and each ballot as it lands, so the bridge shows the units deliberating and answering one by one, and the field unit's view says whether the dummy plug is benched, whether HQ has pulsed since the field unit started and how long HQ has been silent against `UMBILICAL_GRACE_MS`, so the bridge warns before the cable counts as cut.
