class_name PlayerController
extends CharacterBody3D

@export_group("Movement Speeds")
@export_range(1.0, 12.0, 0.1) var walk_speed: float = 5.0
@export_range(2.0, 16.0, 0.1) var sprint_speed: float = 7.0
@export_range(0.5, 8.0, 0.1) var carry_speed: float = 2.5
@export_range(1.0, 12.0, 0.1) var jump_velocity: float = 4.5

@export_group("Acceleration & Feel")
@export_range(5.0, 50.0, 0.5) var acceleration: float = 20.0
@export_range(5.0, 60.0, 0.5) var deceleration: float = 26.0
@export_range(1.0, 30.0, 0.5) var air_acceleration: float = 7.0
@export_range(2.0, 25.0, 0.5) var rotation_speed: float = 12.0

@export_group("State")
@export var is_carrying_heavy_cargo: bool = false

var peer_id: int = 1
var is_local_player: bool = true
var held_cargo: CargoBody = null
var seated_vehicle: TruckController = null
var seated_role: String = ""

# Host-side network input state for remote peers
var net_input_vector: Vector2 = Vector2.ZERO
var net_wants_sprint: bool = false
var net_wants_jump: bool = false
var net_cam_yaw_deg: float = 0.0
var net_rotate_dir: float = 0.0
var last_move_intent_world: Vector3 = Vector3.ZERO

# Client-side interpolation targets
var _has_net_snapshot: bool = false
var _interp_target_pos: Vector3 = Vector3.ZERO
var _interp_target_vel: Vector3 = Vector3.ZERO
var _interp_target_visual_yaw: float = 0.0

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot
@onready var body_mesh: MeshInstance3D = get_node_or_null("VisualRoot/BodyMesh") as MeshInstance3D
@onready var player_camera: PlayerCamera = $PlayerCamera
@onready var interaction_controller: InteractionController = $InteractionController


func _ready() -> void:
	_ensure_input_actions()
	rotation = Vector3.ZERO
	_interp_target_pos = global_position
	collision_mask = 1 | 8 | 16 # Collide with Environment (1), Cargo (8), and Vehicle (16)
	if interaction_controller != null:
		interaction_controller.setup(self, player_camera)


func configure_network_role(assigned_peer_id: int, local_controlled: bool) -> void:
	peer_id = assigned_peer_id
	is_local_player = local_controlled
	apply_player_color_for_peer(peer_id)

	if player_camera != null:
		player_camera.set_process(is_local_player)
		player_camera.set_process_unhandled_input(is_local_player)
		if player_camera.camera != null:
			player_camera.camera.current = is_local_player

	if interaction_controller != null:
		interaction_controller.set_physics_process(is_local_player)
		interaction_controller.set_process_unhandled_input(is_local_player)


func apply_player_color_for_peer(id: int) -> void:
	if body_mesh == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.roughness = 0.7
	if id == 1:
		mat.albedo_color = Color(0.95, 0.48, 0.16, 1.0) # Host: Delivery Orange
	elif id % 2 == 0:
		mat.albedo_color = Color(0.18, 0.62, 0.92, 1.0) # Client 2: Cobalt / Sky Blue
	else:
		mat.albedo_color = Color(0.28, 0.82, 0.46, 1.0) # Client 3+: Emerald Green
	body_mesh.material_override = mat


func is_host_simulation() -> bool:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return true
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return true
	return multiplayer.is_server()


func _physics_process(delta: float) -> void:
	if rotation != Vector3.ZERO:
		rotation = Vector3.ZERO

	if not is_host_simulation():
		_interpolate_client_state(delta)
		return

	if is_seated_in_vehicle():
		velocity = Vector3.ZERO
		return

	var input_vector: Vector2 = Vector2.ZERO
	var wants_sprint: bool = false
	var wants_jump: bool = false

	if is_local_player:
		input_vector = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back"
		)
		wants_sprint = Input.is_action_pressed("sprint")
		wants_jump = Input.is_action_just_pressed("jump")
		if player_camera != null:
			net_cam_yaw_deg = player_camera._yaw_degrees
		net_rotate_dir = 0.0
		if Input.is_action_pressed("rotate_left"):
			net_rotate_dir += 1.0
		if Input.is_action_pressed("rotate_right"):
			net_rotate_dir -= 1.0
	else:
		input_vector = net_input_vector
		wants_sprint = net_wants_sprint
		wants_jump = net_wants_jump
		net_wants_jump = false # Consume one-shot jump intent

	apply_movement_step(delta, input_vector, wants_sprint, wants_jump)
	move_and_slide()


