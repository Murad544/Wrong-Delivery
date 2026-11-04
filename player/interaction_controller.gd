class_name InteractionController
extends Node3D

signal prompt_changed(prompt_text: String, is_valid: bool)
signal interaction_feedback(message: String, is_error: bool)

@export_range(1.0, 8.0, 0.1) var reach_distance: float = 3.0
@export_range(0.1, 1.0, 0.05) var min_view_alignment_dot: float = 0.35
@export_flags_3d_physics var obstruction_collision_mask: int = 1 # Layer 1: Environment
@export_flags_3d_physics var interactable_collision_mask: int = 4 # Layer 3: Interactable

var player_body: CharacterBody3D = null
var player_camera: PlayerCamera = null

var _nearby_targets: Array[InteractableTarget] = []
var _current_target: InteractableTarget = null
var _last_prompt_text: String = ""
var _last_prompt_valid: bool = false

@onready var proximity_detector: Area3D = $ProximityDetector


func _ready() -> void:
	if proximity_detector != null:
		proximity_detector.collision_layer = 0
		proximity_detector.collision_mask = interactable_collision_mask
		proximity_detector.monitoring = true
		proximity_detector.monitorable = false
		proximity_detector.area_entered.connect(_on_proximity_area_entered)
		proximity_detector.area_exited.connect(_on_proximity_area_exited)


func setup(owner_body: CharacterBody3D, camera_rig: PlayerCamera) -> void:
	player_body = owner_body
	player_camera = camera_rig


func _physics_process(_delta: float) -> void:
	_update_best_target()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if try_interact():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("secure_cargo"):
		if try_secure_cargo_action():
			get_viewport().set_input_as_handled()


func try_interact() -> bool:
	var is_client_mode: bool = (
		player_body != null
		and player_body.has_method("is_host_simulation")
		and not bool(player_body.call("is_host_simulation"))
	)
	var state_sync: StateSync = _find_state_sync() if is_client_mode else null

	if player_body != null and player_body.has_method("is_seated_in_vehicle") and bool(player_body.call("is_seated_in_vehicle")):
		if state_sync != null:
			state_sync.request_client_interaction("exit_vehicle")
			return true
		var exit_res: Dictionary = player_body.call("try_exit_seated_vehicle")
		var ok: bool = bool(exit_res.get("success", false))
		var msg: String = String(exit_res.get("message", ""))
		interaction_feedback.emit(msg, not ok)
		_update_best_target(true)
		return true

	if player_body != null and player_body.has_method("is_holding_any_cargo") and bool(player_body.call("is_holding_any_cargo")):
		if state_sync != null:
			state_sync.request_client_interaction("release_cargo")
			return true
		var release_msg: String = String(player_body.call("release_held_cargo"))
		interaction_feedback.emit(release_msg, false)
		_update_best_target(true)
		return true

	_update_best_target()
	if _current_target == null:
		return false

	var actor: Node3D = player_body if player_body != null else self
	var check: Dictionary = _current_target.can_interact_from(global_position)
	if not bool(check.get("allowed", false)):
		var reason: String = String(check.get("reason", "Cannot interact"))
		interaction_feedback.emit(reason, true)
		return true

	if not has_line_of_sight(_current_target):
		interaction_feedback.emit("Blocked by obstacle", true)
		return true

	if state_sync != null:
		_dispatch_client_target_request(state_sync, _current_target)
		return true

	var message: String = _current_target.perform_interaction(actor)
	interaction_feedback.emit(message, false)
	_update_best_target(true)
	return true


