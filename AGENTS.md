# Wrong Delivery — Codex Project Instructions

> **Purpose:** This is the authoritative product and engineering specification for the **Wrong Delivery** Godot 4 project. Codex must read this file before editing the project. Implement the game incrementally. Do **not** try to deliver the entire game in a single pass.
>
> **Working title:** Wrong Delivery — The Worst Delivery Company  
> **Genre:** 3D cooperative physics comedy / delivery simulation  
> **Platform:** Desktop PC first (macOS development; design for Windows/Linux)  
> **Engine:** Godot 4.x, latest stable version compatible with the local installation  
> **Programming language:** Typed GDScript  
> **Player count:** 2-player MVP; expand to 2–4 players after the MVP  
> **Art direction:** Bright, readable low-poly cartoon, slightly exaggerated character proportions  
> **Physics philosophy:** **Controlled chaos**: intuitive controls with unpredictable *cargo*, never unpredictable input handling.

---

## 0. Instructions for Codex: how to work

1. **Read this entire document** and inspect the existing project before modifying anything.
2. **Follow the active milestone** in §15. Unless explicitly instructed otherwise, implement **Milestone 01 only**. The rest of the file is forward-looking design context, not authorization to create every system now.
3. Make the smallest complete, testable increment. Do not silently introduce paid services, third-party addons, hosted backends, art packs, or plugins.
4. Prefer native Godot scenes, nodes, resources, and built-in multiplayer APIs. Use **typed GDScript** where practical, `@export` for gameplay tuning, and clear scene boundaries.
5. Separate game simulation, physics, networking, UI, and presentation. Keep important gameplay state **host-authoritative**.
6. If a design choice cannot be implemented safely or reliably with the installed Godot version, explain the deviation and offer the simplest supported implementation. Do not pretend an API exists.
7. Never claim that gameplay has been visually tested without actually running and inspecting the game. Headless validation is necessary but not sufficient.
8. At the end of each milestone, report: files changed, functionality, exact commands run, automated test results, manual testing checklist, known problems, and next recommended step.
9. Preserve existing working features; keep Git commits focused. Do not delete user-created assets, scenes, or configuration without explicit permission.
10. If the environment does not have Godot installed, still prepare files but disclose that parsing/runtime validation could not be completed.
11. Do not build multiplayer by making every client simulate the same free rigid body independently and assuming it will match. Shared physics must have a clear authoritative owner.
12. No telemetry, analytics, accounts, monetization, or AI API calls are required for the MVP.

### Definition of done for *any* milestone

- Main scene opens and runs with no script parse errors and no new critical runtime errors.
- Inputs are defined through Godot Input Map, not hardcoded key polling where avoidable.
- Exposed gameplay values are configurable without modifying core algorithms.
- A short manual QA script exists and works for that milestone.
- New state transitions are validated and do not allow illegal interactions.
- Where relevant, both host and client see consistent game state.
- Changes are clearly summarized; limitations are not concealed.

---

## 1. Product vision

Players are employees of the world's least competent delivery company. They accept absurd delivery contracts, load oversized or fragile objects into an unreliable truck, drive across a compact whimsical neighborhood, and then maneuver cargo into almost-impossible delivery destinations. Success is measured by **delivery completion**, **damage**, **time**, and **major mistakes**, not combat or grinding.

The game is funniest when the **team's plan** breaks down: two players disagree on which way to turn a sofa, a poorly secured package slides during a sharp corner, or a large object barely fits through a doorway. Controls themselves should remain predictable and responsive.

### Pillars

1. **Cooperative coordination:** Two people work on the same physical problem.
2. **Understandable physics:** The sofa visibly reacts to movement, impacts, tilt, and constraint, but should not jitter uncontrollably.
3. **Short repeatable missions:** Target roughly **5–8 minutes** for a familiar mission; not a strict timeout.
4. **Easy-to-learn controls:** A third-person control scheme familiar to PC players.
5. **Readable consequences:** Players can tell why damage or a delivery penalty happened.
6. **Escalating absurdity:** Additional cargo types and missions reuse core systems rather than demanding a new architecture every time.
7. **Fun first:** The very first sofa-carrying interaction must be fun before expanding content.

