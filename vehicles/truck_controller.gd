class_name TruckController
extends CharacterBody3D

signal occupant_changed(driver: Node3D, passenger: Node3D)
signal truck_feedback(message: String, is_error: bool)

@export_group("Arcade Driving Tuning")
@export_range(4.0, 30.0, 0.5) var max_forward_speed: float = 14.0
@export_range(2.0, 15.0, 0.5) var max_reverse_speed: float = 5.0
@export_range(2.0, 25.0, 0.5) var acceleration: float = 8.0
@export_range(4.0, 35.0, 0.5) var braking_deceleration: float = 14.0
@export_range(10.0, 50.0, 1.0) var max_steering_angle_degrees: float = 30.0
@export_range(8.0, 40.0, 1.0) var handbrake_deceleration: float = 22.0
@export_range(0.0, 0.9, 0.05) var handbrake_lateral_slip: float = 0.45
@export_range(1.0, 12.0, 0.5) var coasting_deceleration: float = 3.5
@export_range(1.5, 6.0, 0.1) var wheelbase: float = 2.6
@export_range(0.5, 5.0, 0.1) var max_safe_exit_speed: float = 2.0

var forward_speed: float = 0.0
var current_steer_angle_rad: float = 0.0
var yaw_rate: float = 0.0
var longitudinal_acceleration: float = 0.0
var lateral_acceleration: float = 0.0
var is_handbrake_active: bool = false

var driver_actor: Node3D = null
var passenger_actor: Node3D = null

var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _horiz_velocity: Vector3 = Vector3.ZERO
var _wheel_spin_angle: float = 0.0
var _suspension_offset_y: float = 0.0
var _suspension_vel_y: float = 0.0
var _prev_world_y: float = 0.0

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


func _physics_process(delta: float) -> void:
	var throttle_input: float = 0.0
	var steer_input: float = 0.0
	var handbrake_input: bool = false

	if driver_actor != null and is_instance_valid(driver_actor):
		throttle_input = Input.get_axis("move_back", "move_forward")
		steer_input = Input.get_axis("move_right", "move_left")
		handbrake_input = Input.is_action_pressed("handbrake")
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
	if get_slide_collision_count() > 0 and pre_slide_speed > 1.0:
		for i in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			if col == null:
				continue
			var contact_local_y: float = col.get_position().y - global_position.y
			var normal: Vector3 = col.get_normal()
			if normal.y < 0.25 and contact_local_y > 0.55:
				var forward_dir: Vector3 = -global_transform.basis.z.normalized()
				var head_on_factor: float = absf(forward_dir.dot(normal))
				if head_on_factor > 0.4:
					var crash_severity: float = pre_slide_speed * head_on_factor
					forward_speed *= (1.0 - clampf(head_on_factor * 0.85, 0.3, 0.92))
					_horiz_velocity = _horiz_velocity.slide(normal)
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
	is_handbrake_active = handbrake_pressed

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -1.2

	# Longitudinal speed update (responsive arcade throttle & braking)
	if handbrake_pressed:
		forward_speed = move_toward(forward_speed, 0.0, handbrake_deceleration * delta)
	elif absf(throttle_input) > 0.01:
		if throttle_input > 0.0:
			if forward_speed < -0.1:
				forward_speed = move_toward(forward_speed, 0.0, braking_deceleration * 1.25 * delta)
			else:
				forward_speed = move_toward(forward_speed, max_forward_speed * throttle_input, acceleration * delta)
		else:
			if forward_speed > 0.1:
				forward_speed = move_toward(forward_speed, 0.0, braking_deceleration * 1.25 * delta)
			else:
				forward_speed = move_toward(forward_speed, -max_reverse_speed * absf(throttle_input), acceleration * 0.9 * delta)
	else:
		forward_speed = move_toward(forward_speed, 0.0, coasting_deceleration * delta)

	longitudinal_acceleration = (forward_speed - prev_forward_speed) / maxf(delta, 0.0001)

	# Arcade steering: smooth wheel angle + speed-scaled turning rate
	var max_steer_rad: float = deg_to_rad(max_steering_angle_degrees)
	var target_steer: float = steer_input * max_steer_rad
	current_steer_angle_rad = move_toward(current_steer_angle_rad, target_steer, deg_to_rad(220.0) * delta)

	if absf(forward_speed) > 0.08 and absf(current_steer_angle_rad) > 0.005:
		var effective_wb: float = maxf(wheelbase, 1.2)
		yaw_rate = (forward_speed / effective_wb) * tan(current_steer_angle_rad) * 1.35
		yaw_rate = clampf(yaw_rate, -deg_to_rad(105.0), deg_to_rad(105.0))
		rotation.y = wrapf(rotation.y + yaw_rate * delta, -PI, PI)
	else:
		yaw_rate = 0.0

	# Lateral acceleration formula from AGENTS.md §6:
	# lateral_acceleration ≈ forward_speed * yaw_rate
	lateral_acceleration = forward_speed * yaw_rate

	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	var desired_horiz_vel: Vector3 = forward_dir * forward_speed

	var grip_rate: float = 14.0
	if handbrake_pressed and absf(forward_speed) > 1.5:
		grip_rate = lerpf(12.0, 2.5, handbrake_lateral_slip)

	_horiz_velocity = _horiz_velocity.lerp(desired_horiz_vel, clampf(grip_rate * delta, 0.05, 1.0))
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
		var target_roll: float = clampf(deg_to_rad(-lateral_acceleration * 0.45), deg_to_rad(-6.0), deg_to_rad(6.0))
		var target_pitch: float = clampf(deg_to_rad(longitudinal_acceleration * 0.28), deg_to_rad(-4.0), deg_to_rad(4.0))
		visual_root.rotation.z = lerpf(visual_root.rotation.z, target_roll, clampf(delta * 10.0, 0.0, 1.0))
		visual_root.rotation.x = lerpf(visual_root.rotation.x, target_pitch, clampf(delta * 10.0, 0.0, 1.0))
		visual_root.position.y = _suspension_offset_y

	_wheel_spin_angle = wrapf(_wheel_spin_angle - (forward_speed / 0.4) * delta, -TAU, TAU)
	var wheels_rear: Array[Node3D] = [wheel_rl, wheel_rr]
	for w: Node3D in wheels_rear:
		if w != null:
			w.rotation.x = _wheel_spin_angle

	var wheels_front: Array[Node3D] = [wheel_fl, wheel_fr]
	for wf: Node3D in wheels_front:
		if wf != null:
			wf.rotation.y = current_steer_angle_rad
			wf.rotation.x = _wheel_spin_angle
