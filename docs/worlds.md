# Worlds

How to write a world for gehirn's simulated body: the file and every field in it, how its humans walk and what they do about the body, the default world and how it stays the reference, and how to fly a world. [Configuration](configuration.md) lists `WORLD` among the other variables.

## The default world

With `WORLD` unset, gehirn plays the world built into `body/world.v` `default_world`, and every measurement in [PLAN](../PLAN.md) from before worlds were files flew it. The body starts at -3.5,-2.5. Beacon b1, radius 0.3 m, stands at 3,2, past pillar o1, radius 0.8 m, at 0,-0.3. Human h1, radius 0.3 m, walks an ellipse around 0.8,1.2 with radii of 1.8 and 1.2 m at 0.3 radians a second, one loop per 21 s, and walks through the body.

It stays the reference, so earlier numbers stay comparable. `body/body_test.v` `test_scene`, which `just test` runs in a dev and a release build, pins its scene, over six of h1's loops every 7 ms and then an hour, a day and 30 days in, to the bit against the formula the simulator used before worlds were files: the ids, kinds and radii, the order b1, o1, h1, and every position. [worlds/default.json](../worlds/default.json) holds the same world in the file format, and `body/world_test.v` checks that loading it gives the built-in world and the same scene. `tools/scenarios.json` copies the default world for the scenario gate ([MAGI](magi.md#the-scenario-gate)), and `eval_test.v` checks that copy.

## A world file

A world is one JSON object. [worlds/example.json](../worlds/example.json) is a small one with four humans that walk and react in different ways:

```json
{
  "start": [-4.0, -3.0],
  "beacons": [
    {"id": "dock", "pos": [3.5, 2.5], "r": 0.3}
  ],
  "obstacles": [
    {"id": "o1", "pos": [-0.5, -0.8], "r": 0.7},
    {"id": "o2", "pos": [2.0, -2.5], "r": 0.6}
  ],
  "humans": [
    {"id": "h1", "r": 0.3, "behavior": "waypoints", "points": [[1.0, -3.5], [1.0, 3.5]], "speed": 0.5, "cycle": true,
     "reaction": "stop", "keep": 1.0},
    {"id": "h2", "r": 0.3, "behavior": "loop", "center": [2.5, 1.0], "radii": [1.6, 1.0], "rate": 0.35, "phase": 0.0,
     "reaction": "aside", "keep": 0.8},
    {"id": "h3", "r": 0.3, "behavior": "stand", "pos": [-2.5, -1.5],
     "reaction": "aside", "keep": 1.0},
    {"id": "h4", "r": 0.3, "behavior": "toward", "pos": [4.5, -4.0], "speed": 0.3,
     "reaction": "stop", "keep": 2.5}
  ]
}
```

Positions are `[x, y]` in meters, radii and distances in meters, speeds in meters a second, angles in radians. Every position, waypoint and loop lies inside the armor's fence, -5 to 5 m on each axis. Every entity is a circle, as the percept shows it, and the percept lists the beacons, then the obstacles, then the humans, each in the file's order. The core and MAGI read every one of them each time they judge, and the recorder writes them 50 times a second.

| Field | Holds |
| --- | --- |
| `start` | Where the body starts. `START` moves it ([Configuration](configuration.md)) |
| `beacons` | At least one beacon to deliver to, each an `id`, a `pos` and a radius `r`. A release counts on target at any of them, and the mission gehirn sets by default names the first |
| `obstacles` | Solid circles that never move, each an `id`, a `pos` and an `r`; may be empty |
| `humans` | People, each an `id`, an `r`, a `behavior`, a `reaction` and the fields those take; may be empty |

An `id` is 1 to 16 lowercase letters, digits and hyphens, one per entity, since ids reach status lines and every prompt. A world holds at most 16 beacons, obstacles and humans in all. Fields a behavior or reaction does not take are ignored.

### Behaviors

| `behavior` | Fields | Walks |
| --- | --- | --- |
| `loop` | `center`, `radii` as `[x, y]`, `rate`, `phase` | An ellipse around `center`, starting at angle `phase` and turning `rate` radians a second, counterclockwise when positive. A radius of 0 makes a line walked back and forth |
| `waypoints` | `points`, `speed`, `cycle` | From the first of 2 or more `points` to the last at `speed`, then back to the first and around again if `cycle` is true, or stands at the last |
| `stand` | `pos` | Nowhere: stands at `pos` |
| `toward` | `pos`, `speed` | From `pos` straight at the body at `speed` |

