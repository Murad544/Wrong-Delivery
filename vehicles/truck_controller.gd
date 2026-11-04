class_name TruckController
extends CharacterBody3D

signal occupant_changed(driver: Node3D, passenger: Node3D)
signal truck_feedback(message: String, is_error: bool)
signal drift_boost_triggered(boost_count: int)

@export_group("Arcade Driving Tuning")
@export_range(4.0, 30.0, 0.5) var max_forward_speed: float = 14.0
@export_range(2.0, 15.0, 0.5) var max_reverse_speed: float = 5.0
@export_range(2.0, 25.0, 0.5) var acceleration: float = 8.0
@export_range(4.0, 35.0, 0.5) var braking_deceleration: float = 14.0
@export_range(10.0, 50.0, 1.0) var max_steering_angle_degrees: float = 30.0
@export_range(8.0, 40.0, 1.0) var handbrake_deceleration: float = 22.0
@export_range(0.0, 0.9, 0.05) var handbrake_lateral_slip: float = 0.55
@export_range(1.0, 12.0, 0.5) var coasting_deceleration: float = 3.5
@export_range(1.5, 6.0, 0.1) var wheelbase: float = 2.6
@export_range(0.5, 5.0, 0.1) var max_safe_exit_speed: float = 2.0

@export_group("Arcade Drift & Boost")
@export_range(3.0, 10.0, 0.5) var min_drift_speed: float = 4.5
@export_range(10.0, 45.0, 1.0) var max_drift_slip_degrees: float = 28.0
@export_range(1.0, 2.2, 0.05) var drift_yaw_multiplier: float = 1.45
@export_range(1.0, 8.0, 0.5) var drift_drag_deceleration: float = 3.2
@export_range(0.4, 2.0, 0.05) var drift_charge_time_seconds: float = 0.70
@export_range(1.05, 1.4, 0.02) var drift_boost_speed_multiplier: float = 1.22
@export_range(0.3, 1.8, 0.1) var drift_boost_duration: float = 0.90

var forward_speed: float = 0.0
var current_steer_angle_rad: float = 0.0
var yaw_rate: float = 0.0
var longitudinal_acceleration: float = 0.0
var lateral_acceleration: float = 0.0
var is_handbrake_active: bool = false
var is_drifting: bool = false
var drift_slip_angle_rad: float = 0.0
var drift_charge_ratio: float = 0.0
var drift_boost_timer: float = 0.0
var drift_boost_count: int = 0

var driver_actor: Node3D = null
var passenger_actor: Node3D = null

var _net_driver_throttle: float = 0.0
var _net_driver_steer: float = 0.0
var _net_driver_handbrake: bool = false

var _has_net_snapshot: bool = false
var _interp_target_pos: Vector3 = Vector3.ZERO
var _interp_target_yaw: float = 0.0

var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _horiz_velocity: Vector3 = Vector3.ZERO
var _wheel_spin_angle: float = 0.0
var _suspension_offset_y: float = 0.0
var _suspension_vel_y: float = 0.0
var _prev_world_y: float = 0.0
var _beacon_rot_angle: float = 0.0
var _drift_smoke_l: CPUParticles3D = null
var _drift_smoke_r: CPUParticles3D = null
var _taillight_mat: StandardMaterial3D = null
var _beacon_pivot_l: Node3D = null
var _beacon_pivot_r: Node3D = null

@onready var visual_root: Node3D = $VisualRoot
@onready var walkable_bed: PhysicsBody3D = get_node_or_null("WalkableBedAndRamp") as PhysicsBody3D
@onready var cargo_bay: CargoBay = $CargoBay
@onready var driver_seat_marker: Marker3D = $Seats/DriverSeatMarker
@onready var passenger_seat_marker: Marker3D = $Seats/PassengerSeatMarker
@onready var driver_exit_marker: Marker3D = $Seats/DriverExitMarker
@onready var passenger_exit_marker: Marker3D = $Seats/PassengerExitMarker
@onready var wheel_fl: Node3D = get_node_or_null("VisualRoot/WheelFL") as Node3D
@onready var wheel_fr: Node3D = get_node_or_null("VisualRoot/WheelFR") as Node3D
@onready var wheel_rl: Node3D = get_node_or_null("VisualRoot/WheelRL") as Node3D
@onready var wheel_rr: Node3D = get_node_or_null("VisualRoot/WheelRR") as Node3D


