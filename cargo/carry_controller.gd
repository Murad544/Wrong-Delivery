class_name CarryController
extends Node

signal carrier_attached(handle_id: int, actor: Node3D)
signal carrier_detached(handle_id: int, actor: Node3D, reason: String)

@export_group("Spring & Damping")
@export_range(20.0, 600.0, 5.0) var linear_spring_stiffness: float = 220.0
@export_range(5.0, 120.0, 1.0) var linear_damping: float = 36.0
@export_range(50.0, 2000.0, 10.0) var max_carry_force: float = 680.0
@export_range(5.0, 150.0, 1.0) var angular_spring_stiffness: float = 38.0
@export_range(1.0, 50.0, 0.5) var angular_damping: float = 11.0
@export_range(5.0, 200.0, 1.0) var max_carry_torque: float = 72.0
@export_range(1.0, 15.0, 0.5) var max_angular_speed: float = 4.2

@export_group("Rotation & Co-op Tuning")
@export_range(30.0, 240.0, 5.0) var manual_rotate_deg_per_sec: float = 95.0
@export_range(0.4, 2.5, 0.05) var default_hold_distance: float = 1.25
@export_range(0.4, 2.0, 0.05) var default_hold_height: float = 0.88
@export_range(1.5, 6.0, 0.1) var max_detach_distance: float = 3.5
@export_range(2.5, 8.0, 0.1) var max_carrier_separation: float = 4.9
@export_range(0.1, 2.0, 0.05) var single_release_grace_sec: float = 0.65

var cargo_body: RigidBody3D = null
var required_carriers: int = 1
var target_yaw_offset: float = 0.0
var last_applied_force: Vector3 = Vector3.ZERO
var last_applied_torque: Vector3 = Vector3.ZERO

# Co-op coordination & strain telemetry (replicated to client HUD)
var current_strain_ratio: float = 0.0
var coop_speed_multiplier: float = 1.0
var coordination_state_text: String = "IDLE"

var _single_release_grace_timer: float = 0.0
var _target_roll_tilt_rad: float = 0.0
var _target_pitch_tilt_rad: float = 0.0

# Maps handle_id (int) -> carrier Node3D
var _carriers_by_handle: Dictionary = {}
# Maps handle_id (int) -> CargoHandle
var _handles_by_id: Dictionary = {}


func setup(body: RigidBody3D, handles: Array[CargoHandle], data: CargoData) -> void:
	cargo_body = body
	_handles_by_id.clear()
	for handle: CargoHandle in handles:
		if handle != null:
			_handles_by_id[handle.handle_id] = handle

	if data != null:
		required_carriers = data.required_carriers
		default_hold_distance = data.hold_distance
		default_hold_height = data.hold_height_offset
		max_detach_distance = data.max_detach_distance


func get_carrier_count() -> int:
	return _carriers_by_handle.size()


func is_fully_staffed() -> bool:
	return get_carrier_count() >= required_carriers


func has_any_carrier() -> bool:
	return not _carriers_by_handle.is_empty()


func is_actor_carrying(actor: Node3D) -> bool:
	for handle_id: int in _carriers_by_handle.keys():
		if _carriers_by_handle[handle_id] == actor:
			return true
	return false


func get_actor_handle_id(actor: Node3D) -> int:
	for handle_id: int in _carriers_by_handle.keys():
		if _carriers_by_handle[handle_id] == actor:
			return handle_id
	return -1


func attach_carrier(handle_id: int, actor: Node3D) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if _carriers_by_handle.has(handle_id):
		return false
	if is_actor_carrying(actor):
		return false

	_carriers_by_handle[handle_id] = actor
	if _handles_by_id.has(handle_id):
		var handle: CargoHandle = _handles_by_id[handle_id]
		handle.set_occupying_actor(actor)

	if cargo_body != null:
		if _carriers_by_handle.size() == 1:
			var carrier_yaw: float = _get_actor_forward_yaw(actor)
			target_yaw_offset = wrapf(cargo_body.global_rotation.y - carrier_yaw, -PI, PI)
		elif _carriers_by_handle.size() >= 2:
			_single_release_grace_timer = 0.0
			var axis_yaw: float = _compute_dual_carrier_axis_yaw()
			target_yaw_offset = wrapf(cargo_body.global_rotation.y - axis_yaw, -PI, PI)

	_evaluate_coop_coordination(0.016)
	carrier_attached.emit(handle_id, actor)
	return true