A walking speed lies from 0.1 to 2 m/s; a loop's is its rate times its larger radius. Humans walk on whenever the simulator senses the body, by the time since the world began and where the body is, so a run with the same senses moves them the same way. They walk through obstacles, as h1 of the default world walks through pillar o1, so lay their ways clear of them.

### Reactions

| `reaction` | Fields | Does |
| --- | --- | --- |
| `through` | none | Nothing: walks through the body, as h1 of the default world does. It is there so the default world stays the reference; a human of a new world stops or steps aside |
| `stop` | `keep` | Stands while the body's center is within `keep` of its rim, or would be after its next step, and walks on from where it stood once the body is clear, so it never steps within `keep` |
| `aside` | `keep` | Keeps its rim at least `keep` from the body's center: where its way leads past the body it walks around it, and where its way ends inside that distance it waits there. Then it catches up with its walk at up to 2 m/s. A body driving at it pushes it along, past the fence too |

`keep` lies from 0.3 to 3 m, measured as the armor measures a human, from the body's center to the human's rim, so it starts above the body's 0.25 m radius and an aside human keeps clear of the body. A human walking `toward` the body takes `stop` or `aside`, since walking through it would hold the body in contact for good. A standing human may react too: with `aside` it steps out of the body's way and back to its place.

The simulator keeps its rules for every world: the body stands still while it touches anything solid, humans included, by a distance from its center under the solid's radius plus 0.25 m, and a velocity command lapses after 200 ms. The armor keeps its own ([Safety](safety.md)), whatever a human does, and a stop or aside human never steps within its `keep` of the body, so it never walks into it.

Under `BODY=mujoco` the MuJoCo base plays the same world ([Safety](safety.md#how-the-body-moves)): every obstacle is a static cylinder of its radius and every human a walking capsule of its radius, which moves by the same rules on the model's clock, starting at the base's first sense and pausing with the model after a stall. There a solid stops the base through MuJoCo's contact, a human who walks through the base touches it by `Sim`'s rule and holds it still while they touch, as in `Sim`, and a beacon is nothing the base can touch.

## What gehirn refuses

gehirn reads `WORLD` at startup with the other variables and refuses to start, with one line that names `WORLD`, quotes its value, says what is wrong and what it accepts, and exits 2 ([Refusals](configuration.md#refusals)), for:

- a file it cannot read, one that is not a regular file of at most 65536 bytes, or one that is not a world in JSON, cut short or nested more than 32 brackets deep included;
- an unknown `behavior` or `reaction`, which includes a missing one;
- a position, center, radii or waypoint that is not one x and one y, a number that is not finite, and a radius at or below 0 or above 5 m;
- a position, waypoint or loop outside the fence;
- a start that touches an obstacle, or a human where it starts, by the simulator's rule of contact;
- an `id` that is not 1 to 16 lowercase letters, digits and hyphens, or that two entities share;
- no beacon, or more than 16 entities;
- a walking speed outside 0.1 to 2 m/s, a `keep` outside 0.3 to 3 m for `stop` or `aside`, fewer than 2 waypoints or waypoints all in one place, and a human walking `toward` the body and `through` it.

`START`, when set, moves the world's start and is checked as before: two decimals inside the fence.

## Flying a world

Set `WORLD` to the file. gehirn opens it from its working directory, and `tools/trials.py` starts each mission in a fresh one, so give it the full path:

```sh
just build
WORLD=$PWD/worlds/example.json python3 tools/trials.py --runs 3 --jobs 3
```

`tools/pilot.py` reads `WORLD` too and starts from the world's start, moved to `START` when set, and steers to its first beacon unless `--beacon` names another. The mission gehirn sets by default names the world's first beacon, so with HQ and the field unit apart, give HQ the same `WORLD`, or a `MISSION` of its own. The mock's core heads for the beacon the mission names, else the first ([Running gehirn](running.md#the-mock-by-hand)). The start sets of `tools/eval_dummy.py` lie in the default world, so with `WORLD` set it takes only starts you give it ([Piloting](piloting.md#training-the-dummy-plug)). `magi-eval` plays no world, since `tools/scenarios.json` holds its own scene. The bridge draws whatever the percept holds. The demo and the scenes unset `WORLD`, since their beats are timed on the default world; a scene that plays another world sets it itself.

PLAN's State holds what the example world's humans did in mock missions.