func _ready() -> void:
	_spawn_transform = global_transform
	_prev_world_y = global_position.y
	collision_layer = 16 # Layer 5: Vehicle (bitmask 16)
	collision_mask = 1 # Collide with Environment (1) only; Cargo (8) must never push/launch the truck
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.35
	floor_constant_speed = true
	floor_block_on_wall = false
	wall_min_slide_angle = 0.0

	if walkable_bed != null:
		add_collision_exception_with(walkable_bed)

	if cargo_bay != null:
		cargo_bay.truck_owner = self

	var interactables_root: Node = get_node_or_null("Interactables")
	if interactables_root != null:
		for child: Node in interactables_root.get_children():
			if child is TruckInteractable:
				var ti: TruckInteractable = child as TruckInteractable
				ti.truck_owner = self

	_setup_enhanced_truck_visuals()


func is_host_simulation() -> bool:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return true
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return true
	return multiplayer.is_server()


func _physics_process(delta: float) -> void:
	if not is_host_simulation():
		_interpolate_client_state(delta)
		_sync_seated_occupants()
		_update_visual_feedback(delta)
		return

	var throttle_input: float = 0.0
	var steer_input: float = 0.0
	var handbrake_input: bool = false

	if driver_actor != null and is_instance_valid(driver_actor):
		if bool(driver_actor.get("is_local_player")):
			throttle_input = Input.get_axis("move_back", "move_forward")
			steer_input = Input.get_axis("move_right", "move_left")
			handbrake_input = Input.is_action_pressed("handbrake")
		else:
			throttle_input = _net_driver_throttle
			steer_input = _net_driver_steer
			handbrake_input = _net_driver_handbrake
	else:
		# Parked when no driver is in the cab
		handbrake_input = true

	apply_driving_step(delta, throttle_input, steer_input, handbrake_input)

	var pre_slide_speed: float = absf(forward_speed)
	if driver_actor != null or pre_slide_speed > 0.02 or not is_on_floor():
		move_and_slide()
	else:
		velocity = Vector3.ZERO
		_horiz_velocity = Vector3.ZERO

	# Detect vertical bump traversal for suspension bounce
	var dy: float = global_position.y - _prev_world_y
	_prev_world_y = global_position.y
	if absf(dy) > 0.008 and pre_slide_speed > 1.5:
		_suspension_vel_y += clampf(dy * 18.0, -2.5, 2.5)

	# Detect true wall crashes (only contacts well above wheel/curb height: local_y > 0.55m)
	# and push knockable RigidBody3D road props (cones, barrels) smoothly out of the way
	if get_slide_collision_count() > 0 and pre_slide_speed > 0.5:
		for i in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			if col == null:
				continue
			var collider: Object = col.get_collider()
			if collider is RigidBody3D:
				var rb: RigidBody3D = collider as RigidBody3D
				var push_dir: Vector3 = (-col.get_normal() + Vector3(0.0, 0.35, 0.0)).normalized()
				rb.apply_central_impulse(push_dir * clampf(pre_slide_speed * 2.5, 2.0, 18.0))
				continue

			var contact_local_y: float = col.get_position().y - global_position.y
			var normal: Vector3 = col.get_normal()
			if normal.y < 0.25 and contact_local_y > 0.55 and pre_slide_speed > 1.0:
				var forward_dir: Vector3 = -global_transform.basis.z.normalized()
				var head_on_factor: float = absf(forward_dir.dot(normal))
				if head_on_factor > 0.4:
					var crash_severity: float = pre_slide_speed * head_on_factor
					forward_speed *= (1.0 - clampf(head_on_factor * 0.85, 0.3, 0.92))
					_horiz_velocity = _horiz_velocity.slide(normal)
					is_drifting = false
					drift_charge_ratio = 0.0
					if cargo_bay != null and crash_severity > 3.5:
						cargo_bay.apply_vehicle_crash_impulse(crash_severity)
					break

	_sync_seated_occupants()
	_update_visual_feedback(delta)

	if cargo_bay != null:
		cargo_bay.step_bay_physics(
			delta,
			longitudinal_acceleration,
			lateral_acceleration,
			is_stationary_for_cargo()
		)


