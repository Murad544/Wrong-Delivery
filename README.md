# Wrong Delivery — The Worst Delivery Company

A 3D cooperative physics comedy / delivery simulation built in **Godot 4.x** using typed GDScript.

## Current Status: Milestone 02 — Single-Player Cargo Physics

Implemented strictly per `AGENTS.md` §4, §11, and §15 (Milestones 01–02):
- **Cargo Physics & Validated State Machine** (`cargo/cargo_body.gd`, `cargo/cargo_data.gd`):
  - `RigidBody3D` cargo with explicit validated state machine (`FREE`, `CARRIED`, `LOADED_UNSECURED`, `SECURED`, `UNLOADING`, `DELIVERED`), checkpoint reset (`F4`), and visual impact flash.
  - Reusable `CargoData` resource defining mass, durability, required carriers, fragility, and impact thresholds.
- **Spring/Damper Carry Controller & Grab Handles** (`cargo/carry_controller.gd`, `cargo/cargo_handle.gd`):
  - Force and torque-based carry controller (`apply_central_force` / `apply_torque`) with capped force/angular velocity and collision-exception handling so carried cargo collides cleanly with walls and doorways without launching the carrier.
  - `Q` / `R` rotation while carrying and automatic safe detach if separation distance exceeds `max_detach_distance`.
  - Single-carrier `CargoCrate` (`cargo/cargo.tscn`, `10 kg`, `1` carrier) and two-handle `SofaCargo` (`cargo/sofa_cargo.tscn`, `30 kg`, `2` carriers prepared; holding 1 handle alone applies only a slight tug and warns that 2 carriers are required).
- **Impact Damage Model** (`cargo/cargo_damage.gd`):
  - Collision severity evaluation with configurable speed threshold (`2.6 m/s`), brief damage cooldown (`0.35 s`) to avoid sustained-contact spam, and durability clamped to `[0, max_durability]`.
- **Physics Playground & Diagnostics HUD** (`scenes/levels/physics_playground.tscn`, `ui/game_hud.tscn`):
  - Dedicated physics playground with flat floor, crates, ramp & curb, doorway & narrow corridor, two-handle sofa, cargo bay mockup, and impact-test wall.
  - Live **Cargo Physics Diagnostics** overlay (`F3` toggle) displaying cargo state, durability, carrier count, linear speed, carry force (`N`), and last impact speed.

---

## Controls

| Input | On Foot | While Carrying Cargo | Debug / Level Hotkeys |
|---|---|---|---|
| `W / A / S / D` | Camera-relative movement | Capped carry movement (`2.5 m/s`) | — |
| `Mouse` | Orbit third-person camera | Orbit camera | — |
| `Left Shift` | Sprint (`7.0 m/s`) | Disabled while carrying | — |
| `Space` | Jump (`4.5 m/s`) | Disabled while carrying | — |
| `E` | Interact / Grab cargo handle | Release / Drop held cargo | — |
| `Q / R` | — | Rotate held cargo left / right | — |
| `Esc` | Release / recapture mouse | Release / recapture mouse | — |
| `F3` | — | — | Toggle Physics Diagnostics HUD |
| `F4` | — | — | Reset all cargo to checkpoint |
| `F5` | — | — | Switch between Main Level & Physics Playground |

---

## Running the Project & Validation

### 1. Open in Godot 4 Editor
Open `project.godot` in Godot 4.2+ and press **F5** (Run Project) to launch `res://scenes/levels/sofa_delivery.tscn` (press **F5** in-game to jump to `res://scenes/levels/physics_playground.tscn`, or run `physics_playground.tscn` directly with **F6**).

### 2. Headless Editor & Smoke Test Validation
From a terminal where `godot` is on your `PATH`:

```bash
# Validate project import & script parsing
godot --headless --editor --path . --quit

# Run Milestone 01 & Milestone 02 automated smoke tests
godot --headless --path . -s res://tests/milestone_01_smoke_test.gd
godot --headless --path . -s res://tests/milestone_02_smoke_test.gd
```

---

## Milestone 02 Manual QA Checklist

- [ ] Launch `scenes/levels/physics_playground.tscn` (or press `F5` inside the main scene).
- [ ] Verify the crates and sofa settle naturally on the floor without bouncing or jittering.
- [ ] Approach `StandardCrate` and press `E` to grab — walk through the narrow doorway and corridor, rotate with `Q` and `R`, and verify the crate stops against walls without clipping through geometry.
- [ ] Walk far enough from a wedged crate so the handle exceeds `max_detach_distance` (`3.2 m`) and verify it auto-detaches cleanly.
- [ ] Grab `RampDropCrate` at the top of the orange ramp, carry it to the edge, and drop it (`E`) or push it off the ledge — verify that gentle contacts below `2.6 m/s` deal `0` damage, while hard drops/impacts flash red and reduce durability once per cooldown window.
- [ ] Approach `PlaygroundSofa` and press `E` on either `Left Handle` or `Right Handle` — verify the prompt/HUD shows `1/2 carriers` and that one player alone cannot lift the oversized sofa off the floor.
- [ ] Press `F4` to reset all cargo back to their spawn transforms and full durability.