### Out of scope for first MVP

Open-world city, procedural map generation, public matchmaking, dedicated servers, account systems, competitive leaderboards, paid cosmetics, realistic vehicle simulation, walking freely inside a moving truck, complex rope physics, IK arm rigs, fully deformable furniture, advanced NPC AI, destructible buildings, large asset pipeline, mobile port.

---

## 2. First full mission: “The Impossible Sofa”

**Scenario:** Two workers transport an oversized sofa from a warehouse to a nearby customer's house.

**Player flow:**

1. Spawn near a small warehouse. The sofa and a drivable box truck are available.
2. Each player approaches a different sofa handle and presses **E** to grab.
3. Players carry, rotate, and maneuver the sofa through the warehouse exit.
4. Players place the sofa inside the truck's cargo area.
5. One player secures the sofa using cargo straps / a marked secure anchor (**F**).
6. One player drives. The other enters the passenger seat and monitors the cargo stability HUD.
7. Drive down a short road with a turn, a hill or bump, and a hazard.
8. Park, unsecure and unload the sofa.
9. Together carry the sofa through the house door and into the designated delivery volume.
10. The host validates delivery completion. Both players see the same score and a restart option.

**MVP win condition:** The assigned sofa enters the delivery zone in an allowed state, is released and stationary enough to count, and the host finalizes the result once. Do not count the object as delivered while it remains in the truck.

**MVP failure / recovery:** Dropped cargo can be retrieved; cargo should not become permanently stuck under normal play. Provide a reset-to-checkpoint mechanism if it gets wedged or falls outside the playable area. Early MVP should not rely on irreversible failure states.

**Acceptance test:** Two game instances can host/join, carry the same sofa, load it, drive it, unload it, place it in the destination, show identical results, and restart without relaunching the app.

---

## 3. PC control scheme and input actions

Use Godot Input Map actions with default bindings. Make sure context determines whether an input is interpreted on foot, while carrying, or seated in the truck.

| Input | On foot | Carrying | In truck |
|---|---|---|---|
| W/A/S/D | Camera-relative movement | Assisted movement while holding handle | W accelerate, S reverse/brake, A/D steer |
| Mouse | Orbit third-person camera | Orbit camera | Vehicle camera orbit |
| Left Shift | Sprint | No sprint (or slower capped movement) | Not used |
| Space | Jump | Not allowed for heavy cargo | Handbrake |
| E | Interact / grab / release | Release handle | Enter / exit vehicle |
| Q | Reserved / optional rotation | Rotate cargo left | Not used |
| R | Reserved / optional rotation | Rotate cargo right | Not used |
| F | Context action | Secure/unsecure loaded cargo | Context action if stationary, as appropriate |
| Esc | Pause / release mouse | Pause | Pause |

**Input implementation rules:**

