class_name StateSync
extends Node

signal latency_simulation_changed(latency_ms: float, loss_ratio: float)

@export_range(10.0, 60.0, 1.0) var input_send_rate_hz: float = 30.0
@export_range(10.0, 60.0, 1.0) var snapshot_send_rate_hz: float = 20.0
@export_range(0.0, 300.0, 10.0) var simulated_latency_ms: float = 0.0
@export_range(0.0, 0.25, 0.01) var simulated_packet_loss: float = 0.0

var network_manager: NetworkManager = null
var player_spawner: PlayerSpawner = null
var cargo_manager: CargoManager = null
var delivery_truck: TruckController = null
var game_hud: GameHUD = null

var _input_accum: float = 0.0
var _snapshot_accum: float = 0.0
var _delayed_packets: Array[Dictionary] = []


func setup(
	net_mgr: NetworkManager,
	spawner: PlayerSpawner,
	cargo_mgr: CargoManager,
	truck: TruckController,
	hud: GameHUD
) -> void:
	network_manager = net_mgr
	player_spawner = spawner
	cargo_manager = cargo_mgr
	delivery_truck = truck
	game_hud = hud


func cycle_simulated_latency() -> String:
	if simulated_latency_ms < 10.0:
		simulated_latency_ms = 60.0
		simulated_packet_loss = 0.02
	elif simulated_latency_ms < 80.0:
		simulated_latency_ms = 100.0
		simulated_packet_loss = 0.04
	else:
		simulated_latency_ms = 0.0
		simulated_packet_loss = 0.0

	latency_simulation_changed.emit(simulated_latency_ms, simulated_packet_loss)
	return "Net Sim: %.0f ms latency, %.0f%% packet loss" % [
		simulated_latency_ms,
		simulated_packet_loss * 100.0
	]


func _physics_process(delta: float) -> void:
	_flush_delayed_packets()

	if network_manager == null or not network_manager.is_online():
		return

	if multiplayer.is_server():
		_snapshot_accum += delta
		var snap_interval: float = 1.0 / maxf(snapshot_send_rate_hz, 1.0)
		if _snapshot_accum >= snap_interval:
			_snapshot_accum = fmod(_snapshot_accum, snap_interval)
			_broadcast_world_snapshot()
	else:
		_input_accum += delta
		var input_interval: float = 1.0 / maxf(input_send_rate_hz, 1.0)
		if _input_accum >= input_interval:
			_input_accum = fmod(_input_accum, input_interval)
			_send_local_client_inputs()


func request_client_interaction(
	action_kind: String,
	int_arg_a: int = 0,
	int_arg_b: int = 0,
	str_arg: String = ""
) -> void:
	if network_manager == null or not network_manager.is_online() or multiplayer.is_server():
		return
	rpc_request_interaction.rpc_id(1, action_kind, int_arg_a, int_arg_b, str_arg)


func _send_local_client_inputs() -> void:
	if player_spawner == null:
		return
	var local_player: PlayerController = player_spawner.get_local_player()
	if local_player == null:
		return

	var move_vec: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var wants_sprint: bool = Input.is_action_pressed("sprint")
	var wants_jump: bool = Input.is_action_pressed("jump")
	var cam_yaw: float = local_player.player_camera._yaw_degrees if local_player.player_camera != null else 0.0
	var rot_dir: float = 0.0
	if Input.is_action_pressed("rotate_left"):
		rot_dir += 1.0
	if Input.is_action_pressed("rotate_right"):
		rot_dir -= 1.0

	var throttle: float = Input.get_axis("move_back", "move_forward")
	var steer: float = Input.get_axis("move_right", "move_left")
	var handbrake: bool = Input.is_action_pressed("handbrake")

	var payload: Dictionary = {
		"move": move_vec,
		"sprint": wants_sprint,
		"jump": wants_jump,
		"cam_yaw": cam_yaw,
		"rot_dir": rot_dir,
		"throttle": throttle,
		"steer": steer,
		"handbrake": handbrake,
	}
	_send_or_queue_unreliable(true, payload)


