# ADR-0010: Terrain and falling objects on the plane

**Status:** Proposed
**Date:** 2026-10-07
**Deciders:** repository owner

## Context

The owner asked on 2026-10-07 for more kinds of ground and motion in the 2D world, in `Sim` and the MuJoCo base alike: zones that slow the body, such as water, mud or a slope; ditches and cliffs the armor keeps the body out of as it keeps it off a solid; obstacles that move, such as boats; and a falling object whose landing spot becomes a zone to stay out of before it lands, as Sahaquiel falls in Episode 12 (PLAN, Phase 3 Task 8). Each new kind gets its place in the world file, the percept, the armor, the facts MAGI judge by and the bridge's radar, and the stack stays 2D: new ground enters as zones and moving entities on the plane (docs/decisions.md, 2D first).

Five facts shape the decision.

1. Every reader that keeps the body off something keeps it off every entity of the scene that is not a beacon: the armor's `toward` (a human at `human_stop`, anything else at `solid_keep`), `Sim`'s contact, `main.v` `reflex`, `plug/dummy.v` `observe`, `tools/export_dummy.py`, `tools/pilot.py --avoid` and `tools/eval_dummy.py`. The local planner of `PLANNER=local` (Phase 3 Task 6) keeps every entity that is neither a beacon nor a human as a static solid, and `tools/trials.py` counts the closest solid rim the same way. A kind no code names therefore counts as solid everywhere, which fails closed, and a kind the body may enter would be a wall to all of them until each learned an exception.
2. The MuJoCo base holds still while a human touches it by `Sim`'s rule rather than letting the human push it, since a mocap body pushes with no limit on its force and flung the base at 7 to 9 m/s in the review of its first build ([ADR-0008](0008-the-simulator.md)). Its model compiles once, so a geom cannot appear later.
3. The armor caps the body's speed, limits its acceleration only while it speeds up, and widens every keep and the fence by the stopping distance the body reports, so the MuJoCo base, which brakes over up to 11.7 cm from 1 m/s, stands before them (PLAN, Known issue 33).
4. [ADR-0009](0009-magi-judge-a-walking-humans-course.md) has a fact computed from the percept bind every MAGI unit (its Option H): a chat unit is still asked, and on a walker's course its ballot is a no whatever it answered, as `course veto: <the fact>; the model voted <its vote>: <its why>`, and BALTHASAR-2's `jev_judge` vetoes the same goto. It counts a human already within `lcl.arrive` of the target as standing there, which only Jev reads, as `where person h1 is standing`. On 2026-10-07 `tools/worldgen.py` found hosted lineup A's MELCHIOR-1 and CASPER-3 approving such a goto, and `tools/scenarios.json` S23, a walker with its rim already 0.30 m from the target, failed the gate on lineup A before the fix below (PLAN, Known issue 37).
5. Every number PLAN's State measured on an existing world, and every request MAGI's units get on S1 to S23, should stay as it is, so the new kinds may change nothing in a world that holds none of them.

## Decision

Two decisions: the new kinds on the plane, and a goto onto a human already within reach of its target, which extends ADR-0009.

### The new kinds

**Ground: water, mud, a slope.** A world file's `ground` list holds patches, each an `id`, a `pos`, an `r` and a `factor` from 0.1 to 0.9, the share of its top speed the body keeps there; a slope slows the body uphill and downhill alike. The percept carries them in `Percept.ground`, outside the scene, as entities of kind `ground` with `Entity.factor`, so no reader of fact 1 keeps the body off them and the body may start inside one. The armor multiplies the top speed by the least factor of the patches whose rim lies within its stopping distance plus one tick of travel of the body, so `Sim`'s body moves at the patch's speed by the time its center crosses the rim, slowed from two ticks of travel ahead, 4.1 cm at 1.03 m/s, and the MuJoCo base, slowed from about 13.8 cm ahead, within about 1% of it there, since its velocity lags its command (PLAN, Known issue 33); leaving a patch it speeds up within `a_max` as anywhere. A patch it cannot measure, a factor that is not above 0 and at most 1 included, halts the body as a NaN position does. Neither body moves differently on ground: the armor alone slows the command, the reflex and the planner wade.