func try_secure_cargo_action() -> bool:
	var is_client_mode: bool = (
		player_body != null
		and player_body.has_method("is_host_simulation")
		and not bool(player_body.call("is_host_simulation"))
	)
	var state_sync: StateSync = _find_state_sync() if is_client_mode else null

	if player_body != null and player_body.has_method("is_seated_in_vehicle") and bool(player_body.call("is_seated_in_vehicle")):
		interaction_feedback.emit("Exit the truck cab to strap cargo at the rear bay", true)
		return true

	if player_body != null and player_body.has_method("is_holding_any_cargo") and bool(player_body.call("is_holding_any_cargo")):
		interaction_feedback.emit("Drop held cargo in the bay first, then press F to strap", true)
		return true

	var anchor_target: InteractableTarget = null
	if _current_target is TruckInteractable and (_current_target as TruckInteractable).role == "CargoAnchor":
		anchor_target = _current_target
	else:
		for candidate: InteractableTarget in _nearby_targets:
			if candidate is TruckInteractable and (candidate as TruckInteractable).role == "CargoAnchor":
				var dist: float = global_position.distance_to(candidate.global_position)
				if dist <= candidate.max_interaction_distance and has_line_of_sight(candidate):
					anchor_target = candidate
					break

	if anchor_target == null:
		return false

	var actor: Node3D = player_body if player_body != null else self
	var check: Dictionary = anchor_target.can_interact_from(global_position)
	if not bool(check.get("allowed", false)):
		interaction_feedback.emit(String(check.get("reason", "Cannot secure cargo")), true)
		return true

	if state_sync != null:
		state_sync.request_client_interaction("truck_role", 0, 0, "CargoAnchor")
		return true

	var msg: String = anchor_target.perform_interaction(actor)
	interaction_feedback.emit(msg, false)
	_update_best_target(true)
	return true


func _find_state_sync() -> StateSync:
	if get_tree() == null or get_tree().current_scene == null:
		return null
	return get_tree().current_scene.get_node_or_null("StateSync") as StateSync


func _dispatch_client_target_request(state_sync: StateSync, target: InteractableTarget) -> void:
	if target is CargoHandle:
		var handle: CargoHandle = target as CargoHandle
		var cargo: CargoBody = handle.cargo_owner as CargoBody
		if cargo != null:
			state_sync.request_client_interaction("cargo_handle", cargo.cargo_net_id, handle.handle_id)
	elif target is TruckInteractable:
		var ti: TruckInteractable = target as TruckInteractable
		state_sync.request_client_interaction("truck_role", 0, 0, ti.role)
	else:
		state_sync.request_client_interaction("level_prop", 0, 0, String(target.get_path()))


func get_current_target() -> InteractableTarget:
	return _current_target


func has_line_of_sight(target: InteractableTarget) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return false

	var origin: Vector3 = global_position
	var destination: Vector3 = target.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin,
		destination,
		obstruction_collision_mask
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if player_body != null:
		query.exclude = [player_body.get_rid()]

	var hit: Dictionary = space_state.intersect_ray(query)
	return hit.is_empty()


func _update_best_target(force_emit: bool = false) -> void:
	if player_body != null and player_body.has_method("is_seated_in_vehicle") and bool(player_body.call("is_seated_in_vehicle")):
		_current_target = null
		var role_str: String = String(player_body.get("seated_role"))
		var vehicle_prompt: String = "E — Exit Truck (%s)  |  WASD: Drive  |  Space: Handbrake" % role_str
		if role_str == "Passenger":
			vehicle_prompt = "E — Exit Truck (Passenger)  |  Watch Cargo Stability HUD"
		if force_emit or vehicle_prompt != _last_prompt_text or not _last_prompt_valid:
			_last_prompt_text = vehicle_prompt
			_last_prompt_valid = true
			prompt_changed.emit(vehicle_prompt, true)
		return

	if player_body != null and player_body.has_method("is_holding_any_cargo") and bool(player_body.call("is_holding_any_cargo")):
		_current_target = null
		var held: CargoBody = player_body.get("held_cargo") as CargoBody
		var held_name: String = held.get_display_name() if held != null else "Cargo"
		var carry_prompt: String = "E — Drop %s  |  Q / R — Rotate" % held_name
		if held != null and held.carry_controller != null and held.get_required_carriers() > 1:
			var strain_pct: float = held.carry_controller.current_strain_ratio * 100.0
			var coord_txt: String = held.carry_controller.coordination_state_text
			carry_prompt = "E — Drop %s  |  Q/R — Rotate  |  [%s | Strain: %.0f%%]" % [
				held_name,
				coord_txt,
				strain_pct,
			]
		if force_emit or carry_prompt != _last_prompt_text or not _last_prompt_valid:
			_last_prompt_text = carry_prompt
			_last_prompt_valid = true
			prompt_changed.emit(carry_prompt, true)
		return

	var candidate: InteractableTarget = _find_raycast_target()
	if candidate == null:
		candidate = _find_best_proximity_target()

	_current_target = candidate

	var new_prompt: String = ""
	var new_valid: bool = false
	if _current_target != null:
		var check: Dictionary = _current_target.can_interact_from(global_position)
		new_valid = bool(check.get("allowed", false))
		new_prompt = _current_target.get_prompt_text()

	if force_emit or new_prompt != _last_prompt_text or new_valid != _last_prompt_valid:
		_last_prompt_text = new_prompt
		_last_prompt_valid = new_valid
		prompt_changed.emit(new_prompt, new_valid)


