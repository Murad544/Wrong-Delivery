class_name CarryController
extends Node

signal carrier_attached(handle_id: int, actor: Node3D)
signal carrier_detached(handle_id: int, actor: Node3D, reason: String)

@export_group("Spring & Damping")
@export_range(20.0, 600.0, 5.0) var linear_spring_stiffness: float = 210.0
@export_range(5.0, 120.0, 1.0) var linear_damping: float = 34.0
@export_range(50.0, 2000.0, 10.0) var max_carry_force: float = 520.0
@export_range(5.0, 120.0, 1.0) var angular_spring_stiffness: float = 28.0
@export_range(1.0, 40.0, 0.5) var angular_damping: float = 8.5
@export_range(5.0, 150.0, 1.0) var max_carry_torque: float = 48.0
@export_range(1.0, 15.0, 0.5) var max_angular_speed: float = 4.5

@export_group("Rotation & Placement")
@export_range(30.0, 240.0, 5.0) var manual_rotate_deg_per_sec: float = 95.0
@export_range(0.5, 2.5, 0.05) var default_hold_distance: float = 1.35
@export_range(0.4, 2.0, 0.05) var default_hold_height: float = 0.95
@export_range(1.5, 6.0, 0.1) var max_detach_distance: float = 3.2

var cargo_body: RigidBody3D = null
var required_carriers: int = 1
var target_yaw_offset: float = 0.0
var last_applied_force: Vector3 = Vector3.ZERO
var last_applied_torque: Vector3 = Vector3.ZERO

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

	if _carriers_by_handle.size() == 1 and cargo_body != null:
		var carrier_yaw: float = _get_actor_forward_yaw(actor)
		target_yaw_offset = wrapf(cargo_body.global_rotation.y - carrier_yaw, -PI, PI)

	carrier_attached.emit(handle_id, actor)
	return true


func detach_carrier_by_handle(handle_id: int, reason: String = "Released") -> Node3D:
	if not _carriers_by_handle.has(handle_id):
		return null
	var actor: Node3D = _carriers_by_handle[handle_id]
	_carriers_by_handle.erase(handle_id)

	if _handles_by_id.has(handle_id):
		var handle: CargoHandle = _handles_by_id[handle_id]
		handle.set_occupying_actor(null)

	if _carriers_by_handle.is_empty():
		last_applied_force = Vector3.ZERO
		last_applied_torque = Vector3.ZERO

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


func process_carry_physics(delta: float) -> void:
	if cargo_body == null or not has_any_carrier():
		last_applied_force = Vector3.ZERO
		last_applied_torque = Vector3.ZERO
		return

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

	var target_pos: Vector3 = compute_target_world_position()
	var pos_error: Vector3 = target_pos - cargo_body.global_position
	var vel: Vector3 = cargo_body.linear_velocity

	var gravity_val: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_comp: Vector3 = Vector3.UP * cargo_body.mass * gravity_val

	var staff_factor: float = 1.0
	if not is_fully_staffed():
		# Heavy cargo (e.g., 2-player sofa held by 1 player in Milestone 02):
		# Apply only partial horizontal tug and insufficient lift so it stays grounded.
		staff_factor = 0.22
		gravity_comp = Vector3.UP * cargo_body.mass * gravity_val * 0.25
		pos_error.y = minf(0.0, pos_error.y)

	var spring_force: Vector3 = (pos_error * linear_spring_stiffness - vel * linear_damping) * staff_factor + gravity_comp
	if spring_force.length() > max_carry_force:
		spring_force = spring_force.normalized() * max_carry_force

	cargo_body.apply_central_force(spring_force)
	last_applied_force = spring_force

	# Upright + yaw target torque
	var desired_yaw: float = _compute_target_world_yaw()
	var current_euler: Vector3 = cargo_body.global_rotation
	var yaw_error: float = wrapf(desired_yaw - current_euler.y, -PI, PI)
	var pitch_error: float = wrapf(0.0 - current_euler.x, -PI, PI)
	var roll_error: float = wrapf(0.0 - current_euler.z, -PI, PI)

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

	var accum: Vector3 = Vector3.ZERO
	var count: int = 0
	for handle_id: int in _carriers_by_handle.keys():
		var actor: Node3D = _carriers_by_handle[handle_id]
		if actor == null or not is_instance_valid(actor):
			continue
		var forward: Vector3 = _get_actor_forward_vector(actor)
		var hold_point: Vector3 = actor.global_position + Vector3.UP * default_hold_height + forward * default_hold_distance
		if _handles_by_id.has(handle_id) and _carriers_by_handle.size() > 1:
			var handle: CargoHandle = _handles_by_id[handle_id]
			var handle_world_offset: Vector3 = cargo_body.global_transform.basis * handle.position
			hold_point -= handle_world_offset
		accum += hold_point
		count += 1

	if count == 0:
		return cargo_body.global_position
	return accum / float(count)


func _compute_target_world_yaw() -> float:
	for handle_id: int in _carriers_by_handle.keys():
		var actor: Node3D = _carriers_by_handle[handle_id]
		if actor != null and is_instance_valid(actor):
			return wrapf(_get_actor_forward_yaw(actor) + target_yaw_offset, -PI, PI)
	return cargo_body.global_rotation.y


func _validate_carrier_distances() -> void:
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