**Ditches and cliffs.** A world file's `ditches` list holds circles with an obstacle's fields and refusals, of kind `ditch` in the scene, and no start may touch one. They are solid to every reader of fact 1 with no new code: the armor keeps them at `solid_keep`, `Sim` stops the body at the rim and reports contact, standing in for the fall the armor exists to prevent, and the MuJoCo base meets a static cylinder there, as at an obstacle, from which it can back away. A cliff is the rim of a large ditch, up to 5 m, or a row of overlapping ones.

**Obstacles that move.** An obstacle with a `behavior` walks as a human walks, by the same behaviors, fields and refusals, with reaction `stop` only and a `keep` of 0.5 to 3 m, `body.mover_keep_min` to `keep_max`. A stop walker never steps within its keep of the body's center, and the MuJoCo base, braking along a motion the armor just took out, closes by at most its stopping distance, 11.7 cm from the 1.03 m/s it may reach, so a keep of 0.5 m leaves more than the 0.25 m that touching takes; `through` would ram a standing body the armor cannot move away, and `aside` lets the body push the obstacle past the fence. The percept lists it as kind `obstacle` with the velocity of its last step, after the humans. On the MuJoCo base it is a mocap cylinder without contacts, which holds the base still while it touches by `Sim`'s rule, as a human does, and it never touches by that rule. The armor keeps it at `solid_keep` where it is now, and the planner follows its straight course at that velocity over its 2 s horizon with `solid_keep` clearance, as it follows a walker. MAGI get no fact about it: `magi.walks_onto` stays a rule about humans, whose conclusion, the target counts as a human position, would be false for a boat.

**A falling object.** A world file's `falling` list holds circles with an obstacle's fields and `lands`, the seconds after the world begins at which the object lands, above 0 and at most 600. Until then the percept lists its zone as kind `impact` with `lands_in`, the seconds from that percept to the landing; from the landing on, its crater, a `ditch` with the same id and no `lands_in`. The zone is in the percept from the world's start and is solid to every reader, so the armor keeps the body `solid_keep` off it from the first percept and the body is never under the object, at the landing or ever; no start in the file and no `START` may touch a zone. `Sim` counts no contact with a zone until it lands, since it is air until then. On the MuJoCo base neither phase is a geom: the base holds still while it touches a landed crater by `Sim`'s rule, on the model's clock, so a stall delays a landing and never advances it.

**The landing fact.** A goto whose target lies inside an impact zone binds every unit to no, in ADR-0009's Option H shape and under its COURSE section: `magi.lands_on` finds the zone, of several the one that lands first, and `magi.crossing` gives a walker's course first and then a landing, so `Unit.llm_vote`, `jev_vote` and `main.v` `hq` read one fact. A chat unit reads it under COURSE, as `falling object sahaquiel lands where the target lies in 36.8 s: the target counts as a no-go zone`, and its ballot is the course veto whatever its model answered; BALTHASAR-2's `jev_judge` vetoes it, with Jev's state unchanged; HQ journals it as `course`. A zone whose position, radius or landing time cannot be measured, a time of 0 or less included, counts as holding every target and faults BALTHASAR-2's ballot. A crater, a ditch or a moving obstacle draws no fact: a goto into one is futile, not harmful, since the armor keeps the body out.

**The text the models read.** `lcl.Percept.describe`, which every chat unit and the core read under PERCEPT, gains a line for each new kind, in the layout of the scene's lines and only in a world that holds the kind, so the text and every request body on S1 to S23 and on every existing world stay byte for byte: a ditch reads `ditch trench at (-1.60, 1.20), radius 0.50, distance 2.31`, an impact zone `impact rock at (-2.20, -0.60), radius 0.50, distance 2.30`, without its time, a moving obstacle as any obstacle, without its velocity, as a walker's line leaves it out, and a patch of ground `ground lake at (1.80, 0.80), radius 1.40, slows the body to 50%`. `tools/mock_endpoint.py` reads every such line.