func _broadcast_world_snapshot() -> void:
	var snapshot: Dictionary = build_authoritative_snapshot()
	_send_or_queue_unreliable(false, snapshot)


func build_authoritative_snapshot() -> Dictionary:
	var players_data: Array[Dictionary] = []
	if player_spawner != null:
		for pid_val: Variant in player_spawner.players_by_peer.keys():
			var pid: int = int(pid_val)
			var p: PlayerController = player_spawner.players_by_peer[pid] as PlayerController
			if p != null and is_instance_valid(p):
				var v_yaw: float = p.visual_root.rotation.y if p.visual_root != null else 0.0
				var held_id: int = p.held_cargo.cargo_net_id if p.is_holding_any_cargo() else 0
				players_data.append({
					"pid": pid,
					"pos": p.global_position,
					"vel": p.velocity,
					"vyaw": v_yaw,
					"carry": p.is_carrying_heavy_cargo,
					"held_id": held_id,
					"seat": p.seated_role,
				})

	var cargos_data: Array[Dictionary] = []
	if cargo_manager != null:
		for cargo: CargoBody in cargo_manager.get_all_cargos():
			var dur: float = cargo.cargo_damage.current_durability if cargo.cargo_damage != null else 100.0
			cargos_data.append({
				"cid": cargo.cargo_net_id,
				"pos": cargo.global_position,
				"rot": cargo.global_rotation,
				"vel": cargo.linear_velocity,
				"st": int(cargo.current_state),
				"dur": dur,
				"cnt": cargo.get_carrier_count(),
			})

	var truck_data: Dictionary = {}
	if delivery_truck != null and is_instance_valid(delivery_truck):
		var drv_pid: int = int(delivery_truck.driver_actor.get("peer_id")) if delivery_truck.driver_actor != null else 0
		var pas_pid: int = int(delivery_truck.passenger_actor.get("peer_id")) if delivery_truck.passenger_actor != null else 0
		var bay_stab: float = delivery_truck.cargo_bay.current_stability_ratio if delivery_truck.cargo_bay != null else 1.0
		var bay_warn: String = delivery_truck.cargo_bay.current_warning_text if delivery_truck.cargo_bay != null else "EMPTY"
		var bay_sec: bool = delivery_truck.cargo_bay.is_any_cargo_secured() if delivery_truck.cargo_bay != null else false
		truck_data = {
			"pos": delivery_truck.global_position,
			"yaw": delivery_truck.rotation.y,
			"spd": delivery_truck.forward_speed,
			"str": delivery_truck.current_steer_angle_rad,
			"lat": delivery_truck.lateral_acceleration,
			"hbk": delivery_truck.is_handbrake_active,
			"drv": drv_pid,
			"pas": pas_pid,
			"bst": bay_stab,
			"bwn": bay_warn,
			"bsc": bay_sec,
		}

	return {
		"players": players_data,
		"cargos": cargos_data,
		"truck": truck_data,
	}