func apply_remote_input_state(
	move_vec: Vector2,
	wants_sprint: bool,
	wants_jump: bool,
	cam_yaw_deg: float,
	rotate_dir: float
) -> void:
	net_input_vector = move_vec.limit_length(1.0)
	net_wants_sprint = wants_sprint
	if wants_jump:
		net_wants_jump = true
	net_cam_yaw_deg = cam_yaw_deg
	net_rotate_dir = clampf(rotate_dir, -1.0, 1.0)


func apply_authoritative_snapshot(
	auth_pos: Vector3,
	auth_vel: Vector3,
	auth_visual_yaw: float,
	carrying_flag: bool
) -> void:
	_interp_target_pos = auth_pos
	_interp_target_vel = auth_vel
	_interp_target_visual_yaw = auth_visual_yaw
	is_carrying_heavy_cargo = carrying_flag
	if not _has_net_snapshot:
		_has_net_snapshot = true
		global_position = auth_pos
		if visual_root != null:
			visual_root.rotation.y = auth_visual_yaw


func _interpolate_client_state(delta: float) -> void:
	if not _has_net_snapshot:
		return
	if is_seated_in_vehicle():
		return

	var dist: float = global_position.distance_to(_interp_target_pos)
	if dist > 4.0:
		global_position = _interp_target_pos
	else:
		var interp_rate: float = 18.0 if is_local_player else 15.0
		global_position = global_position.lerp(_interp_target_pos, clampf(interp_rate * delta, 0.0, 1.0))

	velocity = _interp_target_vel
	if visual_root != null:
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, _interp_target_visual_yaw, clampf(15.0 * delta, 0.0, 1.0))


func apply_movement_step(
	delta: float,
	input_vector: Vector2,
	wants_sprint: bool,
	wants_jump: bool
) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif wants_jump and can_jump():
		velocity.y = jump_velocity

	var move_direction: Vector3 = compute_world_move_direction(input_vector)
	last_move_intent_world = move_direction
	var target_speed: float = get_target_move_speed(wants_sprint)
	var target_horizontal_velocity: Vector3 = move_direction * target_speed

	# Apply gentle handle-stretch leash when carrying blocked/disagreed cargo so carriers feel resistance
	if is_holding_any_cargo() and held_cargo != null and held_cargo.carry_controller != null:
		var leash_pull: Vector3 = held_cargo.carry_controller.compute_carrier_leash_pullback(self)
		target_horizontal_velocity += leash_pull

	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var accel_rate: float = _choose_acceleration_rate(move_direction, is_on_floor())
	horizontal_velocity = horizontal_velocity.move_toward(
		target_horizontal_velocity,
		accel_rate * delta
	)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if move_direction.length_squared() > 0.001 and visual_root != null:
		var target_yaw: float = atan2(-move_direction.x, -move_direction.z)
		var turn_rate: float = rotation_speed * (0.55 if is_carrying_heavy_cargo else 1.0)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, clampf(turn_rate * delta, 0.0, 1.0))


func compute_world_move_direction(input_vector: Vector2) -> Vector3:
	if input_vector.length_squared() <= 0.0001:
		return Vector3.ZERO
	var basis_transform: Basis = Basis(Vector3.UP, deg_to_rad(net_cam_yaw_deg))
	if is_local_player and player_camera != null:
		basis_transform = player_camera.get_horizontal_basis()
	var direction: Vector3 = (basis_transform * Vector3(input_vector.x, 0.0, input_vector.y))
	direction.y = 0.0
	return direction.normalized()