func apply_driving_step(
	delta: float,
	throttle_input: float,
	steer_input: float,
	handbrake_pressed: bool
) -> void:
	var prev_forward_speed: float = forward_speed
	var was_drifting: bool = is_drifting
	is_handbrake_active = handbrake_pressed

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -1.2

	if drift_boost_timer > 0.0:
		drift_boost_timer = maxf(0.0, drift_boost_timer - delta)

	# Determine whether Handbrake + Steer at speed engages Arcade Drift vs Straight Emergency Brake
	var wants_drift: bool = (
		handbrake_pressed
		and forward_speed >= min_drift_speed
		and (absf(steer_input) > 0.15 or absf(drift_slip_angle_rad) > 0.08)
	)

	if wants_drift:
		is_drifting = true
		# Holding W throttle during a drift keeps rear wheels spinning to sustain the power-slide
		var drag: float = drift_drag_deceleration * (0.35 if throttle_input > 0.1 else 1.0)
		forward_speed = move_toward(forward_speed, min_drift_speed * 0.85, drag * delta)
		drift_charge_ratio = clampf(
			drift_charge_ratio + delta / maxf(drift_charge_time_seconds, 0.15),
			0.0,
			1.0
		)
	else:
		is_drifting = false
		# Trigger Mini-Turbo Drift Boost if releasing handbrake after charging a drift!
		if was_drifting and not handbrake_pressed and drift_charge_ratio >= 0.85 and forward_speed >= min_drift_speed * 0.7:
			drift_boost_timer = drift_boost_duration
			drift_boost_count += 1
			forward_speed = minf(forward_speed + 3.2, max_forward_speed * drift_boost_speed_multiplier)
			drift_boost_triggered.emit(drift_boost_count)
			truck_feedback.emit("DRIFT BOOST! (+Speed Surge #%d)" % drift_boost_count, false)
		if not handbrake_pressed:
			drift_charge_ratio = move_toward(drift_charge_ratio, 0.0, delta * 2.5)

		var effective_max_fwd: float = max_forward_speed * (drift_boost_speed_multiplier if drift_boost_timer > 0.0 else 1.0)
		var effective_accel: float = acceleration * (1.45 if drift_boost_timer > 0.0 else 1.0)

		if handbrake_pressed:
			forward_speed = move_toward(forward_speed, 0.0, handbrake_deceleration * delta)
		elif absf(throttle_input) > 0.01:
			if throttle_input > 0.0:
				if forward_speed < -0.1:
					forward_speed = move_toward(forward_speed, 0.0, braking_deceleration * 1.25 * delta)
				else:
					forward_speed = move_toward(forward_speed, effective_max_fwd * throttle_input, effective_accel * delta)
			else:
				if forward_speed > 0.1:
					forward_speed = move_toward(forward_speed, 0.0, braking_deceleration * 1.25 * delta)
				else:
					forward_speed = move_toward(forward_speed, -max_reverse_speed * absf(throttle_input), acceleration * 0.9 * delta)
		else:
			forward_speed = move_toward(forward_speed, 0.0, coasting_deceleration * delta)

	longitudinal_acceleration = (forward_speed - prev_forward_speed) / maxf(delta, 0.0001)

	# Arcade steering + Drift slip angle & yaw amplification
	var max_steer_rad: float = deg_to_rad(max_steering_angle_degrees)
	var target_steer: float = steer_input * max_steer_rad
	current_steer_angle_rad = move_toward(current_steer_angle_rad, target_steer, deg_to_rad(220.0) * delta)

	var target_slip_rad: float = 0.0
	if is_drifting:
		target_slip_rad = signf(steer_input if absf(steer_input) > 0.05 else drift_slip_angle_rad) * deg_to_rad(max_drift_slip_degrees)
	drift_slip_angle_rad = move_toward(drift_slip_angle_rad, target_slip_rad, deg_to_rad(95.0) * delta)

	if absf(forward_speed) > 0.08 and (absf(current_steer_angle_rad) > 0.005 or absf(drift_slip_angle_rad) > 0.01):
		var effective_wb: float = maxf(wheelbase, 1.2)
		var turn_mult: float = 1.35 * (drift_yaw_multiplier if is_drifting else 1.0)
		yaw_rate = (forward_speed / effective_wb) * tan(current_steer_angle_rad) * turn_mult
		yaw_rate = clampf(yaw_rate, -deg_to_rad(135.0), deg_to_rad(135.0))
		rotation.y = wrapf(rotation.y + yaw_rate * delta, -PI, PI)
	else:
		yaw_rate = 0.0

	# Lateral acceleration formula from AGENTS.md §6 (amplified during aggressive drifts):
	# lateral_acceleration ≈ forward_speed * yaw_rate
	lateral_acceleration = forward_speed * yaw_rate * (1.25 if is_drifting else 1.0)

	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	var desired_horiz_vel: Vector3 = forward_dir * forward_speed

	var grip_rate: float = 14.0
	if is_drifting:
		grip_rate = lerpf(11.0, 2.6, handbrake_lateral_slip)
	elif handbrake_pressed and absf(forward_speed) > 1.5:
		grip_rate = lerpf(12.0, 4.0, handbrake_lateral_slip)

	_horiz_velocity = _horiz_velocity.lerp(desired_horiz_vel, clampf(grip_rate * delta, 0.04, 1.0))
	velocity.x = _horiz_velocity.x
	velocity.z = _horiz_velocity.z