func detach_carrier_by_handle(handle_id: int, reason: String = "Released") -> Node3D:
	if not _carriers_by_handle.has(handle_id):
		return null
	var was_fully_staffed: bool = is_fully_staffed()
	var actor: Node3D = _carriers_by_handle[handle_id]
	_carriers_by_handle.erase(handle_id)

	if _handles_by_id.has(handle_id):
		var handle: CargoHandle = _handles_by_id[handle_id]
		handle.set_occupying_actor(null)

	if was_fully_staffed and required_carriers > 1 and not _carriers_by_handle.is_empty():
		# Start short grace period when one carrier releases a heavy multi-person object
		_single_release_grace_timer = single_release_grace_sec

	if _carriers_by_handle.is_empty():
		last_applied_force = Vector3.ZERO
		last_applied_torque = Vector3.ZERO
		current_strain_ratio = 0.0
		coop_speed_multiplier = 1.0
		coordination_state_text = "IDLE"
		_single_release_grace_timer = 0.0

	carrier_detached.emit(handle_id, actor, reason)
	return actor


func detach_actor(actor: Node3D, reason: String = "Released") -> bool:
	var handle_id: int = get_actor_handle_id(actor)
	if handle_id == -1:
		return false
	detach_carrier_by_handle(handle_id, reason)
	return true


func detach_all(reason: String = "Reset") -> void:
	var ids: Array = _carriers_by_handle.keys()
	for id_val: Variant in ids:
		detach_carrier_by_handle(int(id_val), reason)


func apply_rotation_input(direction_sign: float, delta: float) -> void:
	if not has_any_carrier():
		return
	target_yaw_offset = wrapf(
		target_yaw_offset + deg_to_rad(manual_rotate_deg_per_sec) * direction_sign * delta,
		-PI,
		PI
	)


func compute_carrier_leash_pullback(actor: Node3D) -> Vector3:
	if cargo_body == null or actor == null or not _carriers_by_handle.values().has(actor):
		return Vector3.ZERO

	var handle_id: int = get_actor_handle_id(actor)
	var handle_world_pos: Vector3 = cargo_body.global_position
	if _handles_by_id.has(handle_id):
		handle_world_pos = _handles_by_id[handle_id].global_position

	var desired_hold: Vector3 = _get_actor_hold_point(actor, _carriers_by_handle.size() > 1)
	var stretch_vec: Vector3 = handle_world_pos - desired_hold
	stretch_vec.y = 0.0
	var stretch_dist: float = stretch_vec.length()
	if stretch_dist <= 0.45:
		return Vector3.ZERO

	var pullback_speed: float = clampf((stretch_dist - 0.45) * 3.2, 0.0, 3.0)
	return stretch_vec.normalized() * pullback_speed


