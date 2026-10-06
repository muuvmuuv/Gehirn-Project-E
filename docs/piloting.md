# Piloting

How a pilot steers the body: the signed datagrams and the A10 reply, the gamepad, the sync ratio that shares the controls with the core, and the dummy plug that takes the seat when the pilot leaves.

## Datagrams

The plug takes UDP datagrams like this one, at 20 Hz or faster: a JSON line, a newline, and the line's HMAC SHA256 under `PILOT_KEY` in 64 lowercase hex digits. `tools/pilot.py` `datagram()` shows how to make one.

```
{"v":1,"seq":1790000000000000,"pilot":"shinji","u":[0.4,0.1],"eject":false}
fa38345f9bbb948b76b3bf0dd41a3c4e237e7a623a545f68d9a767d164f59133
```

`u` is the desired velocity in meters per second. `seq` is the pilot's wall clock in microseconds, strictly increasing. The plug drops a datagram that is unsigned or signed under another key, comes from another pilot, because a core is paired with one pilot, repeats or precedes the last one it took, or lies more than 500 ms from the field unit's clock, so a captured datagram cannot be replayed. The pilot's clock therefore has to agree with the field unit's within 500 ms, which NTP on one network does by a wide margin. Without `PILOT_KEY` the plug drops every datagram, and gehirn says so at startup. The seat counts as empty 500 ms after the last datagram. `eject` latches: the body halts and stays halted until the process restarts.

The plug answers every datagram it takes, to the address it came from, with what the A10 back channel lets the pilot feel ([ADR 0006](adr/0006-gamepad-and-a10.md)): a JSON line, a newline, and 64 hex digits of HMAC SHA256 under `PILOT_KEY` over `feel`, a newline and the line. A reply never passes as a datagram.

```
{"v":1,"feel":{"t_ms":1791033238530,"contact":false,"near":0,"sync":0.5,"strain":0.94}}
```

`t_ms` is the field unit's clock, `contact` says the body touches something, `near` how close the nearest human is, 0 from 2 m out and 1 at 0.7 m, `sync` is the seat's sync ratio, and `strain` the meters per second the armor took off the command, by any of its limits: speed, acceleration, separation, the fence and the slide along anything solid. Under `DRIVE=differential` it also counts what the base does not execute while it turns toward the command ([Safety](safety.md#how-the-body-moves)). Nothing on the field unit waits for a reply or acts on one.

## The gamepad

`./gehirn-gamepad` puts the seat in a game controller ([ADR 0006](adr/0006-gamepad-and-a10.md)). It runs on the pilot's machine, reads any controller SDL2 knows, Xbox and PlayStation pads among them, and sends the plug signed datagrams at 50 Hz as `PILOT_ID`, under `PILOT_KEY`, to `PLUG_ADDR`. Building it needs SDL2 and its pkg-config file: Homebrew's `sdl2-compat` on the Mac, `sdl2-compat-dev` on Alpine, `libsdl2-dev` on Debian and Ubuntu. Nothing else in gehirn needs SDL.

| Control | What it does |
| --- | --- |
| Hold LB (L1) | Keeps the seat. The gamepad sends only while LB is held; let go and the seat empties after 500 ms, and the dummy plug or the core takes over |
| Left stick | Steers: up is +y, and full tilt asks for 1 m/s, the armor's manned cap. A stick resting within 15% of center reads zero |
| Hold Back and Start (View and Menu, or Share and Options) for a second | Ejects. Both must have been up first, and letting go of either starts the second over. The eject latches until gehirn restarts |

Every reply rumbles: contact shakes both motors at full, a human inside 2 m hums the high frequency motor harder the closer they come, and the armor's strain pulls the low frequency motor, which also answers a sudden full tilt while the armor ramps up the speed. Each rumble lasts 100 ms, so it stops when replies stop. The gamepad prints one line a second with whether LB is held, the command, the datagrams sent, lost and answered, and the newest feel, or `no feel` when no reply came that second; `./gehirn-gamepad --probe` lists the controllers SDL sees and exits. Reading a physical controller and its rumble are not verified yet (PLAN, Phase 2). Next to a running field unit, or `./gehirn` as in [The mock by hand](running.md#the-mock-by-hand), with the same `PILOT_KEY`:

```sh
just gamepad
PILOT_KEY=<the field unit's key> ./gehirn-gamepad
```

## Sync ratio

Sync is a moving average of how well the seat and the core agree, from the angle between their commands and how close their magnitudes are. It is the arbitration term of shared control, in the sense of Dragan and Srinivasa's policy blending. At or below 30% the core only advises. Above that its share grows with sync up to 80%, so a seated pilot keeps at least a fifth of the controls while the body has power. A core with nowhere to go takes no share.

The dummy plug earns its own ratio. At 30% it is benched until the pilot is back, and the core drives alone under the unmanned speed limit. It imitates style, not intent: commands are stored relative to the approved goal, so without a goal it does nothing, and with one it has no memorized heading to run off with. In canon a sync ratio past 400% dissolves the pilot into LCL. The nearest thing here is a dummy plug good enough that nobody needs to sit down.

## Training the dummy plug

Without a weights file the dummy plug clones the pilot by nearest neighbor: each tick it averages what the pilot did at the seven ticks on file most like this one, by where the body was and how far the goal. It sees nothing of the scene. With a weights file it flies a small neural network trained offline on what the pilot saw: how far the goal is, and the direction to and closeness of the nearest obstacle and the nearest human and which side of the way to the goal each lies on, all in the goal's frame. The network predicts the pilot's command and its speed, and the dummy plug flies the command's direction at that speed. gehirn loads `DUMMY_WEIGHTS` at startup and names it on the `field: plug` line. A file there that is cut short, of another version or shape, or holds a weight that is not finite or beyond 1e6, stops gehirn with one line that names the variable and the cause, and exits 1; weights of an older version have to be trained again from the recorder.

Export the ticks the pilot flew toward a goal from the recorder, then train; a few thousand ticks take seconds, 33000 about 40 seconds:

```sh
python3 tools/export_dummy.py plug.shinji.jsonl > dummy.shinji.set
python3 tools/train_dummy.py dummy.shinji.set    # writes dummy.shinji.json
```

Then correct it DAgger style: fly with the dummy plug in the seat and take the seat whenever it steers wrong. The recorder marks every tick of a pilot who took the seat from the dummy plug while it drove toward a goal, or after it was benched, as a correction. Exporting and training again on the whole recorder learns from them, and `--corrections 2` counts each twice. `tools/pilot.py --avoid 1.2 --dagger 30` is a scripted pilot that does the correcting: it passes anything within 1.2 m of its rim on the side nearer the beacon, and takes the seat for two seconds whenever the dummy plug steers more than 30 degrees off its own command or nobody steers toward a goal.

`tools/eval_dummy.py` compares the two dummy plugs. It flies each from the starts you give it, or from the start sets of PLAN.md Phase 4's protocol (`--starts train`, `validation`, `test`, `fresh-train` or `fresh`, which its docstring explains and which lie in the default world, so it refuses them while `WORLD` names another), with the same recorders on file and a scripted pilot who leaves after a second, and counts how often each brings the body within reach of the beacon, how often it gets benched, how far it steers off what the pilot would have steered, its lowest sync, and how close it comes to the pillar and the human; PLAN.md records what it measured. The nearest neighbor dummy plug keeps only the newest 20000 pilot ticks of those recorders, and the script warns when they hold more.