func is_stationary_for_cargo() -> bool:
	return absf(forward_speed) <= 0.6


func has_any_occupant() -> bool:
	return driver_actor != null or passenger_actor != null


func is_actor_seated(actor: Node3D) -> bool:
	return actor != null and (actor == driver_actor or actor == passenger_actor)


func get_actor_seat_role(actor: Node3D) -> String:
	if actor == driver_actor:
		return "Driver"
	if actor == passenger_actor:
		return "Passenger"
	return ""


func get_interaction_prompt_for_role(role: String) -> Dictionary:
	match role:
		"DriverSeat":
			if driver_actor != null:
				return {
					"key": "E",
					"description": "Driver Seat (Occupied)",
					"enabled": false,
					"reason": "Driver seat occupied",
				}
			return {
				"key": "E",
				"description": "Enter Driver Seat",
				"enabled": true,
				"reason": "",
			}
		"PassengerSeat":
			if passenger_actor != null:
				return {
					"key": "E",
					"description": "Passenger Seat (Occupied)",
					"enabled": false,
					"reason": "Passenger seat occupied",
				}
			return {
				"key": "E",
				"description": "Enter Passenger Seat",
				"enabled": true,
				"reason": "",
			}
		"CargoAnchor":
			if cargo_bay == null:
				return {
					"key": "F",
					"description": "Cargo Straps",
					"enabled": false,
					"reason": "Unavailable",
				}
			var check: Dictionary = cargo_bay.evaluate_secure_action()
			var allowed: bool = bool(check.get("allowed", false))
			var desc: String = "Unsecure Cargo Straps" if cargo_bay.are_all_cargos_secured() else "Secure Cargo Straps"
			return {
				"key": "F / E",
				"description": desc,
				"enabled": allowed,
				"reason": String(check.get("reason", "")),
			}
	return {"key": "E", "description": "Interact", "enabled": true, "reason": ""}