func process_carry_physics(delta: float) -> void:
	if cargo_body == null or not has_any_carrier():
		last_applied_force = Vector3.ZERO
		last_applied_torque = Vector3.ZERO
		current_strain_ratio = 0.0
		coop_speed_multiplier = 1.0
		coordination_state_text = "IDLE"
		return

	if _single_release_grace_timer > 0.0:
		_single_release_grace_timer = maxf(0.0, _single_release_grace_timer - delta)

	_validate_carrier_distances()
	if not has_any_carrier():
		return

	# Check rotation inputs (Q / R) from all attached carriers (local or remote)
	var rot_dir: float = 0.0
	for handle_id: int in _carriers_by_handle.keys():
		var actor: Node3D = _carriers_by_handle[handle_id]
		if actor == null or not is_instance_valid(actor):
			continue
		if bool(actor.get("is_local_player")):
			if Input.is_action_pressed("rotate_left"):
				rot_dir += 1.0
			if Input.is_action_pressed("rotate_right"):
				rot_dir -= 1.0
		else:
			rot_dir += float(actor.get("net_rotate_dir"))
	if absf(rot_dir) > 0.01:
		apply_rotation_input(clampf(rot_dir, -1.0, 1.0), delta)

	_evaluate_coop_coordination(delta)

	var target_pos: Vector3 = compute_target_world_position()
	var pos_error: Vector3 = target_pos - cargo_body.global_position
	var vel: Vector3 = cargo_body.linear_velocity

	var gravity_val: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_comp: Vector3 = Vector3.UP * cargo_body.mass * gravity_val

	var staff_factor: float = 1.0
	if not is_fully_staffed():
		var grace_ratio: float = clampf(_single_release_grace_timer / maxf(single_release_grace_sec, 0.01), 0.0, 1.0)
		staff_factor = lerpf(0.24, 0.75, grace_ratio)
		gravity_comp = Vector3.UP * cargo_body.mass * gravity_val * lerpf(0.28, 0.85, grace_ratio)
		if grace_ratio <= 0.05:
			pos_error.y = minf(0.0, pos_error.y)

	var effective_stiffness: float = linear_spring_stiffness * (1.25 if required_carriers > 1 and is_fully_staffed() else 1.0)
	var spring_force: Vector3 = (pos_error * effective_stiffness - vel * linear_damping) * staff_factor + gravity_comp
	if spring_force.length() > max_carry_force:
		spring_force = spring_force.normalized() * max_carry_force

	cargo_body.apply_central_force(spring_force)
	last_applied_force = spring_force

	# Upright + yaw + disagreement tilt torque
	var desired_yaw: float = _compute_target_world_yaw()
	var current_euler: Vector3 = cargo_body.global_rotation
	var yaw_error: float = wrapf(desired_yaw - current_euler.y, -PI, PI)
	var pitch_error: float = wrapf(_target_pitch_tilt_rad - current_euler.x, -PI, PI)
	var roll_error: float = wrapf(_target_roll_tilt_rad - current_euler.z, -PI, PI)

	var angular_error: Vector3 = Vector3(pitch_error, yaw_error * staff_factor, roll_error)
	var torque: Vector3 = angular_error * angular_spring_stiffness - cargo_body.angular_velocity * angular_damping
	if torque.length() > max_carry_torque:
		torque = torque.normalized() * max_carry_torque

	cargo_body.apply_torque(torque)
	last_applied_torque = torque

	if cargo_body.angular_velocity.length() > max_angular_speed:
		cargo_body.angular_velocity = cargo_body.angular_velocity.normalized() * max_angular_speed


func compute_target_world_position() -> Vector3:
	if _carriers_by_handle.is_empty() or cargo_body == null:
		return Vector3.ZERO

	var is_multi: bool = (_carriers_by_handle.size() > 1)
	var accum: Vector3 = Vector3.ZERO
	var count: int = 0
	for handle_id: int in _carriers_by_handle.keys():
		var actor: Node3D = _carriers_by_handle[handle_id]
		if actor == null or not is_instance_valid(actor):
			continue
		var hold_point: Vector3 = _get_actor_hold_point(actor, is_multi)
		accum += hold_point
		count += 1

	if count == 0:
		return cargo_body.global_position
	return accum / float(count)