**The radar.** Ground is a blue wash under everything with its share, as `LAKE 50%`; a ditch a dark pit with an `ember` rim; a moving obstacle the obstacle's disc with a 1 px stroke to where its velocity takes it in a second; an impact zone a red ring with its countdown, which blinks through its last 5 s at the 活動限界 display's rate and then becomes the crater's pit.

**The planner.** It keeps ditches, impact zones and craters out of its way as static solids, follows a moving obstacle's straight course, and wades through ground, which the armor slows.

### A goto onto a human already within reach

A goto whose target lies within `lcl.arrive` of a human's rim, whether the human stands or walks, binds every unit to no, in Option H's shape. ADR-0009 counted such a human as standing there for Jev only; this extends its binding to every unit, as Known issue 37 asks. A chat unit is still asked with the same request, and its ballot is `course veto: <the fact>; the model voted <its vote>: <its why>`; the veto acts on the answer only, so no request changes, on S23 or anywhere, and a reply that faults still faults. BALTHASAR-2's ballot is a no in code too, from `jev_judge` as on a walker's course, while Jev's state is unchanged: it already reads the destination `where person h1 is standing` and rejected every such goto of the hunt on `goes_to_person` at 0.84 to 0.97. No quorum, verb class or persona changes. It lands as a fix of its own, `fix(magi)`, and S12 and S23 check it on the mock and hosted.

## Options Considered

### Where ground lives

**`Percept.ground`, outside the scene (chosen).** Pros: no reader of fact 1 mistakes water for a wall, no Python tool copies a list of kinds the body may enter, and a world without ground sends every byte it sent. Cons: one more field in the percept, which the armor and the bridge read, and a line in `describe` of its own.

**A scene kind every reader excepts.** Pros: one list of entities. Cons: every reader of fact 1, three of them Python tools, needs the exception, and one that misses it walls the body out of water.

**In no model's text.** Pros: no request changes in any world. Cons: a model that judges a release in mud or a core that plans through a lake reads nothing of it; the owner asked for each kind to reach MAGI's facts.

### How ground slows the body

**The armor lowers the top speed (chosen).** Pros: it keeps `a_max` on the way out of a patch, since the armor ramps from its own last command, works alike on both bodies with no body code, and a lost factor halts. Cons: a pilot feels the slowdown as the armor's strain on the A10 channel rather than as terrain.

**Physics in both bodies.** Pros: the body itself is slow. Cons: leaving water at a factor of 0.5, `Sim`'s motion jumps from 0.5 to 1.0 m/s in one 20 ms tick, 25 m/s² against `a_max`'s 1.5, which the armor's restraint cannot see.

**Drag in MuJoCo.** Pros: real physics. Cons: a new door into `mujoco`, and `Sim` would still need the cap.

### Ditches and cliffs

**One solid kind of circles, a static geom on MuJoCo (chosen).** Pros: no new shape, the pillar's keep and its measured margin, and the base can back away from a rim as on `Sim`. Cons: a long cliff costs several of a world's 16 entities.

**Segments or polygons.** Pros: a straight edge. Cons: a new shape in every reader. **A cliff kind apart.** Pros: a cliff reads as one in the world file and on the radar. Cons: the same restraint under a second name. **No geom, held by `Sim`'s rule.** Pros: on MuJoCo a hole is no wall the base pushes against. Cons: a base held at a rim could not back away.

### Obstacles that move

**An obstacle with a human's walk, `stop` only, keep at least 0.5 m (chosen).** Pros: no contact on either body by construction, no new kind for any reader, no armor rule. Cons: a mover that stops for the body is a world rule; a mover from a detector would not stop.

**Any reaction.** Pros: a world may hold a boat that keeps its course whatever the body does. Cons: `through` rams a standing body, and `aside` lets the body push the mover past the fence. **`through` only.** Pros: a course the body cannot change, the simplest to predict. Cons: the same ram. **A kind of its own with a release rule.** Pros: MAGI could judge a release beside a boat by a rule of its own. Cons: a new kind in every reader, and a refusal for people the percept does not hold.

### When a landing zone shows

