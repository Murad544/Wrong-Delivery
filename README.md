# Wrong Delivery — The Worst Delivery Company

A 3D cooperative physics comedy / delivery simulation built in **Godot 4.x** using typed GDScript.

## Current Status: Milestone 04 — Two-Player LAN Multiplayer

Implemented strictly per `AGENTS.md` §8 and §15 (Milestones 01–04):
- **Host-Authoritative LAN Networking** (`networking/network_manager.gd`, `scenes/lobby.tscn`, `scenes/lobby.gd`):
  - `ENetMultiplayerPeer` LAN host/join on UDP port `7777` (up to 2 players for MVP, configurable via `max_players`).
  - Instant in-game hotkeys (**`F1`** to Host LAN, **`F2`** to Join `127.0.0.1:7777`), standalone `scenes/lobby.tscn` UI, and command-line flags (`--host`, `--join`, `--ip=...`, `--port=...`).
- **Player Spawning & Disconnect Recovery** (`networking/player_spawner.gd`):
  - Spawns distinct color-coded workers (Orange for Host Peer 1, Blue for Client Peer 2).
  - Keeps camera and input listeners strictly local to each client.
  - Automatically releases held cargo handles and clears vehicle seat ownership if a peer disconnects mid-carry or mid-drive.
- **Authoritative State Sync, Validation & Latency Simulation** (`networking/state_sync.gd`, `cargo/cargo_manager.gd`):
  - Client sends movement and driving inputs at `30 Hz` (`unreliable_ordered`) and interaction requests via `reliable` RPCs.
  - Host validates every grab, seat, and strap request against authoritative player distance, line-of-sight raycast (no grabbing through walls), handle occupancy, and per-peer rate limits.
  - Host broadcasts authoritative world snapshots (`20 Hz`) for players, cargo, and the truck; Client disables independent free `RigidBody3D` physics on cargo and interpolates smoothly.
  - Built-in **Simulated Latency & Packet Loss toggle (`F6`)** (`0 ms` / `60 ms, 2% loss` / `100 ms, 4% loss`).

---

## Controls & Multiplayer Hotkeys

| Input | On Foot | Carrying Cargo | In Delivery Truck |
|---|---|---|---|
| `W / A / S / D` | Camera-relative movement | Assisted carry (`2.5 m/s`) | `W` accelerate, `S` brake/reverse, `A/D` steer |
| `Mouse` | Orbit third-person camera | Orbit camera | Vehicle orbit camera (with auto-follow) |
| `Left Shift` | Sprint (`7.0 m/s`) | Disabled | — |
| `Space` | Jump (`4.5 m/s`) | Disabled | Handbrake |
| `E` | Interact / Grab / Enter seat | Drop held cargo | Exit seat (when stopped/slow) |
| `Q / R` | — | Rotate cargo left / right | — |
| `F` | Strap / unstrap cargo at bay | — | — |
| `Esc` | Release / recapture mouse | Release / recapture mouse | Release / recapture mouse |
| **`F1` / `F2`** | **`F1`: Host LAN Game** | **`F2`: Join LAN (`127.0.0.1`)** | — |
| `F3` / `F4` / `F5` / `F6` | `F3` HUD Diagnostics | `F4` Reset (Host) | `F5` Switch Level / `F6` Latency Sim |

---

## Running Two Game Instances Locally

1. **In Godot 4 Editor**:
   - Go to **Debug -> Customize Run Instances...**, check **Enable Multiple Instances**, and set **2 instances** (or launch a second instance from terminal).
2. **In Instance 1 (Host)**:
   - Press **`F1`** to host on UDP port `7777` (HUD shows `Hosting LAN on port 7777`).
3. **In Instance 2 (Client)**:
   - Press **`F2`** to join `127.0.0.1:7777` (HUD shows `Connected as Client` and spawns the Blue player next to the Orange host player).
4. **Testing Simulated Latency**:
   - Press **`F6`** to cycle between `0 ms`, `60 ms (2% loss)`, and `100 ms (4% loss)`.

### Headless Smoke Tests
```bash
godot --headless --editor --path . --quit
godot --headless --path . -s res://tests/milestone_01_smoke_test.gd
godot --headless --path . -s res://tests/milestone_02_smoke_test.gd
godot --headless --path . -s res://tests/milestone_03_smoke_test.gd
godot --headless --path . -s res://tests/milestone_04_smoke_test.gd
```

---

## Milestone 04 Manual QA Checklist

- [ ] Launch two instances of the game; press **`F1`** in Instance 1 (Host) and **`F2`** in Instance 2 (Client).
- [ ] Verify both players see each other (Orange Host and Blue Client) and move smoothly across both windows.
- [ ] Have the Client grab `WarehouseCrate` (`E`), carry it into the truck cargo bay, drop it (`E`), and press `F` at the rear strap anchor — verify the Host sees the crate carried, loaded, and strapped with identical durability and state.
- [ ] Have one player enter the **Driver Seat** and the other enter the **Passenger Seat**, then drive down the street — verify both windows show synchronized truck movement and cargo bay stability telemetry.
- [ ] Press **`F6`** to enable `60 ms` / `100 ms` simulated latency and verify movement and cargo snapshots remain smooth and playable.
- [ ] Close the Client window while the Client is holding a crate or driving the truck — verify the Host cleanly releases the crate handle / clears the driver seat without errors or ghost grips.