func can_interact_with_role(role: String, _origin: Vector3) -> Dictionary:
	var info: Dictionary = get_interaction_prompt_for_role(role)
	return {
		"allowed": bool(info.get("enabled", false)),
		"reason": String(info.get("reason", ""))
	}


func interact_with_role(role: String, actor: Node3D) -> String:
	if actor == null:
		return "Invalid actor"

	match role:
		"DriverSeat":
			return try_enter_seat(actor, 0)
		"PassengerSeat":
			return try_enter_seat(actor, 1)
		"CargoAnchor":
			if cargo_bay != null:
				var res: Dictionary = cargo_bay.toggle_secure_loaded_cargo(actor)
				var msg: String = String(res.get("message", ""))
				truck_feedback.emit(msg, not bool(res.get("success", false)))
				return msg
	return "Unhandled truck interaction"


func try_enter_seat(actor: Node3D, seat_index: int) -> String:
	if actor.has_method("is_holding_any_cargo") and bool(actor.call("is_holding_any_cargo")):
		return "Release held cargo before entering truck"
	if is_actor_seated(actor):
		return "Already seated in truck"

	if seat_index == 0:
		if driver_actor != null:
			return "Driver seat is already occupied"
		driver_actor = actor
		if actor.has_method("on_entered_vehicle"):
			actor.call("on_entered_vehicle", self, "Driver")
		_sync_seated_occupants()
		occupant_changed.emit(driver_actor, passenger_actor)
		return "Driving Truck (WASD: Drive | Space: Handbrake | E: Exit)"
	else:
		if passenger_actor != null:
			return "Passenger seat is already occupied"
		passenger_actor = actor
		if actor.has_method("on_entered_vehicle"):
			actor.call("on_entered_vehicle", self, "Passenger")
		_sync_seated_occupants()
		occupant_changed.emit(driver_actor, passenger_actor)
		return "Seated in Passenger Seat (Monitoring Cargo HUD | E: Exit)"


func try_exit_vehicle(actor: Node3D) -> Dictionary:
	if not is_actor_seated(actor):
		return {"success": false, "message": "Not seated in truck"}
	if absf(forward_speed) > max_safe_exit_speed:
		return {
			"success": false,
			"message": "Truck moving too fast (%.1f m/s) — slow down to exit!" % absf(forward_speed)
		}

	var exit_pos: Vector3 = global_position + global_transform.basis.x * (-2.15 if actor == driver_actor else 2.15)
	if actor == driver_actor and driver_exit_marker != null:
		exit_pos = driver_exit_marker.global_position
	elif actor == passenger_actor and passenger_exit_marker != null:
		exit_pos = passenger_exit_marker.global_position
	exit_pos.y = maxf(0.1, global_position.y + 0.1)

	if actor == driver_actor:
		driver_actor = null
	elif actor == passenger_actor:
		passenger_actor = null

	if actor.has_method("on_exited_vehicle"):
		actor.call("on_exited_vehicle", self, exit_pos)

	occupant_changed.emit(driver_actor, passenger_actor)
	return {"success": true, "message": "Exited delivery truck"}


func force_remove_occupant(actor: Node3D) -> void:
	if actor == null:
		return
	if actor == driver_actor:
		driver_actor = null
		_net_driver_throttle = 0.0
		_net_driver_steer = 0.0
		_net_driver_handbrake = true
	if actor == passenger_actor:
		passenger_actor = null
	occupant_changed.emit(driver_actor, passenger_actor)


func apply_remote_driver_input(throttle: float, steer: float, handbrake: bool) -> void:
	_net_driver_throttle = clampf(throttle, -1.0, 1.0)
	_net_driver_steer = clampf(steer, -1.0, 1.0)
	_net_driver_handbrake = handbrake