- Define named actions, for example `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `interact`, `rotate_left`, `rotate_right`, `secure_cargo`, `handbrake`, `pause`.
- Use raycast / distance / line-of-sight checks to choose an interaction target. Do not allow grabbing through walls.
- Show the currently available interaction as a HUD prompt, e.g. `E — Grab sofa handle`.
- Prevent conflicting actions (jump while carrying an oversized sofa, enter the truck while holding cargo, secure cargo outside the truck, exit vehicle while traveling fast).
- Later support remapping and gamepad controls; they are not MVP blockers.

### Starting movement tuning (prototype, adjustable)

| Parameter | Value |
|---|---:|
| Walk speed | **5.0 m/s** |
| Sprint speed | Design/tune; begin around **7.0 m/s** |
| Carry speed | **2.5 m/s** |
| Jump velocity | **4.5 m/s** |
| Camera | Third person, orbit with mouse, collision-aware distance |

- Use `CharacterBody3D`, `move_and_slide()`, camera-relative horizontal vectors, gravity and jump velocity.
- Smooth acceleration and deceleration with configurable values, but prioritize responsive stopping.
- Keep camera logic local to each client; do not sync camera angles unnecessarily.
- Prevent the camera from clipping through solid level geometry (e.g., spring-arm or raycast-based camera obstruction).
- Make visual player orientation track movement unless carrying or context interaction changes it.

---

## 4. Cargo objects and physics

### Base object design

Use `RigidBody3D` for free physical cargo with a collision shape, visible mesh, configurable gameplay properties, and explicit state. Avoid frequent direct writes to a dynamic body's global transform. When carried, use force / torque and a target-following controller; if a simplified kinematic transport mode is introduced, make transitions explicit and tested.

**Suggested states:**

```text
FREE -> CARRIED -> LOADED -> (SECURED or UNSECURED) -> UNLOADING -> DELIVERED
```

Implement this as a robust state machine rather than a chain of unvalidated booleans. Support appropriate reverse transitions, such as `CARRIED -> FREE` and `SECURED -> LOADED_UNSECURED`. In an implementation, `SECURED` may be a substate of `LOADED`, provided the semantics are unambiguous.

| State | Behavior |
|---|---|
| FREE | Dynamic rigid-body simulation, world collision, gravity |
| CARRIED | Host applies assisted spring/damping forces; constrained tilt and capped angular velocity |
| LOADED_UNSECURED | Cargo sits inside cargo bay and responds to truck acceleration in a simplified local simulation |
| SECURED | Cargo attached to a valid truck anchor in a deterministic way; no routine sliding |
| UNLOADING | Cargo is detached into world-space handling; safe pose/velocity handoff |
| DELIVERED | No further pickup; result recorded once |

### Example tuning values

| Cargo | Mass | Durability | Required carriers | Handling | Fragility |
|---|---:|---:|---:|---|---|
| Giant sofa | **30 kg** | **100** | **2** | Medium | Low |
| Fragile vase | **3 kg** | **30** | **1** | Easy | High |

Treat these as **gameplay balancing numbers**, not physically accurate masses. Expose as a reusable `Resource` (`CargoData`) or exports so new cargo can be created without rewriting logic.

### Damage model

- Damage is based on collision severity (relative speed and/or impulses), not merely on contact count.
- Ignore tiny contacts with a configurable speed/impulse threshold.
- Add brief damage cooldown or collision coalescing so a sustained collision does not emit dozens of penalties.
- Show visible feedback: impact sound, damage flash, HUD damage indicator.
- Only **host** authoritatively calculates and applies damage in multiplayer.
- Bound durability within `[0, max_durability]`.
- Ensure moving the object into a secured state never creates spurious damage spikes.

### Stability and performance

- Choose appropriate collision layers and masks; avoid unwanted collisions between attached players and held cargo.
- Cap carry-controller forces, acceleration and angular velocity to avoid explosions/jitter.
- Use the physics tick for simulation (`_physics_process` or Godot-supported rigid-body integration hooks), not render frame timing.
- Test the sofa at rest, in corridors, against corners, while carried by one person, carried by two people and dropped.

---

## 5. Cooperative carrying: signature mechanic

**Design goal:** The object feels heavy and jointly controlled. Two-player disagreement causes resistance or tilt without making the game unplayable.

### Grab points

- The sofa has **two distinct grab handles** with local offsets and occupancy state.
- A player must be within a configurable reach distance and have line of sight to grab a free handle.
- Heavy cargo requires two players before full movement is enabled; one carrier may hold a handle briefly but cannot move the sofa normally.
- A player cannot grab multiple handles or cargo objects simultaneously.
- The host validates every request using authoritative player positions and object state.

### Assisted movement

1. Determine each carrier's movement intent on the host.
2. Compute a target pose from the carriers' attachment points and the sofa's handle offsets.
3. Apply bounded spring/damper forces and torque toward the target pose.
4. Respect walls and obstacles; do not teleport the sofa to keep handles attached.
5. Cap movement and rotation; allow some drift/tilt for comedy.
6. Recover gracefully if the controller becomes overconstrained.

**Behavior rules:**

| Inputs | Desired result |
|---|---|
| Both players move in same direction | Nearly full carrying speed |
| One moves, one stays | Slower progress and visible tilt/strain |
| Move in opposite directions | Little net progress, increased strain, modest rotation |
| One releases | Short grace period then drop / release other handle as appropriate |
| Players exceed separation limit | Auto-detach safely |
| Sofa meets a wall | Sofa stops against collision; no clipping or teleports |

- Provide a visible **strain meter** only if it helps explain the handling. Do not turn it into an unrelated button-mashing mechanic.
- Initial animations may be basic or placeholder. No character arm IK is required for the MVP.
- Avoid rigid joints between independently simulated networked player bodies for the first version; authoritative assisted movement is easier to control and test.
- The **first fun test** is two players carrying the sofa through a tight doorway. Optimize this experience before adding other cargo types.

---

## 6. Vehicle: arcade delivery truck

### Design

- One compact box-style delivery truck, easy to enter/exit, responsive steering and brakes.
- Use a simplified **custom arcade controller**, initially `CharacterBody3D` or equivalent stable body/controller, rather than requiring realistic wheel simulation.
- `VehicleBody3D` can be evaluated later but is not necessary for MVP.
- Use wheel mesh rotation, body roll and suspension bounce as **visual** feedback when useful.
- One driver at a time; one seated passenger in two-player MVP.
- Passenger can view cargo stability / warnings, but **cannot freely walk within a moving truck** in MVP.
- Prevent invalid transitions such as entering/exiting while carrying cargo; exiting at high vehicle speed should be restricted.

### Initial truck tuning (expose all values)

| Parameter | Starting value |
|---|---:|
| Max forward speed | **14 m/s** |
| Max reverse speed | **5 m/s** |
| Acceleration | **8 m/s²** |
| Braking deceleration | **14 m/s²** |
| Max steering angle | **30 degrees** |
| Handbrake | Strong longitudinal braking + reduced lateral grip |

These are prototype tuning values, not simulated automotive specifications.

### Cargo securing / transport

- Cargo can enter the rear cargo bay while truck is stopped/parked.
- A cargo bay volume identifies items that have been positioned correctly inside.
- `F` at a reachable anchor secures cargo to a valid slot; invalid positions show why securing is disallowed.
- **Secured:** anchor follows the truck in a deterministic transport mode. Routine turns should not move the cargo relative to the truck.
- **Unsecured:** use a **truck-local simplified sliding/tilt model** driven by acceleration, braking and turning, rather than trying to stack several free rigid bodies inside a moving kinematic vehicle.
- In the simplified model, derive approximate lateral acceleration from `lateral_acceleration ≈ forward_speed * yaw_rate`, where yaw rate is in radians/second; use longitudinal acceleration similarly.
- Cargo damage can occur if unsecured cargo slides into cargo-bay boundaries or when the vehicle suffers a major collision; compute on host.
- Convert cargo pose/velocity safely when transitioning between world-space rigid-body physics and truck-local mode; prevent sudden teleporting, penetration or damage spikes.
- Passenger HUD may display stability and warnings; avoid interactive stabilizing tools until the delivery loop works.

**Co-op division during driving:**

- Driver: route choice, speed, braking, avoiding obstacles.
- Passenger: watches cargo stability/condition and warns the driver.
- Later option: limited stabilization tool or improvised equipment upgrades.

---

## 7. Scoring and mission progression

Start with a simple, deterministic and explainable score.

```text
score = clamp(100 - damage_penalty - overtime_penalty - major_mistake_penalty, 0, 100)
```

- `damage_penalty`: based on percentage of durability lost.
- `overtime_penalty`: only after a generous target time; don't punish beginners too harshly.
- `major_mistake_penalty`: e.g. missing an optional handling condition, abandoning cargo, or using reset-to-checkpoint.
- No hidden random score changes.
- Only the host decides mission start/end, delivery acceptance and score.
- Show final time, cargo damage, penalties, final rating, and **Restart**.
- Use an explicit delivery zone with a valid cargo ID and a brief settled/released state requirement.
- Record completion once; do not allow repeated rewards by moving cargo in and out of the zone.

**MVP scope:** One contract, one sofa, one warehouse, a short road, one customer home, one score screen.

---

## 8. Networking: two-player host-authoritative model

### Transport and ownership

- Use Godot's high-level multiplayer with `ENetMultiplayerPeer` for **LAN host/join MVP**.
- One player's instance acts as host/server and also plays.
- Remote player connects as client.
- Host is the authoritative simulation owner for **all cargo, vehicle motion, damage, and mission state**. Client sends **inputs and intent requests**, not final authoritative transforms.
- Limit lobby to two players for MVP; architecture should avoid hardcoding assumptions that prevent 2–4 players later.
- Internet connectivity/port forwarding, relay services, friend invites, and NAT traversal are later milestones.

### Network responsibilities

| Entity / event | Strategy |
|---|---|
| Local camera | Client-only, no synchronization |
| Player controls | Client -> host input messages |
| Player positions | Host -> client state snapshots; interpolate remotely |
| Grab / release / secure | Reliable request to host; validate and replicate result |
| Cargo transform | Host -> client frequent unreliable ordered / sequenced snapshots as appropriate |
| Truck input | Driver -> host |
| Truck position | Host -> client frequent snapshots, interpolate |
| Damage + cargo state | Host authoritative; reliable transition notifications (and late-join snapshot) |
| Mission result | Reliable host message to all players |
| Cosmetic effects | Trigger locally or replicate minimal event information |

### Initial timing

- Physics simulation: **60 Hz**.
- Input sending: roughly **30 Hz** (initial target).
- World transform snapshots: roughly **20 Hz** (initial target).
- Tune based on observed latency, packet loss, bandwidth, and gameplay feel. These are not guaranteed optimal values.

### Security / validation

- Never trust a remote player's submitted position, cargo damage, score, or completion claim.
- On every grab request check player identity (`multiplayer.get_remote_sender_id()` where applicable), current authoritative distance, line of sight, occupied handles, cargo state and rate limits.
- Validate vehicle seat ownership and input ownership.
- Keep network IDs and node paths stable; provide explicit spawn/despawn lifecycle.
- Handle disconnects by releasing relevant grab handles, removing seat ownership and allowing recovery.
- Ensure late join/rejoin state can eventually be reconstructed; first LAN MVP may restrict joining during an active mission if documented.
- Use Godot RPC configuration (`@rpc`), `MultiplayerSpawner`, and `MultiplayerSynchronizer` where appropriate, but verify exact Godot 4.x API behavior. Do not blindly replicate every local transform.

### Sample RPC pattern (pseudocode, not drop-in code)

```gdscript
@rpc("any_peer", "call_remote", "reliable")
func request_grab(cargo_id: int, handle_id: int) -> void:
    if not multiplayer.is_server():
        return
    var sender_id := multiplayer.get_remote_sender_id()
    # Find authoritative player and cargo by registered IDs.
    # Validate reach, LOS, state, occupancy, and rate limit.
    # Apply state change on host; replicate accepted result.