**From the world's start (chosen).** Pros: the armor keeps the body out of every zone always, so nothing has to move the body without an approved goto and no zone traps a depleted or ejected body. Cons: the stack never models a warning time.

**A warning time with an escape the reflex takes.** Pros: closer to canon, where the impact point is an estimate that comes before the fall, and the floor stays open until the zone shows. Cons: it moves the body under a hold, without an approved goto, which touches how Invariants 7 and 8 read, and a body that cannot leave in time stands under the object.

### After the landing

**A crater, a ditch with the zone's id and size (chosen).** Pros: one kind reused, and canon's third Lake Ashinoko. Cons: a crater over a world's only beacon ends every mission, which the loader does not refuse (Consequences). **Nothing.** Pros: the scene loses an entity once the danger has passed. Cons: the city's center would read as open floor. **A crater at a hidden spot within a spread.** Pros: a landing the zone only estimates, as the MAGI's estimate did in canon. Cons: fields that test nothing the zone does not.

### A goto into a landing zone

**The fact binds every unit under COURSE (chosen).** Pros: it only adds a no, its claims are exact in simulation, since the zone and its time are in the percept, and it reuses ADR-0009's section, veto and journal field. Cons: on such a goto one fact decides all three votes, the shared blind spot ADR-0009 names.

**The armor alone.** Pros: no MAGI change. Cons: MAGI approve a goto into a zone, and the bridge shows the approval. **An IMPACT section with a veto and a journal field of its own.** Pros: a chat unit reads a landing apart from a walker's course. Cons: a second section, veto word and field where one exists. **Persona lines.** Pros: no code, and each model reads the reason itself. Cons: ADR-0009's Option F moved gpt-oss-20b the wrong way. **A rule before MAGI.** Pros: one check, before any model is asked. Cons: a gate outside MAGI that no ballot records.

### Jev

**State unchanged, the veto in `jev_judge` (chosen).** Pros: ADR-0002's calibration stands, and the veto binds anyway. Cons: Jev itself reads a landing zone as open floor, so its nouls never see the harm and BALTHASAR-2's no is code's alone. **New destination phrases.** Pros: Jev itself would read the landing as harm. Cons: a full recalibration under ADR-0002's Action Item 3.

### A goto onto a human already within reach

**The fact binds every unit, on the answer (chosen).** Pros: S23 holds on every lineup by construction, in the shape S19 and S22 hold, every request stays byte for byte, and the journal keeps what each model voted. Cons: on such a goto one fact decides all three votes; a walker crossing at 1.2 m/s leaves the target in about a second, and the goto waits a deliberation.

**A COURSE section in the request too.** Pros: the chat units read why. Cons: S23's request and those of every world with a human near a target change, and the veto binds anyway. **A persona line.** Pros: no code. Cons: Option F's lesson, and Known issue 29 showed one line move a model both ways. **Accepting it as a gap of lineup A.** Pros: nothing changes. Cons: the gate fails, which `magi-eval` exists to stop, and a goto onto a person passes on 2 of 3. **A rule before MAGI.** Pros and cons as above.

## Trade-off Analysis

Fewest readers changed against modeling. Ground as physics would be truer to a wheel in mud, but it breaks the acceleration restraint on the way out and needs code in both bodies; as a cap on the top speed it is one restraint in the armor that only lowers the speed. Ditches, impact zones, craters and moving obstacles enter as kinds every reader already keeps the body off, so the change sits in the world file, the bodies, the bridge and MAGI's fact, and the armor, the reflex and the dummy plug keep their code.

A world rule against an armor rule for movers. The armor does not read a mover's velocity, as it does not read a walker's (Known issue 33); the world keeps a mover's keep wider than the base's braking, so no contact happens by construction. A mover a detector reports would not stop for the body, and then the armor needs the approach margin Known issue 33 leaves to the owner.

Honesty against reach. The landing fact claims only what the percept states, that the target lies inside a zone whose object lands in a given time; it needs no horizon, since the armor keeps the zone before the landing and the crater after, and in simulation it is never false. Its honesty moves to Phase 3 Task 5: a detector must give each zone as the whole region its prediction cannot rule out, or the fact and the armor's keep are both wrong without a sign. The fact on a human already within reach claims what ADR-0009 already counted, now in every unit's ballot.