func apply_authoritative_snapshot(
	auth_pos: Vector3,
	auth_yaw: float,
	auth_fwd_speed: float,
	auth_steer_rad: float,
	auth_lat_accel: float,
	auth_handbrake: bool,
	bay_stability: float,
	bay_warning: String,
	bay_secured: bool
) -> void:
	_interp_target_pos = auth_pos
	_interp_target_yaw = auth_yaw
	forward_speed = auth_fwd_speed
	current_steer_angle_rad = auth_steer_rad
	lateral_acceleration = auth_lat_accel
	is_handbrake_active = auth_handbrake
	if cargo_bay != null:
		cargo_bay.current_stability_ratio = bay_stability
		cargo_bay.current_warning_text = bay_warning
		if cargo_bay.strap_visuals != null:
			cargo_bay.strap_visuals.visible = bay_secured

	if not _has_net_snapshot:
		_has_net_snapshot = true
		global_position = auth_pos
		rotation.y = auth_yaw


func _interpolate_client_state(delta: float) -> void:
	if not _has_net_snapshot:
		return
	if global_position.distance_to(_interp_target_pos) > 5.0:
		global_position = _interp_target_pos
	else:
		global_position = global_position.lerp(_interp_target_pos, clampf(16.0 * delta, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _interp_target_yaw, clampf(16.0 * delta, 0.0, 1.0))


func reset_to_spawn() -> void:
	if driver_actor != null:
		var d: Node3D = driver_actor
		forward_speed = 0.0
		try_exit_vehicle(d)
	if passenger_actor != null:
		var p: Node3D = passenger_actor
		forward_speed = 0.0
		try_exit_vehicle(p)

	forward_speed = 0.0
	current_steer_angle_rad = 0.0
	yaw_rate = 0.0
	longitudinal_acceleration = 0.0
	lateral_acceleration = 0.0
	is_drifting = false
	drift_slip_angle_rad = 0.0
	drift_charge_ratio = 0.0
	drift_boost_timer = 0.0
	velocity = Vector3.ZERO
	_horiz_velocity = Vector3.ZERO
	_suspension_offset_y = 0.0
	_suspension_vel_y = 0.0
	global_transform = _spawn_transform
	_prev_world_y = global_position.y


func _sync_seated_occupants() -> void:
	# Only sync global_position so the Player's root basis is NEVER rotated by the truck!
	if driver_actor != null and is_instance_valid(driver_actor) and driver_seat_marker != null:
		driver_actor.global_position = driver_seat_marker.global_position
	if passenger_actor != null and is_instance_valid(passenger_actor) and passenger_seat_marker != null:
		passenger_actor.global_position = passenger_seat_marker.global_position


func _update_visual_feedback(delta: float) -> void:
	# Spring-damper suspension bounce
	var spring_accel: float = -_suspension_offset_y * 65.0 - _suspension_vel_y * 10.0
	_suspension_vel_y += spring_accel * delta
	_suspension_offset_y = clampf(_suspension_offset_y + _suspension_vel_y * delta, -0.18, 0.18)

	if visual_root != null:
		var target_roll: float = clampf(deg_to_rad(-lateral_acceleration * 0.55), deg_to_rad(-9.0), deg_to_rad(9.0))
		var target_pitch: float = clampf(deg_to_rad(longitudinal_acceleration * 0.32), deg_to_rad(-5.0), deg_to_rad(5.0))
		var target_slip_yaw: float = drift_slip_angle_rad * 0.45
		visual_root.rotation.z = lerpf(visual_root.rotation.z, target_roll, clampf(delta * 10.0, 0.0, 1.0))
		visual_root.rotation.x = lerpf(visual_root.rotation.x, target_pitch, clampf(delta * 10.0, 0.0, 1.0))
		visual_root.rotation.y = lerpf(visual_root.rotation.y, target_slip_yaw, clampf(delta * 10.0, 0.0, 1.0))
		visual_root.position.y = _suspension_offset_y

	var spin_mult: float = 1.45 if (is_drifting or drift_boost_timer > 0.0) else 1.0
	_wheel_spin_angle = wrapf(_wheel_spin_angle - (forward_speed * spin_mult / 0.4) * delta, -TAU, TAU)
	var wheels_rear: Array[Node3D] = [wheel_rl, wheel_rr]
	for w: Node3D in wheels_rear:
		if w != null:
			w.rotation.x = _wheel_spin_angle

	var wheels_front: Array[Node3D] = [wheel_fl, wheel_fr]
	for wf: Node3D in wheels_front:
		if wf != null:
			# Counter-steer front wheels visually during a drift
			var visual_steer: float = current_steer_angle_rad - drift_slip_angle_rad * 0.35
			wf.rotation.y = visual_steer
			wf.rotation.x = _wheel_spin_angle

	# Emit tire smoke particles when drifting or boosting
	var emit_smoke: bool = (is_drifting or drift_boost_timer > 0.0) and absf(forward_speed) > 3.0
	if _drift_smoke_l != null:
		_drift_smoke_l.emitting = emit_smoke
	if _drift_smoke_r != null:
		_drift_smoke_r.emitting = emit_smoke

	# Dynamic brake / boost taillight glow
	if _taillight_mat != null:
		if drift_boost_timer > 0.0:
			_taillight_mat.albedo_color = Color(0.25, 0.95, 1.0)
			_taillight_mat.emission = Color(0.2, 0.85, 1.0) * 2.2
		elif is_handbrake_active or longitudinal_acceleration < -2.0:
			_taillight_mat.albedo_color = Color(1.0, 0.18, 0.15)
			_taillight_mat.emission = Color(1.0, 0.15, 0.1) * 1.8
		else:
			_taillight_mat.albedo_color = Color(0.65, 0.12, 0.12)
			_taillight_mat.emission = Color(0.35, 0.05, 0.05)

	# Spin roof beacons when driving
	if driver_actor != null:
		_beacon_rot_angle = wrapf(_beacon_rot_angle + delta * 10.0, 0.0, TAU)
		if _beacon_pivot_l != null:
			_beacon_pivot_l.rotation.y = _beacon_rot_angle
		if _beacon_pivot_r != null:
			_beacon_pivot_r.rotation.y = -_beacon_rot_angle


func _setup_enhanced_truck_visuals() -> void:
	if visual_root == null or visual_root.get_node_or_null("TruckDetails") != null:
		return

	var details: Node3D = Node3D.new()
	details.name = "TruckDetails"
	visual_root.add_child(details)

	var chrome_mat: StandardMaterial3D = StandardMaterial3D.new()
	chrome_mat.albedo_color = Color(0.78, 0.81, 0.85)
	chrome_mat.metallic = 0.65
	chrome_mat.roughness = 0.3

	var dark_trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_trim_mat.albedo_color = Color(0.16, 0.18, 0.21)
	dark_trim_mat.roughness = 0.75

	var headlight_mat: StandardMaterial3D = StandardMaterial3D.new()
	headlight_mat.albedo_color = Color(1.0, 0.97, 0.84)
	headlight_mat.emission_enabled = true
	headlight_mat.emission = Color(1.0, 0.94, 0.72) * 1.4

	var amber_mat: StandardMaterial3D = StandardMaterial3D.new()
	amber_mat.albedo_color = Color(1.0, 0.68, 0.12)
	amber_mat.emission_enabled = true
	amber_mat.emission = Color(1.0, 0.58, 0.08) * 1.5

	_taillight_mat = StandardMaterial3D.new()
	_taillight_mat.albedo_color = Color(0.75, 0.14, 0.14)
	_taillight_mat.emission_enabled = true
	_taillight_mat.emission = Color(0.4, 0.06, 0.06)

	var stripe_mat: StandardMaterial3D = StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.92, 0.32, 0.14)
	stripe_mat.roughness = 0.5

	# Front Bumper, Grille & Glowing Headlights
	_add_detail_box(details, Vector3(0.0, 0.42, -2.8), Vector3(2.22, 0.24, 0.18), chrome_mat)
	_add_detail_box(details, Vector3(0.0, 0.76, -2.79), Vector3(1.22, 0.42, 0.06), dark_trim_mat)
	_add_detail_box(details, Vector3(0.0, 0.76, -2.81), Vector3(1.12, 0.07, 0.04), chrome_mat)
	_add_detail_box(details, Vector3(-0.82, 0.78, -2.79), Vector3(0.32, 0.24, 0.06), headlight_mat)
	_add_detail_box(details, Vector3(0.82, 0.78, -2.79), Vector3(0.32, 0.24, 0.06), headlight_mat)

	# Side Wing Mirrors
	_add_detail_box(details, Vector3(-1.22, 1.48, -1.85), Vector3(0.26, 0.06, 0.06), dark_trim_mat)
	_add_detail_box(details, Vector3(-1.32, 1.48, -1.82), Vector3(0.08, 0.32, 0.18), chrome_mat)
	_add_detail_box(details, Vector3(1.22, 1.48, -1.85), Vector3(0.26, 0.06, 0.06), dark_trim_mat)
	_add_detail_box(details, Vector3(1.32, 1.48, -1.82), Vector3(0.08, 0.32, 0.18), chrome_mat)

	# Roof Lightbar & Rotating Amber Beacons
	_add_detail_box(details, Vector3(0.0, 2.14, -1.25), Vector3(1.5, 0.08, 0.26), chrome_mat)
	_beacon_pivot_l = Node3D.new()
	_beacon_pivot_l.position = Vector3(-0.55, 2.24, -1.25)
	details.add_child(_beacon_pivot_l)
	_add_detail_box(_beacon_pivot_l, Vector3.ZERO, Vector3(0.22, 0.16, 0.14), amber_mat)

	_beacon_pivot_r = Node3D.new()
	_beacon_pivot_r.position = Vector3(0.55, 2.24, -1.25)
	details.add_child(_beacon_pivot_r)
	_add_detail_box(_beacon_pivot_r, Vector3.ZERO, Vector3(0.22, 0.16, 0.14), amber_mat)

	# Delivery Company Racing Stripes along Cargo Bed Walls
	_add_detail_box(details, Vector3(-1.28, 1.18, 1.4), Vector3(0.03, 0.26, 3.22), stripe_mat)
	_add_detail_box(details, Vector3(1.28, 1.18, 1.4), Vector3(0.03, 0.26, 3.22), stripe_mat)

	# Rear Brake / Tail Lights
	_add_detail_box(details, Vector3(-1.12, 0.56, 3.06), Vector3(0.28, 0.18, 0.06), _taillight_mat)
	_add_detail_box(details, Vector3(1.12, 0.56, 3.06), Vector3(0.28, 0.18, 0.06), _taillight_mat)

	# Wheel Hubcaps
	for w_node: Node3D in [wheel_fl, wheel_fr, wheel_rl, wheel_rr]:
		if w_node != null:
			var side_sign: float = -1.0 if w_node.position.x < 0.0 else 1.0
			_add_detail_box(w_node, Vector3(side_sign * 0.15, 0.0, 0.0), Vector3(0.04, 0.36, 0.36), chrome_mat)

	# Rear Tire Drift Smoke Particle Emitters
	_drift_smoke_l = _create_tire_smoke_emitter(Vector3(-1.08, 0.18, 1.85))
	details.add_child(_drift_smoke_l)
	_drift_smoke_r = _create_tire_smoke_emitter(Vector3(1.08, 0.18, 1.85))
	details.add_child(_drift_smoke_r)


func _add_detail_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.position = pos
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	parent.add_child(mi)
	return mi


func _create_tire_smoke_emitter(pos: Vector3) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.position = pos
	p.emitting = false
	p.amount = 22
	p.lifetime = 0.65
	p.direction = Vector3(0.0, 0.45, 1.0)
	p.spread = 38.0
	p.initial_velocity_min = 1.4
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0.0, 1.2, 0.0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 8
	sm.rings = 4
	var smoke_mat: StandardMaterial3D = StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.92, 0.92, 0.95, 0.65)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.roughness = 1.0
	sm.material = smoke_mat
	p.mesh = sm
	return p