func get_world_move_intent() -> Vector3:
	return last_move_intent_world


func get_target_move_speed(wants_sprint: bool) -> float:
	if is_carrying_heavy_cargo or is_holding_any_cargo():
		if held_cargo != null:
			if held_cargo.get_required_carriers() > 1 and held_cargo.get_carrier_count() < held_cargo.get_required_carriers():
				return carry_speed * 0.35
			if held_cargo.carry_controller != null:
				return carry_speed * held_cargo.carry_controller.coop_speed_multiplier
		return carry_speed
	if wants_sprint:
		return sprint_speed
	return walk_speed


func can_jump() -> bool:
	return not is_carrying_heavy_cargo and not is_holding_any_cargo() and not is_seated_in_vehicle()


func is_seated_in_vehicle() -> bool:
	return seated_vehicle != null and is_instance_valid(seated_vehicle)


func on_entered_vehicle(vehicle: TruckController, role: String) -> void:
	seated_vehicle = vehicle
	seated_role = role
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	if collision_shape != null:
		collision_shape.disabled = true
	if visual_root != null:
		visual_root.visible = false
	if is_local_player and player_camera != null:
		player_camera.set_vehicle_camera_mode(true, vehicle)


func on_exited_vehicle(vehicle: TruckController, exit_world_pos: Vector3) -> void:
	var exit_yaw: float = vehicle.global_rotation.y if vehicle != null else 0.0
	seated_vehicle = null
	seated_role = ""
	velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, exit_world_pos)
	_interp_target_pos = exit_world_pos
	if visual_root != null:
		visual_root.visible = true
		visual_root.rotation = Vector3(0.0, exit_yaw, 0.0)
	if collision_shape != null:
		collision_shape.disabled = false
	if is_local_player and player_camera != null:
		player_camera.set_vehicle_camera_mode(false, null)
		player_camera.align_yaw_to_world_angle(exit_yaw)


func try_exit_seated_vehicle() -> Dictionary:
	if not is_seated_in_vehicle():
		return {"success": false, "message": ""}
	return seated_vehicle.try_exit_vehicle(self)


func is_holding_any_cargo() -> bool:
	return held_cargo != null and is_instance_valid(held_cargo)


func on_cargo_grabbed(cargo: CargoBody) -> void:
	held_cargo = cargo
	is_carrying_heavy_cargo = true


func on_cargo_released(cargo: CargoBody) -> void:
	if held_cargo == cargo:
		held_cargo = null
	is_carrying_heavy_cargo = false


func release_held_cargo() -> String:
	if not is_holding_any_cargo():
		return ""
	var item_name: String = held_cargo.get_display_name()
	held_cargo.release_actor(self, "Released by player")
	held_cargo = null
	is_carrying_heavy_cargo = false
	return "Dropped %s" % item_name


func get_carry_forward_direction() -> Vector3:
	if is_local_player and player_camera != null:
		var cam_basis: Basis = player_camera.get_horizontal_basis()
		return (-cam_basis.z).normalized()
	var net_basis: Basis = Basis(Vector3.UP, deg_to_rad(net_cam_yaw_deg))
	return (-net_basis.z).normalized()


func _choose_acceleration_rate(move_direction: Vector3, on_floor: bool) -> float:
	if not on_floor:
		return air_acceleration
	if move_direction.length_squared() > 0.001:
		return acceleration
	return deceleration


static func _ensure_input_actions() -> void:
	var default_keys: Dictionary = {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"sprint": KEY_SHIFT,
		"jump": KEY_SPACE,
		"interact": KEY_E,
		"rotate_left": KEY_Q,
		"rotate_right": KEY_R,
		"secure_cargo": KEY_F,
		"handbrake": KEY_SPACE,
		"pause": KEY_ESCAPE,
	}
	for action_name: String in default_keys.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		if InputMap.action_get_events(action_name).is_empty():
			var key_event: InputEventKey = InputEventKey.new()
			key_event.physical_keycode = default_keys[action_name]
			InputMap.action_add_event(action_name, key_event)
