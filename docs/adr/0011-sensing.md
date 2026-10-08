# ADR-0011: Obstacles from a range sensor

**Status:** Proposed
**Date:** 2026-10-08
**Deciders:** repository owner

## Context

Phase 3's done criterion asks for the mission and every invariant to hold with obstacles known only through sensing, and Task 5 asks for obstacles from a range sensor instead of ground truth, with humans allowed to stay ground truth behind a detector stub that reports each human's velocity from its own track, or MAGI's course rule falls quiet ([ADR-0009](0009-magi-judge-a-walking-humans-course.md)). The owner put Task 5 first on the way to that criterion (docs/decisions.md, 2026-10-08, Phase 3 to its done criterion before 3D).

Six facts shape the decision.

1. One percept feeds everything. `main.v`'s field loop takes `p := ar.sense()` once a tick and hands that percept to the armor's `refusal`, `effect`, `top_speed`, `closeness` and `drive`, to `reflex` or `planner.Planner.next`, to the dummy plug's `act`, to the recorder as `plug.Record.scene`, to HQ inside the `lcl.Context`, where the core and the chat units read `lcl.Percept.describe` and BALTHASAR-2 reads Jev's facts, and to the bridge inside the `lcl.FieldView`. Both bodies build the scene from `World.scene` in `body/body.v`, `Sim.sense` and `body.Mujoco.sense` alike: ground truth with the world's ids, positions, radii and each walker's velocity.
2. Every reader works on circles by kind. Each keeps the body off every entity that is not a beacon ([ADR-0010](0010-terrain-on-the-plane.md), fact 1); `planner.Planner` keeps its memory of who stood by id (`stood` in `planner/planner.v`), so an id must stay with its entity; `magi.walks_onto` reads a human's velocity and counts one without a velocity as standing where it is (docs/magi.md); Jev's facts name people, beacons and obstacles by id (`magi/jev.v`).
3. Every measurement reads the recorder's scene. `tools/trials.py` takes the closest rims and the steps toward a human inside `HUMAN_STOP` from `scene` in each record, `tools/worldgen.py` audits on trials' records, and `tools/export_dummy.py` trains the dummy plug on it. A scene that holds what the stack senses would make those numbers measure the stack's belief, not the world.
4. MuJoCo 3.14.0 casts rays, `mj_ray` and `mj_multiRay` against its visible geoms (its `mujoco.h`), but `body/mujoco_d_mujoco.v` `mjcf` writes each ditch as a static cylinder as tall as a pillar, so a ray would read a ditch as a wall; its humans are mocap geoms without contacts, which a ray still meets; a falling object and a patch of ground are no geoms. `Sim` has no geometry beyond the world's circles.
5. A range ring sees walls, not holes, water, mud or the spot where something will land (PLAN, Known issue 6). Phase 5's firmware restrains speed, acceleration, a geofence from odometry, a watchdog and an e-stop, and no obstacle (PLAN, Phase 5), so no layer below the field tier is planned to keep the body off a solid or a person.
6. Every number in PLAN's State was measured with the scene as ground truth, and `body/body_test.v` `test_scene` pins the default world's scene to the bit.

## Decision

`SENSING` chooses how the stack knows the scene: `truth`, the default, as today and byte for byte, or `range`, the range ring and its tracker below. `range` is an option beside `truth` until missions, scenes and hosted runs are measured on it and the owner moves the default, as with `PLANNER` and `BODY`.

**The sensor.** Under `range` `main.v` wraps either body in `body.Ranged`, so both scan with the same code, `body.scan`: 360 beams, one a degree, from the body's center, counted from its heading, which a holonomic body reports as 0, out to 10 m, against the circles a range finder meets on the plane, standing and moving obstacles and humans. Beacons, ditches, landing zones, craters and ground reflect nothing. The ranges are ideal: no noise, no dropout, and a fresh scan at every sense, so at the field loop's 50 Hz. The percept carries them as `Percept.scan`, which `truth` leaves empty and JSON leaves out.

**People.** A detector stub in `body` reports each human that at least one beam of that scan ends on, at its true position and radius, with no id and no velocity, as a camera's person detector would report a person in view; a human hidden behind a solid or beyond 10 m is not reported.

