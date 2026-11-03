# Wrong Delivery — The Worst Delivery Company

A 3D cooperative physics comedy / delivery simulation built in **Godot 4.x** using typed GDScript.

## Current Status: Milestone 03 — Arcade Truck & Cargo Bay

Implemented strictly per `AGENTS.md` §6 and §15 (Milestones 01–03):
- **Arcade Delivery Truck** (`vehicles/truck_controller.gd`, `vehicles/delivery_truck.tscn`, `vehicles/truck_interactable.gd`):
  - Custom `CharacterBody3D` arcade vehicle controller with exposed tuning parameters (`max_forward_speed = 14.0 m/s`, `max_reverse_speed = 5.0 m/s`, `acceleration = 8.0 m/s²`, `braking_deceleration = 14.0 m/s²`, `max_steering_angle_degrees = 30.0°`, and handbrake with longitudinal braking + lateral slip).
  - Driver Seat and Passenger Seat interactables with state validation (blocks entering while holding cargo; blocks exiting while moving faster than `2.0 m/s`).
  - Visual wheel rotation, front wheel steering, and cab roll/pitch feedback.
- **Cargo Bay & Simplified Local Sliding Model** (`vehicles/cargo_bay.gd`):
  - Detects cargo placed inside the rear cargo bed and transitions it into `LOADED_UNSECURED` transport mode.
  - **Unsecured Cargo (`LOADED_UNSECURED`)**: Slides and tilts in truck-local space based on longitudinal acceleration/braking and turning (`lateral_acceleration = forward_speed * yaw_rate`). Impacts against cargo bay walls deal severity-based damage.
  - **Secured Cargo (`SECURED`)**: Pressing **`F`** (or **`E`**) at the rear yellow cargo strap anchor straps loaded cargo deterministically with visible yellow crisscross straps (`StrapVisuals`); routine turns and braking do not shift secured cargo.
  - **Safe Unloading (`UNLOADING -> CARRIED`)**: Grabbing unsecured cargo while the truck is parked transitions it back to world-space dynamic physics without teleportation or bogus damage spikes.
- **Vehicle & Cargo Stability HUD** (`ui/game_hud.gd`):
  - Displays current seat role (`On Foot` / `Driver` / `Passenger`), truck speed (`m/s` and `km/h`), lateral acceleration, handbrake status, loaded cargo count, and real-time Cargo Stability `%` + warnings.

---

## Controls

| Input | On Foot | Carrying Cargo | In Delivery Truck |
|---|---|---|---|
| `W / A / S / D` | Camera-relative movement | Assisted carry (`2.5 m/s`) | `W` accelerate, `S` brake/reverse, `A/D` steer |
| `Mouse` | Orbit third-person camera | Orbit camera | Vehicle orbit camera |
| `Left Shift` | Sprint (`7.0 m/s`) | Disabled | — |
| `Space` | Jump (`4.5 m/s`) | Disabled | Handbrake |
| `E` | Interact / Grab / Enter seat | Drop held cargo | Exit seat (when stopped/slow) |
| `Q / R` | — | Rotate cargo left / right | — |
| `F` | Strap / unstrap cargo at bay | — | — |
| `Esc` | Release / recapture mouse | Release / recapture mouse | Release / recapture mouse |
| `F3` / `F4` / `F5` | `F3` HUD Diagnostics | `F4` Reset Truck & Cargo | `F5` Switch Level / Playground |

---

## Running the Project & Validation

### 1. Open in Godot 4 Editor
Open `project.godot` in Godot 4.2+ and press **F5** (Run Project) to launch `res://scenes/levels/sofa_delivery.tscn` (press **F5** in-game to switch between the main neighborhood level and `res://scenes/levels/physics_playground.tscn`).

### 2. Headless Editor & Smoke Test Validation
From a terminal where `godot` is on your `PATH`:

```bash
# Validate project import & script parsing
godot --headless --editor --path . --quit

# Run Milestone 01, 02 & 03 automated smoke tests
godot --headless --path . -s res://tests/milestone_01_smoke_test.gd
godot --headless --path . -s res://tests/milestone_02_smoke_test.gd
godot --headless --path . -s res://tests/milestone_03_smoke_test.gd
```

---

## Milestone 03 Manual QA Checklist

- [ ] Launch `scenes/levels/sofa_delivery.tscn` — verify the yellow-and-white **Delivery Truck** is parked outside the warehouse loading bay (`z = 11.5`).
- [ ] Grab `WarehouseCrate` (`E`) inside the warehouse and try to enter the Driver Door while holding it — verify entry is rejected (`Release held cargo before entering truck`).
- [ ] Walk up the truck's rear ramp and press `E` to drop the crate inside the cargo bay — verify the HUD shows `State: LOADED_UNSECURED` and `Cargo Bay: 1 item(s)`.
- [ ] Enter the **Driver Seat** (`E` at the left cab door) and drive down the street with sharp turns and hard braking — verify the **unsecured crate visibly slides and tilts** inside the bed, reducing Stability `%` and taking damage if slammed into the side walls.
- [ ] Try pressing `E` to exit the truck while driving fast — verify exit is blocked until you slow down (`<= 2.0 m/s`).
- [ ] Park the truck, exit (`E`), walk to the yellow **Cargo Strap Anchor** at the rear-left corner of the truck bed, and press **`F`** (or `E`) — verify the yellow crisscross cargo straps appear and the HUD shows `State: SECURED` / `Bay Status: SECURED`.
- [ ] Re-enter the Driver Seat and drive aggressively around corners and over the speed bump — verify the **secured crate stays completely fixed** inside the bay (`Stability: 100%`).
- [ ] Park at the customer house, exit (`E`), press **`F`** at the rear strap anchor to unsecure the crate, and press **`E`** on the crate to unload and carry it into the house — verify a smooth transition back to `CARRIED` with zero bogus damage.