func apply_world_snapshot_on_client(snapshot: Dictionary) -> void:
	if player_spawner != null and snapshot.has("players"):
		var p_list: Array = snapshot["players"]
		for entry_var: Variant in p_list:
			var entry: Dictionary = entry_var as Dictionary
			var pid: int = int(entry.get("pid", 0))
			if pid <= 0:
				continue
			var p: PlayerController = player_spawner.ensure_player_for_peer(pid)
			if p == null:
				continue
			p.apply_authoritative_snapshot(
				entry.get("pos", Vector3.ZERO),
				entry.get("vel", Vector3.ZERO),
				float(entry.get("vyaw", 0.0)),
				bool(entry.get("carry", false))
			)
			var held_id: int = int(entry.get("held_id", 0))
			if held_id > 0 and cargo_manager != null:
				p.held_cargo = cargo_manager.get_cargo(held_id)
			else:
				p.held_cargo = null

			var seat_role: String = String(entry.get("seat", ""))
			if not seat_role.is_empty() and delivery_truck != null:
				if p.seated_vehicle != delivery_truck or p.seated_role != seat_role:
					p.on_entered_vehicle(delivery_truck, seat_role)
			elif seat_role.is_empty() and p.is_seated_in_vehicle():
				p.on_exited_vehicle(delivery_truck, entry.get("pos", p.global_position))

	if cargo_manager != null and snapshot.has("cargos"):
		var c_list: Array = snapshot["cargos"]
		for c_var: Variant in c_list:
			var c_entry: Dictionary = c_var as Dictionary
			var cid: int = int(c_entry.get("cid", 0))
			var cargo: CargoBody = cargo_manager.get_cargo(cid)
			if cargo != null:
				cargo.apply_authoritative_snapshot(
					c_entry.get("pos", cargo.global_position),
					c_entry.get("rot", cargo.global_rotation),
					c_entry.get("vel", Vector3.ZERO),
					int(c_entry.get("st", 0)),
					float(c_entry.get("dur", 100.0)),
					int(c_entry.get("cnt", 0))
				)

	if delivery_truck != null and snapshot.has("truck"):
		var t_data: Dictionary = snapshot["truck"]
		if not t_data.is_empty():
			var drv_id: int = int(t_data.get("drv", 0))
			var pas_id: int = int(t_data.get("pas", 0))
			delivery_truck.driver_actor = player_spawner.get_player(drv_id) if (drv_id > 0 and player_spawner != null) else null
			delivery_truck.passenger_actor = player_spawner.get_player(pas_id) if (pas_id > 0 and player_spawner != null) else null
			delivery_truck.apply_authoritative_snapshot(
				t_data.get("pos", delivery_truck.global_position),
				float(t_data.get("yaw", delivery_truck.rotation.y)),
				float(t_data.get("spd", 0.0)),
				float(t_data.get("str", 0.0)),
				float(t_data.get("lat", 0.0)),
				bool(t_data.get("hbk", false)),
				float(t_data.get("bst", 1.0)),
				String(t_data.get("bwn", "EMPTY")),
				bool(t_data.get("bsc", false))
			)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_submit_client_input(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	process_host_received_input(sender_id, payload)


func process_host_received_input(sender_id: int, payload: Dictionary) -> void:
	if player_spawner == null:
		return
	var player: PlayerController = player_spawner.get_player(sender_id)
	if player == null:
		return

	player.apply_remote_input_state(
		payload.get("move", Vector2.ZERO),
		bool(payload.get("sprint", false)),
		bool(payload.get("jump", false)),
		float(payload.get("cam_yaw", 0.0)),
		float(payload.get("rot_dir", 0.0))
	)

	# Validate vehicle seat ownership: only the authoritative driver can steer/accelerate the truck
	if delivery_truck != null and delivery_truck.driver_actor == player:
		delivery_truck.apply_remote_driver_input(
			float(payload.get("throttle", 0.0)),
			float(payload.get("steer", 0.0)),
			bool(payload.get("handbrake", false))
		)


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_receive_world_snapshot(snapshot: Dictionary) -> void:
	if multiplayer.is_server():
		return
	apply_world_snapshot_on_client(snapshot)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_interaction(
	action_kind: String,
	int_arg_a: int,
	int_arg_b: int,
	str_arg: String
) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var res: Dictionary = process_host_interaction_request(sender_id, action_kind, int_arg_a, int_arg_b, str_arg)
	var msg: String = String(res.get("message", ""))
	var is_err: bool = not bool(res.get("success", false))
	if not msg.is_empty():
		rpc_notify_client_feedback.rpc_id(sender_id, msg, is_err)
	_broadcast_world_snapshot()


func process_host_interaction_request(
	sender_id: int,
	action_kind: String,
	int_arg_a: int,
	int_arg_b: int,
	str_arg: String
) -> Dictionary:
	if player_spawner == null or cargo_manager == null:
		return {"success": false, "message": "Server not ready"}

	var player: PlayerController = player_spawner.get_player(sender_id)
	if player == null or not is_instance_valid(player):
		return {"success": false, "message": "Player not registered on host"}

	match action_kind:
		"cargo_handle":
			return cargo_manager.validate_and_process_handle_request(sender_id, player, int_arg_a, int_arg_b)
		"release_cargo":
			if not player.is_holding_any_cargo():
				return {"success": false, "message": "Not holding any cargo"}
			return {"success": true, "message": player.release_held_cargo()}
		"exit_vehicle":
			if not player.is_seated_in_vehicle():
				return {"success": false, "message": "Not seated in vehicle"}
			return player.try_exit_seated_vehicle()
		"truck_role":
			if delivery_truck == null:
				return {"success": false, "message": "Truck unavailable"}
			if not cargo_manager.check_rate_limit(sender_id):
				return {"success": false, "message": "Rate limited"}
			# Verify authoritative distance to the truck
			if player.global_position.distance_to(delivery_truck.global_position) > 6.5:
				return {"success": false, "message": "Too far from delivery truck"}
			var check: Dictionary = delivery_truck.can_interact_with_role(str_arg, player.global_position)
			if not bool(check.get("allowed", false)):
				return {"success": false, "message": String(check.get("reason", "Cannot interact with truck"))}
			var msg: String = delivery_truck.interact_with_role(str_arg, player)
			return {"success": true, "message": msg}
		"level_prop":
			var prop_node: InteractableTarget = get_node_or_null(NodePath(str_arg)) as InteractableTarget
			if prop_node == null:
				return {"success": false, "message": "Interactable not found"}
			var check_p: Dictionary = prop_node.can_interact_from(player.global_position + Vector3(0.0, 1.25, 0.0))
			if not bool(check_p.get("allowed", false)):
				return {"success": false, "message": String(check_p.get("reason", "Cannot interact"))}
			if player.interaction_controller != null and not player.interaction_controller.has_line_of_sight(prop_node):
				return {"success": false, "message": "Blocked by wall"}
			var p_msg: String = prop_node.perform_interaction(player)
			return {"success": true, "message": p_msg}

	return {"success": false, "message": "Unknown interaction request"}


@rpc("authority", "call_remote", "reliable")
func rpc_notify_client_feedback(message: String, is_error: bool) -> void:
	if game_hud != null:
		game_hud.show_feedback_message(message, is_error)


func _send_or_queue_unreliable(is_client_to_host: bool, payload: Dictionary) -> void:
	if simulated_packet_loss > 0.0 and randf() < simulated_packet_loss:
		return

	if simulated_latency_ms <= 1.0:
		if is_client_to_host:
			rpc_submit_client_input.rpc_id(1, payload)
		else:
			rpc_receive_world_snapshot.rpc(payload)
		return

	var release_msec: int = Time.get_ticks_msec() + int(simulated_latency_ms * 0.5)
	_delayed_packets.append({
		"deliver_at": release_msec,
		"to_host": is_client_to_host,
		"payload": payload.duplicate(true),
	})


func _flush_delayed_packets() -> void:
	if _delayed_packets.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	while not _delayed_packets.is_empty():
		var first: Dictionary = _delayed_packets[0]
		if int(first.get("deliver_at", 0)) > now_msec:
			break
		_delayed_packets.pop_front()
		if network_manager == null or not network_manager.is_online():
			continue
		if bool(first.get("to_host", false)):
			if not multiplayer.is_server():
				rpc_submit_client_input.rpc_id(1, first["payload"])
		else:
			if multiplayer.is_server():
				rpc_receive_world_snapshot.rpc(first["payload"])