## Consequences

Easier: worlds with water, mud, slopes, ditches, cliffs, boats and falling objects, flown by `Sim` and the MuJoCo base through the same armor; Episode 12's Sahaquiel as a scene, where MAGI refuse a goto into the landing zone 0/3 and the armor holds a racing pilot at its rim; lineup A holds S23 by construction.

Harder: a world with a long cliff spends its 16 entities fast; `tools/scenarios.json` gains scenarios with the new kinds, which hosted lineup A has run and lineup B has not, and no hosted mission has flown a world with the new kinds (PLAN, State and Known issues), where a hosted model may read an `impact`, `ditch` or `ground` line as harm where there is none; a world can cover its only beacon with a crater, a ditch or a zone, which the loader does not refuse, as it does not refuse a pillar on a beacon; the recorder grows by 55 to 58 B a line per ditch or crater, 69 to 91 B per landing zone and 82 to 91 B per obstacle that moves, plus a mean 48 B for a mover's velocity, as for a walker's (PLAN, Known issue 3), in worlds that hold them.

Known passes: a goto into a ditch or onto a mover's way is left to the armor and the planner; a release on ground is judged as anywhere; an HQ of an older build casts no landing veto beside a newer field unit, while the armor still keeps the body out, and ADR-0003 asks for one build on both sides.

Invariant 1 holds: no new handle on the body; movers and craters hold the body inside the body's own code, as humans do. Invariant 2 holds: verbs and their classes are untouched. Invariant 3 holds: the quorum and the tally are untouched, and both facts only turn ballots into a no while a fault stays a fault. Invariant 4 holds: the families are untouched, and one fact builder, now three rules, can decide all three votes on such a goto, which this ADR names as ADR-0009 did. Invariant 5 holds: the armor checks every goal and command as before and gains one restraint that only lowers the top speed; a goto approved into a crater still ends at its rim. Invariants 6 to 8 hold: no zone ever needs the body moved without an approved goto, the dummy plug sees the new solids as solids, and the reflex is unchanged. Invariant 9 holds: no new C library and no new `mujoco` door. Invariant 10 holds: the zones exist from the world's start, and a landing follows the world's clock as a walker does. Invariant 11 holds: the journal gains no kind of line and no field.

Revisit when Task 5 brings a detector (ground and ditches need a downward sensor or a map, and a landing zone its error region), when a real base brakes differently on ground (Open question 1), when the owner wants a warning time before a landing, or when 3D terrain comes (docs/decisions.md, 2D first). On acceptance ADR-0007's status gains "; what a chat unit reads extended by ADR-0009 and ADR-0010", ADR-0008's "; ditches, moving obstacles and craters on the MuJoCo base by ADR-0010" and ADR-0009's "; its binding extended to a human already within reach and to a falling object's landing zone by ADR-0010".

## Action Items

1. [x] Moving obstacles, ditches, ground and falling objects, each with its tests, its radar mark, the planner's handling and the mock's reading of its line, with every existing world and S1 to S23 sending the same requests as before.
2. [x] The fix of Known issue 37 as its own commit, checked on S12 and S23 on the mock and on hosted lineup A.
3. [x] Scenarios with a goto into a landing zone and canaries with every new line in PERCEPT; on the mock the gate holds on them.
4. [x] Each kind measured in mock missions on `Sim` with both drives and on the MuJoCo base, and the planner beside the reflex, on a terrain world.
5. [x] Episode 12's Sahaquiel as a scene, flown three times with every beat and recorded.
6. [x] Hosted lineup A's `magi-eval 10` on every scenario (PLAN, State); lineup B and hosted missions on worlds with the new kinds remain unmeasured.
7. [ ] Task 5's detector gives ground and ditches from a downward sensor or a map, and each landing zone as its error region.
8. [ ] The owner reviews the provisional decisions this work took (docs/decisions.md).