```

Use explicit references or manager lookups; do not refer to an undefined singleton like `cargo_manager` without wiring it into the scene.

### Failure cases to test

- Two clients attempt the same handle simultaneously.
- One client disconnects while holding the sofa.
- Driver disconnects while the truck is moving.
- Host ends the mission while the client is loading a cargo item.
- Simulated latency ~50–100 ms and moderate packet loss.
- A delayed grab request arrives after the item is already secured.
- Objects should not duplicate, explode, or teleport across clients.

---

## 9. Interactions and feedback

- Raycast / sphere check for usable objects, with a clear interaction prompt.
- Small readable status indicators: carrier handle occupancy, cargo durability, whether cargo is secured, truck speed, delivery objective, elapsed time.
- When a request is rejected (too far, handle busy, cargo moving, truck not parked), show a short, useful reason.
- Highlight valid grab handles and delivery/secure zones without excessive UI clutter.
- Give cargo impact effects proportional to severity, not every tiny contact.
- Make the game forgiving: auto-reset stuck cargo, generous interaction volumes, cancellation-friendly transitions.
- On completion both players must see the same mission score and be able to restart.

---

## 10. Proposed reusable folder layout

Create folders as needed for the active milestone. Do not create dozens of empty placeholder scripts merely to satisfy this tree.

```text
wrong-delivery/
├── AGENTS.md
├── project.godot
├── scenes/
│   ├── main_menu.tscn
│   ├── lobby.tscn
│   └── levels/
│       ├── sofa_delivery.tscn
│       └── physics_playground.tscn
├── player/
│   ├── player.tscn
│   ├── player_controller.gd
│   ├── player_camera.gd
│   └── interaction_controller.gd
├── cargo/
│   ├── cargo.tscn
│   ├── cargo_body.gd
│   ├── cargo_data.gd
│   ├── carry_controller.gd
│   ├── cargo_damage.gd
│   └── cargo_manager.gd
├── vehicles/
│   ├── delivery_truck.tscn
│   ├── truck_controller.gd
│   └── cargo_bay.gd
├── missions/
│   ├── mission_manager.gd
│   ├── delivery_zone.gd
│   └── scoring_system.gd
├── networking/
│   ├── network_manager.gd
│   ├── player_spawner.gd
│   └── state_sync.gd
├── ui/
│   ├── game_hud.tscn
│   └── results_screen.tscn
├── assets/
│   ├── models/
│   ├── materials/
│   └── audio/
└── tests/
```

**Responsibility boundaries:**

- `player_controller.gd`: on-foot movement and input intents.
- `player_camera.gd`: local camera logic.
- `interaction_controller.gd`: nearby interactable detection and action request.
- `cargo_body.gd`: cargo rigid body and validated state transitions.
- `cargo_data.gd`: reusable item specifications.
- `carry_controller.gd`: assisted handle-based carrying, strain, detach.
- `cargo_damage.gd`: impact interpretation / damage rules.
- `cargo_manager.gd`: authoritative registry and request routing.
- `truck_controller.gd`: arcade movement and seat ownership.
- `cargo_bay.gd`: loaded cargo, securing, truck-local transport.
- `mission_manager.gd`: mission progression and timer.
- `delivery_zone.gd`: final physical delivery validation.
- `scoring_system.gd`: deterministic score calculation.
- `network_manager.gd`: host/join/disconnect, network session state.
- `state_sync.gd`: authoritative snapshot replication/interpolation.

---

## 11. Level design and physics playground

### First level blockout

Use primitive geometry only: a warehouse floor and open loading bay, short road, delivery truck parking area, a house with front door and final delivery zone. Include corners and a doorway that require rotating the sofa, but avoid impossible clearances. Physics object dimensions must be chosen alongside doorway size so success is physically possible.

### Separate playground

Before full mission polish, create a simple `physics_playground.tscn` with:

- Flat floor and a crate.
- Ramp and curb.
- Doorway and narrow corridor.
- Sofa with two handles.
- Cargo bay/anchor test area.
- Simple impact-test wall.
- Visible diagnostics (state, carry force, collision speed, network owner where relevant) behind a development debug toggle.

### Manual physics QA

- [ ] Crate drops naturally and settles without excessive bouncing.
- [ ] Carrying cannot pass solid cargo through walls.
- [ ] Two players can grab different handles.
- [ ] Sofa remains stable when both stand still.
- [ ] Sofa tilts/resists when players disagree without spinning uncontrollably.
- [ ] Releasing/disconnecting does not leave ghost grips or invalid state.
- [ ] Truck brakes sharply without excessive spinning.
- [ ] Unsecured cargo shifts with turns and braking.
- [ ] Secured cargo remains fixed during normal driving.
- [ ] Switching physics modes does not cause visible teleportation or bogus damage.
- [ ] Both peers see compatible cargo ownership and position.
- [ ] Mission can recover if cargo gets trapped or falls off the map.

---

## 12. Gameplay extensions after MVP (NOT included now)

### Future delivery contracts

1. **The Wedding Disaster:** Giant multi-layer cake wobbles during corners; protect it from tipping.
2. **Fish Express:** Large aquarium sloshes and loses water during impacts; visual slosh simulation can be simplified.
3. **The Impossible Sofa:** First MVP: big sofa and narrow entrance.
4. **Magnetic Madness:** Refrigerator attracts nearby metal objects at inconvenient times.
5. **The Giant Duck:** Oversized inflatable duck catches wind, making vehicle handling harder.

### Expandable mechanics

- **Almost Fits:** Oversized cargo just barely passes through doors; alternative routes and rotation puzzles.
- **Risk versus reward:** Securing cargo costs a little time but reduces damage risk; aggressive routes can save time.
- **Terrible equipment:** Trolley with a broken wheel, stretchy straps, cheap lifting machine, stronger cargo ties, improved suspension.
- **More levels:** Steep streets, tight apartment stairs, moving platforms, awkward parking spots.
- **4-player support:** More simultaneous carriers, roles, additional cargo pieces.
- **Controller support:** Gamepad input and sensible prompts.
- **Online connectivity:** Dedicated or relay-backed sessions; not needed for local prototype.

Do not begin these until the first end-to-end delivery mission passes the acceptance tests.

---

## 13. Performance, testing, and quality guidelines

- Target smooth desktop performance with a small number of dynamic objects. Profile before optimizing.
- Keep physics collision shapes simple (boxes/capsules/convex shapes); avoid expensive concave dynamic collisions.
- Test behavior at 60 Hz physics with varying render frame rates.
- Keep gameplay state changes deterministic and observable through debug logging.
- Unit-test pure calculations where practical: scoring, state-machine transitions, thresholds, allowed input states.
- Use headless Godot editor validation, for example `godot --headless --editor --path . --quit` where executable naming/flags match the installed version.
- For automated scene runs, run relevant headless scenes with timeout/quit conditions and check runtime logs.
- Do not mistake parse validation for successful gameplay or network testing.
- Maintain a `README.md` with installation, controls, running two instances, test scenarios, and known limitations.
- Implement basic crash-safe and invalid-state-safe behavior for network interruptions and physics reset situations.
- Do not hardcode file system absolute paths; use `res://` and `user://` appropriately.

