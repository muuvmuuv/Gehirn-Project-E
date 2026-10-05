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