func _evaluate_coop_coordination(_delta: float) -> void:
	_target_roll_tilt_rad = 0.0
	_target_pitch_tilt_rad = 0.0

	if not has_any_carrier():
		current_strain_ratio = 0.0
		coop_speed_multiplier = 1.0
		coordination_state_text = "IDLE"
		return

	if not is_fully_staffed():
		current_strain_ratio = 0.65
		coop_speed_multiplier = 0.35
		if _single_release_grace_timer > 0.0:
			coordination_state_text = "PARTNER RELEASED (SETTLING...)"
		else:
			coordination_state_text = "1/%d CARRIERS (NEED PARTNER TO LIFT)" % required_carriers
		_target_roll_tilt_rad = deg_to_rad(5.5)
		return

	if _carriers_by_handle.size() == 1:
		coop_speed_multiplier = 1.0
		current_strain_ratio = _compute_max_handle_stretch_ratio()
		coordination_state_text = "SOLO CARRY" if current_strain_ratio < 0.5 else "BLOCKED BY OBSTACLE"
		return

	# True 2-player cooperative carry evaluation (AGENTS.md §5)
	var actors: Array[Node3D] = []
	for hid: int in _carriers_by_handle.keys():
		var a: Node3D = _carriers_by_handle[hid]
		if a != null and is_instance_valid(a):
			actors.append(a)

	if actors.size() < 2:
		return

	var intent_a: Vector3 = _get_actor_move_intent(actors[0])
	var intent_b: Vector3 = _get_actor_move_intent(actors[1])
	var moving_a: bool = intent_a.length_squared() > 0.02
	var moving_b: bool = intent_b.length_squared() > 0.02

	var disagreement_strain: float = 0.0
	if not moving_a and not moving_b:
		coop_speed_multiplier = 1.0
		disagreement_strain = 0.05
		coordination_state_text = "CO-OP STEADY"
	elif moving_a and moving_b:
		var dot: float = intent_a.normalized().dot(intent_b.normalized())
		if dot >= 0.35:
			# Both moving in the same general direction -> nearly full carry speed
			coop_speed_multiplier = lerpf(0.82, 1.0, clampf(dot, 0.0, 1.0))
			disagreement_strain = lerpf(0.22, 0.08, clampf(dot, 0.0, 1.0))
			coordination_state_text = "CO-OP SYNCHRONIZED"
		elif dot >= -0.2:
			# Angled / cornering movement -> moderate speed & slight tilt
			coop_speed_multiplier = 0.62
			disagreement_strain = 0.42
			coordination_state_text = "CO-OP CORNERING"
			_target_roll_tilt_rad = deg_to_rad(4.5)
		else:
			# Opposite directions -> little net progress, high strain, tug-of-war tilt
			coop_speed_multiplier = 0.18
			disagreement_strain = lerpf(0.75, 0.96, clampf(-dot, 0.0, 1.0))
			coordination_state_text = "DISAGREEMENT: PULLING OPPOSITE!"
			_target_roll_tilt_rad = deg_to_rad(8.5 * signf(intent_a.x - intent_b.x))
			_target_pitch_tilt_rad = deg_to_rad(5.5 * signf(intent_a.z - intent_b.z))
	else:
		# One moves, one stays -> slower progress and visible tilt/strain toward stationary carrier
		coop_speed_multiplier = 0.55
		disagreement_strain = 0.45
		coordination_state_text = "PIVOTING (1 MOVING, 1 STATIONARY)"
		var tilt_sign: float = 1.0 if moving_a else -1.0
		_target_roll_tilt_rad = deg_to_rad(6.5 * tilt_sign)

	var stretch_strain: float = _compute_max_handle_stretch_ratio()
	current_strain_ratio = clampf(maxf(disagreement_strain, stretch_strain), 0.0, 1.0)
	if stretch_strain > 0.68 and stretch_strain > disagreement_strain:
		coordination_state_text = "STRAIN: BLOCKED OR TOO FAR APART!"


func _compute_max_handle_stretch_ratio() -> float:
	if cargo_body == null:
		return 0.0
	var max_stretch: float = 0.0
	var is_multi: bool = (_carriers_by_handle.size() > 1)
	for handle_id: int in _carriers_by_handle.keys():
		var actor: Node3D = _carriers_by_handle[handle_id]
		if actor == null or not is_instance_valid(actor):
			continue
		var handle_pos: Vector3 = cargo_body.global_position
		if _handles_by_id.has(handle_id):
			handle_pos = _handles_by_id[handle_id].global_position
		var hold_pos: Vector3 = _get_actor_hold_point(actor, is_multi)
		var d: float = handle_pos.distance_to(hold_pos)
		max_stretch = maxf(max_stretch, d)
	return clampf(max_stretch / maxf(max_detach_distance * 0.75, 1.0), 0.0, 1.0)