---

## 14. Timeline / planning assumptions

A plausible sequence for a part-time solo developer assisted by Codex is approximately **six milestones**, perhaps **several weeks or more** depending on networking and physics iterations. Do **not** assume any exact schedule is guaranteed. Prioritize quality gates over dates.

The most likely risks are:

1. Multiplayer physics desynchronization.
2. Sofa-to-player attachment jitter.
3. Switching between free rigid-body and truck-local cargo simulation.
4. Vehicle handling when using simplified movement.
5. Complex geometry around doors and unloading zones.

Mitigation: make each system separately playable and tested, then integrate.

---

## 15. Milestone execution plan (strict order)

### Milestone 01 — Player and test environment **[DEFAULT ACTIVE MILESTONE]**

**Build:**

- Working Godot 4 project, with `project.godot` and runnable main scene.
- Primitive low-poly blockout of a warehouse, short street, and customer house.
- Third-person `CharacterBody3D` player with camera-relative WASD movement, Shift sprint, Space jump, smooth acceleration/deceleration, mouse-orbit camera, proper collision.
- Simple, reusable raycast + distance + line-of-sight interaction system, with on-screen prompt.
- Input Map actions and reasonable configuration via `@export`.
- Organize files cleanly, without writing unneeded future systems.

**Do not build yet:** sofa physics, cargo handling, truck, missions, network sync, lobby or scores.

