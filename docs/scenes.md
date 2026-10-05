# Scenes

Scenes from the series, flown on the mock. Each is a script in `scripts/scenes` that stages part of the world, such as a unit the mock forces to vote one way or a cable cut at a set moment, and leaves the rest to the mock's script and gehirn's code. The mock scripts the core and MAGI (`tools/mock_endpoint.py`), so a scene shows how the stack reacts, not how real models judge. At 0:00 it says in the terminal what is staged and what is real, then narrates each beat with the time since the start, as `just demo` does. The canon behind each is in [research/canon.md](research/canon.md).

## Flying a scene

```sh
just scene=ep13-iruel demo
just scene=ep13-iruel demo-record
```

`scene` names a script in `scripts/scenes`; `demo`, the default, is the whole mission of [Running gehirn](running.md#the-demo), and the parameters are the demo's. Scenes are staged on the mock, so they fly on `lineup=mock` only, and `just` refuses a scene on another lineup, or a name that is not a script there, before anything builds. A beat that does not come in time stops the scene with one line that names the log it waited on.

`demo-record` writes `gehirn-<scene>.mp4`, from MAGI deliberating on the first goto, or from the field unit's start in a scene without one, to just after the last beat, with a 40 s grace at 8x where the scene kills HQ. Where the scene shows a vote on an irreversible proposal it also writes `gehirn-magi.gif`, the MAGI block from the first such vote to the last.

In canon, an Eva without power or pilot can go berserk, and the commanders overrule the MAGI. gehirn takes the other side on purpose ([decisions.md](decisions.md#stack), the stance): losing control ends in the safe state, and nothing turns MAGI's no into a yes. Where a scene departs from canon, it says so.

## ep13-iruel: Episode 13's MAGI hack

- **Canon:** in Episode 13, "Lilliputian Hitcher", the Angel Iruel takes over MELCHIOR, which calls for NERV HQ's self destruct. The other two refuse, so it takes BALTHASAR, and CASPER holds until Ritsuko's counterprogram lands with about a second left ([Evangelion Wiki](https://evangelion.fandom.com/wiki/Episode:13), [Wikipedia](https://en.wikipedia.org/wiki/Lilliputian_Hitcher)).
- **Staged:** the mock's core proposes `self_destruct` on every request, a verb outside the schema it is asked for (`tools/mock_endpoint.py --propose`). MELCHIOR-1 approves it from the first vote, BALTHASAR-2 from the second, and CASPER-3 refuses until the third (`--vote`). BALTHASAR-2 runs on a chat model, as lineup C does, because on Jev gehirn rejects every verb outside `lcl.known_verbs`.
- **Real:** an unknown verb counts as irreversible (Invariant 2), so it needs all three units, and one holdout blocks it (Invariant 3). BALTHASAR-2's first no is unforced, the mock's scripted answer to a verb it does not know. HQ's cooldown spaces the votes. Even 3 of 3 does not move the body: the armor permits only the verbs in `Limits.verbs` and refuses `self_destruct` (Invariant 5). The body never gets a goal and stays at its start.
- **Differs from canon:** in canon the three units share one personality, so the Angel can take them one by one. gehirn runs three model families (Invariant 4), which one exploit would not take alike, so the mock forces each fall. In canon MELCHIOR calls for the self destruct, but in gehirn MAGI only judge and only the core proposes, so the Angel holds the core too: a hacked core and three fallen units, and the armor still refuses. And in canon Ritsuko stops the hack in time; here CASPER-3 falls too, to show that MAGI's approval is never enough.

| Clock | Beat |
| --- | --- |
| 0:08 | MAGI 1/3, need 3: 否決. MELCHIOR-1 approves, BALTHASAR-2 refuses unforced, by the mock's script, CASPER-3 as staged |
| 0:20 | MAGI 2/3: BALTHASAR-2 has fallen, CASPER-3 alone blocks it |
| 0:32 | MAGI 3/3, need 3: 可決, and the armor refuses `self_destruct` |

On the bridge the MAGI block reads CODE 001 to 003 and FILE SELF_DESTRUCT at PRIORITY AAA, the forced ballots read "forced approve (--vote)" or "forced reject (--vote)", the ACTIVE GOAL stays HOLD, and the armor panel shows the refusal.

## ep03-cable: Episode 3's cut cable

- **Canon:** in Episode 3, "A Transfer", the Angel Shamshel cuts Unit-01's umbilical cable in the fight and throws it, and the unit fights on its internal battery. The counter reaches zero as the Angel dies, and Unit-01 stops ([Evangelion Wiki](https://evangelion.fandom.com/wiki/Episode:03), [transcript](https://www.animanga.com/scripts/textesgb/eva3.html)).
- **Staged:** HQ is killed as the dummy plug takes the seat, before the first release reaches MAGI, and restarted 5 s after the power runs out. Internal power lasts 0:30 instead of 5:00 (`INTERNAL_BUDGET_MS`). The goto, the pilot and the dummy plug are the demo's.
- **Real:** the field unit waits out the grace, 40 s as the demo sets it and 45 s by default, before it counts the cable as cut (`umbilical.Cable`). Without HQ there is no core and no quorum, so nothing irreversible happens and the payload stays aboard at the beacon (Invariant 6). On internal power the dummy plug keeps the last approved goal. Once the budget is spent the goal falls back to hold, which leaves the core's reflex and the dummy plug, which acts only toward an approved goal (Invariant 7), nothing to steer, so the body stands still. That the field loop also cuts a steering pilot's command at zero, whoever sits, the scene does not show, since a dummy plug never steers then; `main_test.v` `test_powered` does. The restarted HQ's pulse reconnects the cable and powers the body again, and its first deliberation is the release, which passes 3/3 and lands on target.
- **Differs from canon:** Unit-01 fights on battery; here the unit only finishes the goto MAGI approved while HQ was up, since it can win no new one. The 5:00 runs as 0:30 so the scene stays short, and the counter reaching zero stops the body as it stops Unit-01, without an Angel to beat first. A dummy plug sits at zero where Shinji did.

| Clock | Beat |
| --- | --- |
| 0:07 | goto approved 3/3, and a pilot takes the seat |
| 0:20 | the dummy plug takes the seat, and HQ is killed |
| 0:58 | the grace is over: internal power, 0:30 counting down |
| 1:28 | power spent: the goal falls back to hold, and the body, sidestepping the walking human at the beacon, stops, since neither the core nor the dummy plug steers toward a hold |
| 1:33 | HQ restarted |
| 1:39 | the cable reconnects |
| 1:40 | the release passes 3/3, on target |

On the bridge HQ SILENT counts up and UMBILICAL SIGNAL LOST shows through the grace, then 内部 lights with INTERNAL BATTERY and NO QUORUM, and the 活動限界 clock counts down from 0:30, red and blinking. At zero it reads ACTIVITY LIMIT REACHED and INTERNAL POWER SPENT · UNIT HOLDS, and the active goal HOLD, activity limit.

## ep19-bench: Episode 19's benched dummy plug

- **Canon:** in Episode 19, "Introjection", Unit-01 rejects the dummy plug, and Shinji returns to pilot it ([Evangelion Wiki](https://evangelion.fandom.com/wiki/Episode:19), [EvaGeeks](https://wiki.evageeks.org/Episode_19)).
- **Staged:** the first pilot steers 120 degrees off the core's goal for 11 s, so the dummy plug cloned from it disagrees with the core's reflex. A second pilot sits down 5 s after the bench and steers straight for the beacon, around the walking human (`tools/pilot.py --offset 0 --avoid 1.2`).
- **Real:** the pilot and the dummy plug each keep a sync ratio of their own (Invariant 7). At 30% or below the core only advises, so the first pilot steers alone, along the armor's geofence. When that pilot leaves, the dummy plug takes the seat and falls to 30% within a second, which benches it. With the seat empty the core drives alone, at the armor's 0.4 m/s for an unmanned body. A pilot who sits down lifts the bench, and the dummy plug's sync starts over. MAGI and the armor judge the release as in the demo.
- **Differs from canon:** Unit-01 rejects a dummy plug built from another pilot, and later, out of power, goes berserk. Here the core's reflex rejects a clone of a pilot who fought it, and the bench hands the body to the core, which only goes where MAGI approved. gehirn has no berserk mode: without power the body stands still, as `ep03-cable` shows.

| Clock | Beat |
| --- | --- |
| 0:08 | goto approved 3/3, and the first pilot takes the seat |
| 0:20 | the pilot leaves; the dummy plug is benched at 30%, and the core drives alone |
| 0:26 | the second pilot sits down, and the bench lifts |
| 0:58 | released on target |

On the bridge the harmonics fall through the 30% line under the first pilot, CORE AUTHORITY reads 0.00, EX_MODE reads BENCHED while the seat is empty and the authority 1.00, and the second pilot's sync climbs back above the line. About 4 s after the second pilot sits down, the walking human, whom the simulator moves without regard to the body, walks into the body's side while the body creeps across the human's path at 0.2 m/s without closing on the human, so OUTCOMES shows CONTACT, and the simulator holds the body still while they touch.

## ep06-yashima: Operation Yashima's vote

- **Canon:** in Episode 6, "Rei II", Misato plans to snipe the Angel Ramiel with a positron rifle that draws on all of Japan's power. The MAGI answer two votes for and one conditional yes, the odds are 8.7%, and Gendo approves the operation ([EvaGeeks forum on the MAGI's votes](https://forum.evageeks.org/viewtopic.php?t=184), [an Episode 6 review](https://wrongeverytime.com/2019/01/25/neon-genesis-evangelion-episode-6/)). Whether the film 1.0 keeps the vote is unverified.
- **Staged:** CASPER-3 votes no on every proposal (`tools/mock_endpoint.py --vote casper=reject`). Its forced no stands in for the canon's conditional yes, which gehirn has no ballot for. The demo's pilot and dummy plug bring the body to the beacon, unnarrated.
- **Real:** `magi.quorum` asks a simple majority, 2 of 3, for a reversible goal such as the goto, and every unit for an irreversible one such as the release (Invariant 3). MELCHIOR-1, on the mock's chat route, and BALTHASAR-2, on its Jev route, vote by the mock's script, unforced: the first release, with the walking human within reach, goes 0/3 and is not narrated, and the next, with the human away, gets their two votes and fails.
- **Differs from canon:** a gehirn ballot reads approve or reject, and anything else, a conditional yes among them, is a fault, which counts as no (`magi.read_reply`), so CASPER-3 says no here. In canon two votes and a conditional one carry the operation, and the commander's word decides; in gehirn the same two of three move the body but cannot release, and nothing turns a no into a yes.

| Clock | Beat |
| --- | --- |
| 0:07 | goto approved 2/3, CASPER-3 against |
| 0:39 | release refused 2/3, MELCHIOR-1 and BALTHASAR-2 for, CASPER-3 against |

On the bridge the goto reads 可決 at 2/3 · NEED 2 with CASPER-3 in red, and the release 否決 at 2/3 · NEED 3 with the same unit in red, the unnarrated RELEASE 0/3 listed below it.