**The map.** Beacons, ditches, landing zones with their `lands_in`, craters and ground come from the world file as the site's map, as today, and keep the world's ids. That is honest for a site plan known before the mission and for a landing predicted by an outside service as the region its estimate cannot rule out, which in simulation is exact.

**From scan to scene.** A new field tier module, `sensing`, which imports `lcl` alone, turns the body's percept into the one the stack reads: `main.v` runs `p := tracker.percept(ar.sense())` and hands that `p` to every reader of fact 1. It drops every hit that lies on a detected person, groups consecutive hits whose points lie closer than 0.15 m or three times the beam spacing at their range, whichever is wider, fits each group a circle, a least squares fit grown until every hit of the group lies inside it, plus 2 cm, or for one or two hits or hits on a line a circle around their centroid; a group whose circle would reach the body's center, as one seen from inside a cup of discs does, gets a circle around the centroid of each piece of it that spans 0.5 m, or a quarter of its distance from the body, at most, which keeps every circle off the body; and a circle whose hits another circle already holds, as a pillar's holds a hit grazing its rim or the arc beyond a person's shadow, folds into it. It keeps a track for each circle and each person, matched by the nearest center within the distance 2 m/s covers since the last sense plus 0.2 m, reports each track at its newest measured position, smooths its velocity with a filter of the residual against the predicted position, reports a velocity from a track's second sighting on and none below 0.05 m/s, the planner's `walking`, holds a track unseen for 1 s at its last position and then drops it. The scene it hands on holds the map's entries, then each track as an `obstacle` or a `human`, with ids that stay with their track, `s1`, `s2` for sensed solids and `p1`, `p2` for people, so the ids say where each entity comes from. It drops `scan`, so no scan crosses the wire.