**Acceptance:** Game launches without parse errors, player walks from warehouse to house, cannot walk through walls, camera avoids clipping, jump/sprint work, interaction prompt appears only at valid targets, no critical runtime errors.

**Deliver:** Runnable scene + short manual test script + exact validation output.

### Milestone 02 — Single-player cargo physics

**Build:** Free crate and sofa test models with `RigidBody3D`, interaction/grab/drop, single-person test-carry for crate, damage threshold, state machine, cargo playground. For heavy sofa, prepare handles but do not claim two-person mechanics work yet.

**Acceptance:** Crate can be grabbed, moved through a doorway, dropped and pushed; never moves through walls or violently jitters; damage only on meaningful impacts.

### Milestone 03 — Arcade truck and cargo bay

**Build:** Drivable truck, seats (single-player test role), loading/unloading, secure/unsecure anchors, truck-local unsecured cargo movement, collision/damage, vehicle HUD.

**Acceptance:** Truck responds predictably, stops/turns stably, secured cargo remains anchored, unsecured cargo slides under aggressive driving, safe transition back to free cargo.

### Milestone 04 — Two-player local multiplayer

**Build:** LAN lobby host/join, two players, spawning, input messages, host-owned objects, state snapshots, remote interpolation, server-validated interactions, disconnect handling.

