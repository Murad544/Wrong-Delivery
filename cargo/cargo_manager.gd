class_name CargoManager
extends Node

@export_range(0.02, 0.5, 0.01) var min_request_interval_sec: float = 0.08

# Maps cargo_net_id (int) -> CargoBody
var cargos_by_id: Dictionary = {}
# Maps peer_id (int) -> last request time in seconds
var _last_request_time_by_peer: Dictionary = {}


func register_cargos(cargo_list: Array[CargoBody]) -> void:
	cargos_by_id.clear()
	var next_id: int = 1
	for cargo: CargoBody in cargo_list:
		if cargo != null and is_instance_valid(cargo):
			cargo.cargo_net_id = next_id
			cargos_by_id[next_id] = cargo
			next_id += 1


func get_cargo(cargo_id: int) -> CargoBody:
	return cargos_by_id.get(cargo_id, null) as CargoBody


func get_all_cargos() -> Array[CargoBody]:
	var list: Array[CargoBody] = []
	for key_val: Variant in cargos_by_id.keys():
		var c: CargoBody = cargos_by_id[key_val] as CargoBody
		if c != null and is_instance_valid(c):
			list.append(c)
	return list


func check_rate_limit(peer_id: int) -> bool:
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var last_sec: float = float(_last_request_time_by_peer.get(peer_id, -10.0))
	if now_sec - last_sec < min_request_interval_sec:
		return false
	_last_request_time_by_peer[peer_id] = now_sec
	return true


func validate_and_process_handle_request(
	peer_id: int,
	player: PlayerController,
	cargo_id: int,
	handle_id: int
) -> Dictionary:
	if not check_rate_limit(peer_id):
		return {"success": false, "message": "Interaction rate limit exceeded"}
	if player == null or not is_instance_valid(player):
		return {"success": false, "message": "Invalid player"}
	if player.is_seated_in_vehicle():
		return {"success": false, "message": "Cannot grab cargo while seated in truck"}

	var cargo: CargoBody = get_cargo(cargo_id)
	if cargo == null or not is_instance_valid(cargo):
		return {"success": false, "message": "Cargo not found"}

	# If player is already holding this cargo, allow releasing it immediately
	if player.held_cargo == cargo:
		var rel_msg: String = player.release_held_cargo()
		return {"success": true, "message": rel_msg}

	if player.is_holding_any_cargo():
		return {"success": false, "message": "Hands full — release held cargo first"}

	var handle: CargoHandle = cargo._find_handle(handle_id)
	if handle == null:
		return {"success": false, "message": "Invalid handle"}

	var origin: Vector3 = player.global_position + Vector3(0.0, 1.25, 0.0)
	if player.interaction_controller != null:
		origin = player.interaction_controller.global_position

	var check: Dictionary = cargo.evaluate_handle_interaction(handle_id, origin)
	if not bool(check.get("allowed", false)):
		return {
			"success": false,
			"message": String(check.get("reason", "Cannot grab handle"))
		}

	if player.interaction_controller != null and not player.interaction_controller.has_line_of_sight(handle):
		return {
			"success": false,
			"message": "Line of sight to handle is blocked by obstacle"
		}

	var msg: String = cargo.interact_with_handle(handle_id, player)
	var succeeded: bool = (player.held_cargo == cargo)
	return {
		"success": succeeded,
		"message": msg
	}