**The armor restrains on the sensed percept**, as the owner decided on 2026-10-08 (docs/decisions.md, the armor restrains on what the stack senses; Trade-off Analysis). The done criterion reads as the owner decided the same day: obstacles and people known only through the ring and the tracker, ditches, ground, landing zones and craters from the map (docs/decisions.md, the done criterion's reading). The default of `SENSING` stays `truth` and remains open until the measurements of the Action Items. Ground truth reaches the recorder alone: `Body` gains `truth()`, the simulator's scene, empty on a body without one, which `armor.Armor.truth` passes through for `main.v` to write into `plug.Record.truth` under `range`. `tools/trials.py` takes its closest rims and its steps toward a human from `truth` where a record holds it and from `scene` otherwise, and `tools/worldgen.py`'s audit checks the restraints, contacts and releases on the same, while it judges MAGI's votes on the scene MAGI read. `Sim` and the MuJoCo base still decide contact on ground truth.

Nothing else changes its code: the reflex, the planner, the dummy plug, `describe`, MAGI's facts and the bridge read the sensed scene as they read the true one, and HQ never sees the truth or the scan.

## Options Considered

### The sensor

**A planar range ring, cast in `body` for both bodies (chosen).** Pros: one code path, so `Sim` and the MuJoCo base scan alike and stay comparable; pure V, so Invariant 9 holds with no new door into `mujoco`; the ray against a circle is exact. Cons: it scans the world's circles, not MuJoCo's geoms, so the 3D work of docs/decisions.md, 2D first, needs another scan.

**MuJoCo's `mj_multiRay` or rangefinder sensors on the base.** Pros: the physics model's own geometry, ready for heightfields and 3D. Cons: a new function on the `mujoco` door; a ray reads every ditch as a wall (fact 4); `Sim` still needs its own scan, so two bodies scan differently.

**A coarser or slower ring, such as 180 beams at 10 Hz.** Pros: closer to a low cost 2D lidar, which turns at 5 to 15 Hz. Cons: a scan up to 100 ms old adds a walker's motion to every keep, on top of the braking Known issue 33 leaves open; that belongs in a measured step of its own (Action Items).

### From scans to obstacles

**Circles with tracks, in a module `sensing` that imports `lcl` (chosen).** Pros: every reader of fact 2 keeps its code, since a sensed solid is a circle like any other; a circle that holds every hit never puts a rim farther from the body than the surface the sensor saw; a track's id stays put for the planner, and its velocity feeds the course rule and the planner's prediction. Cons: a circle overstates a long wall's reach, and a new track has no velocity on its first sighting, the case of Known issue 34.

**A local occupancy grid.** Pros: any shape, walls of any length. Cons: every reader of fact 2, three Python tools among them, needs a grid reader, and MAGI's text and Jev's facts would need a way to name a cell.

**The tracker inside the armor.** Pros: nothing outside the armor could hand it a different percept. Cons: the armor imports `sensing`, a new edge in the module table for the module that must stay the restraint, and `drive` already takes its percept from `main.v`.

### People

**A detector stub at true positions behind line of sight, tracked in `sensing` (chosen).** Pros: Task 5 allows it; the velocity comes from the stack's own track, never the simulator; a hidden person goes unreported as with a real detector. Cons: no noise, no lag and no false person, so it shows what tracking costs, not what a camera costs.

**People as ground truth with the world's ids and velocities.** Pros: no change for people. Cons: Task 5 asks for the velocity from a track. **People from range clusters alone.** Pros: one sensor. Cons: a pole and a person look alike in a ring, while the armor keeps 0.7 m from a human and 0.35 m from a solid and refuses a release by people alone; calling every cluster a person would refuse releases beside every pillar.

### What a ring cannot see

**The site's map for ditches, ground, landing zones and craters (chosen).** Pros: in simulation it holds what the world holds, so ADR-0010's restraints and its landing fact keep their numbers; it is honest for a planned site and a predicted landing. Cons: a map can be stale, which no world tests yet.

**A downward sensor, as robot vacuums carry.** Pros: it senses a rim itself. Cons: it sees a rim only under its edge, so the planner cannot plan around a ditch, and a holonomic body needs a ring of them; it senses no water and no landing. **Ground truth kept and named so.** Pros: no code. Cons: the same numbers as the map under a name that admits the gap without closing any of it.

### What the armor restrains on

**The sensed percept (chosen by the owner on 2026-10-08).** Pros: it meets the done criterion as written; a sensing failure shows as a contact or a close pass by ground truth instead of hiding behind a restraint that knows better; a real field unit has nothing else, and Phase 5's firmware restrains no obstacle (fact 5). Cons: a person the detector misses, behind a pillar within 2 m, could stand beside a release the armor permits, which only a measurement can bound.

**Ground truth, standing in for a safety sensor.** Pros: the restraint keeps its measured numbers whatever sensing does. Cons: the done criterion holds only for what sits above the armor, the restraint rests on knowledge no field unit has, and no layer of the plan supplies it (fact 5).

**The union of both.** Pros: it fails closed. Cons: a sensing failure never shows in a contact, so it measures nothing the chosen option does not measure through the recorder's truth.

### What stays comparable

**`SENSING=truth` by default, `range` an option, ground truth in the recorder (chosen).** Pros: every earlier number and `test_scene` stand, and every measurement under `range` reads the world, not the belief. Cons: one more variable, and a recorder line under `range` grows by the true scene.

**`range` the default at once.** Pros: one stack. Cons: every number in State, the demo's beats and the hero GIF move before anything is measured.

## Trade-off Analysis

Honesty against reach. Ideal ranges and a stub at true positions keep the first step about what knowing through a sensor costs, resolution, occlusion and tracking, without noise that would hide those under randomness. They do not stand for a lidar or a camera, so the docs say "an ideal range ring" and "a detector at true positions", and noise, rate and misses come later, each measured.

A restraint that can be wrong against one that cannot fail. The armor on ground truth would hold every keep as today and say nothing about sensing. On the sensed percept it can miss a hidden person, and the recorder's truth shows every tick where it did. The design keeps the sensed circle around every hit, so no seen surface lies closer than the armor thinks, and at 1 degree a beam spacing of 3.5 cm at 2 m leaves no world's circle unseen within the armor's reach unless something hides it. Occlusion is the open risk, above all for a release: a person hidden behind a solid inside 2 m. Should a run show one, the armor's fix is to count a hidden sector within `release_keep` as a person for an irreversible effector, which only refuses more.

Circles against shape. A circle per cluster keeps every reader's code and every safety argument made so far, at the cost of overstated reach where discs overlap into a wall or a cup, as `worlds/pocket.json`'s three discs do, whose rims overlap by 0.21 m: seen from outside they make one cluster, and its circle may close the cup's mouth or cover a beacon beside it, which Action Item 3 flies.

## Consequences

Easier: the stack knows obstacles and people only through its sensor and its tracker, the course rule runs on tracked velocities, and every measurement still reads the world; the bridge can later draw what the stack sees beside what is there, which suits the website's recording of Tooling task 9.

Harder: a new track has no velocity on its first sighting, so a walker who steps out from behind a pillar draws no course for 20 ms, the case of Known issue 34; the scenes' scripts wait on lines with the world's ids, such as `"id":"shard-1","kind":"ditch"`, which keep their ids since they come from the map, while a person's id becomes `p1` under `range`; a model reads `obstacle s3` and `person p1`, whose ids carry no history across a lost track; and `tools/scenarios.json` keeps the world's ids, so `magi-eval` judges no sensed scene.

Known passes: a person hidden from the sensor, a track that drops a walker who stops behind a solid for more than 1 s, and a circle that overstates a wall are what the measurements of the Action Items look for. Noise, a slower scan, a detector that misses or lags and a stale map wait for a measured step each.

Invariant 1 holds: `truth` is read only, and the body stays the armor's alone. Invariants 2, 3, 4, 6, 7 and 8 hold: verbs, the quorum, the families, the umbilical, the dummy plug's goal and the core's share are untouched. Invariant 5 holds: the armor checks every approved goal and every command again, now on what the field unit senses. Invariant 9 holds: `sensing` and the scan are V's standard modules alone, with no C library and no new door into `mujoco`. Invariant 10 holds: a track's velocity comes from the percepts' own times, and a scan comes with every sense. Invariant 11 holds: the journal is untouched; `truth` goes to the recorder, which is no journal.

Revisit when 3D comes (a scan from MuJoCo's geoms), when a real sensor is chosen (Open question 1), or when a measurement shows a hidden person beside a release. On acceptance ADR-0009's status gains "; its velocity from a track under `SENSING=range` by ADR-0011" and ADR-0010's "; ditches, ground and landing zones from the map by ADR-0011".

## Action Items

1. [x] `body.Ranged` with `body.scan` and the detector, `Body.truth` on `Sim`, the MuJoCo base and `armor_test.v`'s fake, `armor.Armor.truth`, `Percept.scan`, `plug.Record.truth`, `SENSING` in `load_config` and docs/configuration.md, and the module `sensing` with its row in PLAN's module table; table tests for a ray against a circle, a cluster's circle holding every hit, a straight walker's tracked velocity, an id that stays with its track and a hidden person who goes unreported; under `truth` `test_scene` and every request as before.
2. [x] `tools/trials.py` reading `truth` where a record holds it, and `tools/worldgen.py`'s audit checking the restraints on it through trials, each with its self check.
3. [x] Mock missions under `range` beside `truth` on the default world, `worlds/example.json`, `crossing.json`, `sweep.json`, `pocket.json` and `terrain.json` and in every scene, on `Sim` with both drives and on the MuJoCo base, under the reflex and the planner: deliveries and their times, the closest rims and contacts by ground truth, armor refusals, every release with a person within 2 m by ground truth, which must be none, and how often the course rule fires against `truth`. Flown on 2026-10-08, 288 missions: no contact, no armor refusal and no release within 2 m of a person by ground truth, and two gaps, a walker hidden behind a pillar and a first goto judged on a new track (PLAN, State and Known issue 43).
4. [ ] Known issue 43's gaps closed and measured: a hidden person under the separation cap and beside an irreversible effector, and a new person's unknown velocity.
5. [ ] A `tools/worldgen.py` hunt with `range` under test and `truth` as the reference, for worlds where sensing fails: a person hidden near the beacon, small or fast things, walls of overlapping discs.
6. [ ] Ten hosted missions of lineup A under `range`, on the default world and `worlds/terrain.json`.
7. [ ] The owner decides the default of `SENSING`. What the armor restrains on and the reading of the done criterion below are the owner's calls of 2026-10-08 (docs/decisions.md).
8. [ ] Later steps, each measured on its own: a 10 Hz scan, seeded range noise and dropouts, a detector that misses, lags or reports a false person, a stale map, and the bridge drawing the true scene beside the sensed one for Tooling task 9.

The done criterion reads as obstacles and people known only through the sensor and its tracker, while ditches, ground, landing zones and craters come from the map, as the owner decided on 2026-10-08.