func _compute_target_world_yaw() -> float:
	if _carriers_by_handle.size() >= 2:
		return wrapf(_compute_dual_carrier_axis_yaw() + target_yaw_offset, -PI, PI)

	for handle_id: int in _carriers_by_handle.keys():
		var actor: Node3D = _carriers_by_handle[handle_id]
		if actor != null and is_instance_valid(actor):
			return wrapf(_get_actor_forward_yaw(actor) + target_yaw_offset, -PI, PI)
	return cargo_body.global_rotation.y


func _compute_dual_carrier_axis_yaw() -> float:
	var left_actor: Node3D = _carriers_by_handle.get(0, null) as Node3D
	var right_actor: Node3D = _carriers_by_handle.get(1, null) as Node3D
	if left_actor != null and right_actor != null and is_instance_valid(left_actor) and is_instance_valid(right_actor):
		var p_left: Vector3 = _get_actor_hold_point(left_actor, true)
		var p_right: Vector3 = _get_actor_hold_point(right_actor, true)
		var axis_vec: Vector3 = p_right - p_left
		axis_vec.y = 0.0
		if axis_vec.length_squared() > 0.01:
			# Align sofa's +X axis (from LeftHandle to RightHandle) with (p_right - p_left)
			var dir: Vector3 = axis_vec.normalized()
			return atan2(-dir.z, dir.x)
	return cargo_body.global_rotation.y if cargo_body != null else 0.0


func _validate_carrier_distances() -> void:
	# Check pair separation limit for multi-carrier objects
	if _carriers_by_handle.size() >= 2:
		var actors: Array[Node3D] = []
		for hid: int in _carriers_by_handle.keys():
			var a: Node3D = _carriers_by_handle[hid]
			if a != null and is_instance_valid(a):
				actors.append(a)
		if actors.size() >= 2:
			var pair_dist: float = actors[0].global_position.distance_to(actors[1].global_position)
			if pair_dist > max_carrier_separation:
				detach_all("Carriers exceeded maximum separation distance")
				return

	var to_detach: Array[int] = []
	for handle_id: int in _carriers_by_handle.keys():
		var actor: Node3D = _carriers_by_handle[handle_id]
		if actor == null or not is_instance_valid(actor):
			to_detach.append(handle_id)
			continue

		var anchor_pos: Vector3 = cargo_body.global_position
		if _handles_by_id.has(handle_id):
			anchor_pos = _handles_by_id[handle_id].global_position

		var dist: float = actor.global_position.distance_to(anchor_pos)
		if dist > max_detach_distance:
			to_detach.append(handle_id)

	for handle_id: int in to_detach:
		detach_carrier_by_handle(handle_id, "Separated too far from cargo")


func _get_actor_hold_point(actor: Node3D, is_multi_carrier: bool) -> Vector3:
	var forward: Vector3 = _get_actor_forward_vector(actor)
	var dist: float = (default_hold_distance * 0.52) if is_multi_carrier else default_hold_distance
	return actor.global_position + Vector3.UP * default_hold_height + forward * dist


func _get_actor_move_intent(actor: Node3D) -> Vector3:
	if actor != null and actor.has_method("get_world_move_intent"):
		return actor.call("get_world_move_intent")
	return Vector3.ZERO


func _get_actor_forward_vector(actor: Node3D) -> Vector3:
	if actor.has_method("get_carry_forward_direction"):
		return actor.call("get_carry_forward_direction")
	var visual: Node3D = actor.get_node_or_null("VisualRoot") as Node3D
	if visual != null:
		return -visual.global_transform.basis.z.normalized()
	return -actor.global_transform.basis.z.normalized()


func _get_actor_forward_yaw(actor: Node3D) -> float:
	var fwd: Vector3 = _get_actor_forward_vector(actor)
	return atan2(-fwd.x, -fwd.z)