func _find_raycast_target() -> InteractableTarget:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return null

	var ray_origin: Vector3 = global_position
	var ray_dir: Vector3 = -global_transform.basis.z.normalized()
	var max_ray_len: float = reach_distance

	if player_camera != null:
		ray_origin = player_camera.get_camera_position()
		ray_dir = player_camera.get_forward_direction()
		var cam_to_player: float = ray_origin.distance_to(global_position)
		max_ray_len = cam_to_player + reach_distance + 0.5

	var ray_end: Vector3 = ray_origin + ray_dir * max_ray_len
	var combined_mask: int = obstruction_collision_mask | interactable_collision_mask
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		combined_mask
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	if player_body != null:
		query.exclude = [player_body.get_rid()]

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var collider: Object = hit.get("collider")
	if collider is InteractableTarget:
		var target: InteractableTarget = collider as InteractableTarget
		var dist: float = global_position.distance_to(target.global_position)
		var allowed_dist: float = minf(reach_distance, target.max_interaction_distance)
		if dist <= allowed_dist and has_line_of_sight(target):
			return target

	return null


func _find_best_proximity_target() -> InteractableTarget:
	var best_target: InteractableTarget = null
	var best_score: float = -INF

	var look_dir: Vector3 = -global_transform.basis.z.normalized()
	if player_camera != null:
		look_dir = player_camera.get_forward_direction()
	var horizontal_look: Vector3 = Vector3(look_dir.x, 0.0, look_dir.z).normalized()
	if horizontal_look.length_squared() < 0.001:
		horizontal_look = -global_transform.basis.z.normalized()

	for i in range(_nearby_targets.size() - 1, -1, -1):
		var target: InteractableTarget = _nearby_targets[i]
		if target == null or not is_instance_valid(target):
			_nearby_targets.remove_at(i)
			continue

		var to_target: Vector3 = target.global_position - global_position
		var dist: float = to_target.length()
		var allowed_dist: float = minf(reach_distance, target.max_interaction_distance)
		if dist > allowed_dist or dist < 0.001:
			continue

		var flat_to_target: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
		var alignment: float = 1.0
		if flat_to_target.length_squared() > 0.001:
			alignment = horizontal_look.dot(flat_to_target.normalized())

		if alignment < min_view_alignment_dot:
			continue

		if not has_line_of_sight(target):
			continue

		var score: float = alignment * 2.0 - (dist / allowed_dist)
		if score > best_score:
			best_score = score
			best_target = target

	return best_target


func _on_proximity_area_entered(area: Area3D) -> void:
	if area is InteractableTarget:
		var target: InteractableTarget = area as InteractableTarget
		if not _nearby_targets.has(target):
			_nearby_targets.append(target)


func _on_proximity_area_exited(area: Area3D) -> void:
	if area is InteractableTarget:
		var target: InteractableTarget = area as InteractableTarget
		_nearby_targets.erase(target)