**Acceptance:** Two instances connect and show matching authoritative state; no duplicate cargo, no grabbing through walls, no unsafe ownership transitions; basic 50–100 ms simulated latency remains playable.

### Milestone 05 — True cooperative sofa carry

**Build:** Two handles, occupancy, co-op carrying force controller, disagreement/strain behavior, safe detach, collision-safe large-object handling, network sync.

**Acceptance:** Two players carry a sofa through doorway and into truck, can coordinate rotation, cannot ghost through walls or spin uncontrollably; disconnect/release is safe.

### Milestone 06 — Complete sofa delivery mission

**Build:** Mission triggers, delivery zone, timer, damage/time/major mistake penalties, synchronized result screen and restart loop.

**Acceptance:** Both players complete warehouse -> truck -> drive -> house -> drop-off, receive identical scoring and can restart without relaunch. A complete round should be fun in repeated playtests.

---

## 16. Next instruction to Codex

If this is a new project and the user has not asked for another milestone, begin now with **Milestone 01 only**. Inspect the repository, create its minimal Godot foundation, run available headless validation, and report the playable result. Do not generate an entire hypothetical project without executing tests or reporting what remains unverified.

When the user says **“Proceed to Milestone 02”**, evaluate whether Milestone 01 meets its acceptance criteria before beginning cargo physics. Continue analogously for later milestones.

---

## 17. Final design rules / non-negotiables

- **Controlled chaos** is the design north star.
- User-facing controls are predictable; objects and situations create surprises.
- **Two-player sofa carrying** and **a complete delivery** are the MVP's defining loops.
- Start with **LAN multiplayer**, not online matchmaking.
- Use **server/host authority** for shared physics and game state.
- Keep the truck physics and in-truck cargo mechanics intentionally simplified.
- New contracts should mainly recombine proven systems.
- Codex must build **incrementally, test honestly, and explain limitations**.
- Never prioritize asset polish over the first fun, stable co-op delivery.
