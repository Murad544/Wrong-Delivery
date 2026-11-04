# Wrong Delivery — The Worst Delivery Company

A 3D cooperative physics comedy / delivery simulation built in **Godot 4.x** using typed GDScript.

## Current Status: Milestone 06 — Complete Sofa Delivery Mission & Neighborhood Map

Implemented strictly per `AGENTS.md` §2, §7, §8, and §15 (Milestones 01–06 Complete):
- **Expanded Low-Poly Neighborhood Map** (`scenes/levels/sofa_delivery.tscn`):
  - **Warehouse Compound (`z = -8..+6`)**: Brick loading bay with steel roof trusses, storage shelving racks, dispatch desk, safety bollards, interior partition doorway (`2.4m` wide), and marked loading dock parking apron.
  - **Main Avenue (`z = 6..44`)**: Two-lane road with dashed centerlines, sidewalks, low-poly trees, colorful neighboring buildings (Corner Bakery, Hardware Shop, Yellow Townhouse), a smooth rounded speed bump (`z = 19.5`), and an S-curve roadwork barrier chicane (`z = 26..33`).
  - **Canal Bridge Overpass (`x = 10..20, z = 44`)**: Gentle sloped bridge (`8°` approach/descent ramps + flat bridge deck + red guardrails) crossing a blue water canal onto Maple Street.
  - **Customer Estate at 20 Maple Street (`x = 38, z = 44`)**: Neighboring mint cottage (`18 Maple St`), paved driveway apron, garden fences, front porch, a tight **`2.05m` front doorway** (requiring pivoting/rotating the `2.2m` sofa lengthwise), an L-turn interior hallway with a living room table obstacle, and the glowing green **`DeliveryZone`** (`x = 41.2, z = 46.8`).
- **Host-Authoritative Mission Loop, Delivery Zone & Scoring** (`missions/mission_manager.gd`, `missions/delivery_zone.gd`, `missions/scoring_system.gd`, `ui/results_screen.gd`):
  - **Physical Settlement Validation (`DeliveryZone`)**: Verifies the assigned `giant_sofa` is inside the zone, unloaded from the truck, released by all carriers (`FREE` state), and settled below `0.45 m/s` for `1.2 s` before finalizing delivery once (`CargoState.DELIVERED`).
  - **Deterministic Scoring (`ScoringSystem`)**:
    `score = clamp(100 - damage_penalty - overtime_penalty - major_mistake_penalty, 0, 100)`
  - **Synchronized Results & In-Game Restart (`ResultsScreen`, `StateSync`)**: Replicates the final score breakdown and rating (`S` through `D`) to both Host and Client, and allows restarting the entire mission without relaunching the app.

---

## Controls & Mac-Friendly Hotkeys

| Input | On Foot | Carrying Cargo / Sofa | In Delivery Truck |
|---|---|---|---|
| `W / A / S / D` | Camera-relative movement | Co-op assisted carry (`2.5 m/s`) | `W` accelerate, `S` brake/reverse, `A/D` steer |
| `Mouse` | Orbit third-person camera | Orbit camera | Vehicle orbit camera (with auto-follow) |
| `Left Shift` | Sprint (`7.0 m/s`) | Disabled | — |
| `Space` | Jump (`4.5 m/s`) | Disabled | Handbrake |
| `E` | Interact / Grab handle / Seat | Release held handle | Exit seat (when stopped/slow) |
| `Q / R` | — | Rotate cargo/sofa left / right | — |
| `F` | Strap / unstrap cargo at bay | — | — |
| `Esc` | Release / recapture mouse | Release / recapture mouse | Release / recapture mouse |
| **`1` / `2`** | **`1`: Host LAN Game** | **`2`: Join LAN (`127.0.0.1`)** | — |
| `3` / `4` / `5` / `6` | `3`: Toggle HUD | `4`: Reset Checkpoint (Host) | `5`: Switch Scene / `6`: Latency Sim |

---

## Headless Smoke Tests
```bash
godot --headless --editor --path . --quit
godot --headless --path . -s res://tests/milestone_01_smoke_test.gd
godot --headless --path . -s res://tests/milestone_02_smoke_test.gd
godot --headless --path . -s res://tests/milestone_03_smoke_test.gd
godot --headless --path . -s res://tests/milestone_04_smoke_test.gd
godot --headless --path . -s res://tests/milestone_05_smoke_test.gd
godot --headless --path . -s res://tests/milestone_06_smoke_test.gd
```

---

## Milestone 06 Manual QA Checklist

- [ ] Launch 2 instances (`Debug -> Customize Run Instances -> 2`); press **`1`** in Window 1 (Host) and **`2`** in Window 2 (Client).
- [ ] Verify the top-center **Mission Banner** shows `Step 1/5: Grab The Impossible Sofa...`, live timer (`00:00 / 05:00`), `Sofa Integrity: 100%`, and `Mistakes: 0`.
- [ ] Together grab `LeftHandle` and `RightHandle` (`E`), carry the sofa out the warehouse bay and up the truck's rear ramp, press `E` to set it in the truck bed, and press `F` at the yellow strap anchor to secure it.
- [ ] Enter Driver and Passenger seats (`E`), drive down Main Avenue over the speed bump, weave through the orange roadwork barriers, turn East at the intersection, drive over the canal bridge hill, and park in the driveway at **20 Maple Street**.
- [ ] Exit the truck (`E`), unstrap the sofa (`F`), grab both handles (`E`), and pivot/rotate (`Q`/`R`) the `2.2m` sofa through the `2.05m` front doorway and around the interior corner wall onto the glowing green **Delivery Zone** rug.
- [ ] Verify the banner prompts `Sofa in zone — Press E to release handles!` while held; press **`E`** on both players to release it and watch the `Verifying delivery...` progress reach `100%`.
- [ ] Confirm both Host and Client display the identical **Results Screen** with elapsed time, durability, penalties, rating, and final score, and click **Restart Mission** (or press `Enter`) to reset the entire mission cleanly.
