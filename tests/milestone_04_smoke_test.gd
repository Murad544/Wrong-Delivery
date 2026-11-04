extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []

	var level_packed: PackedScene = load("res://scenes/levels/sofa_delivery.tscn") as PackedScene
	if level_packed == null:
		_fail_and_quit(["Failed to load res://scenes/levels/sofa_delivery.tscn"])
		return

	var level: SofaDeliveryLevel = level_packed.instantiate() as SofaDeliveryLevel
	root.add_child(level)
	await process_frame
	await physics_frame

	var net_mgr: NetworkManager = level.network_manager
	var spawner: PlayerSpawner = level.player_spawner
	var cargo_mgr: CargoManager = level.cargo_manager
	var sync_node: StateSync = level.state_sync
	var truck: TruckController = level.delivery_truck
	var crate: CargoBody = level.get_node_or_null("CargoItems/WarehouseCrate") as CargoBody

	if net_mgr == null or spawner == null or cargo_mgr == null or sync_node == null:
		failures.append("Missing networking managers on SofaDeliveryLevel")

	if spawner != null and cargo_mgr != null and sync_node != null and crate != null and truck != null:
		# 1. Spawn Peer 2 (Remote Client player)
		var peer2_player: PlayerController = spawner.ensure_player_for_peer(2)
		if peer2_player == null or spawner.get_player(2) != peer2_player:
			failures.append("PlayerSpawner failed to spawn PlayerController for peer 2")

		# 2. Verify host rejects out-of-range grab request from Peer 2
		peer2_player.global_position = crate.global_position + Vector3(0.0, 0.0, 12.0)
		var far_res: Dictionary = sync_node.process_host_interaction_request(
			2,
			"cargo_handle",
			crate.cargo_net_id,
			0,
			""
		)
		if bool(far_res.get("success", true)) or crate.get_carrier_count() != 0:
			failures.append("Host must reject out-of-range cargo grab request from client")

		# 3. Verify host accepts valid in-range grab request from Peer 2 (bypassing rate limit cooldown)
		cargo_mgr._last_request_time_by_peer.clear()
		peer2_player.global_position = crate.global_position + Vector3(0.0, 0.0, 1.2)
		var valid_res: Dictionary = sync_node.process_host_interaction_request(
			2,
			"cargo_handle",
			crate.cargo_net_id,
			0,
			""
		)
		if not bool(valid_res.get("success", false)) or peer2_player.held_cargo != crate:
			failures.append("Host should accept valid in-range grab from Peer 2 (got: %s)" % str(valid_res))

		# 4. Verify simultaneous grab of same handle by Peer 1 is rejected
		cargo_mgr._last_request_time_by_peer.clear()
		var peer1_player: PlayerController = spawner.get_player(1)
		peer1_player.global_position = crate.global_position + Vector3(0.0, 0.0, -1.2)
		var conflict_res: Dictionary = sync_node.process_host_interaction_request(
			1,
			"cargo_handle",
			crate.cargo_net_id,
			0,
			""
		)
		if bool(conflict_res.get("success", true)) or peer1_player.is_holding_any_cargo():
			failures.append("Host must reject second player grabbing an already occupied handle")

		# 5. Verify snapshot generation includes both players, cargos, and truck
		var snap: Dictionary = sync_node.build_authoritative_snapshot()
		var snap_players: Array = snap.get("players", [])
		var snap_cargos: Array = snap.get("cargos", [])
		if snap_players.size() != 2 or snap_cargos.size() < 2:
			failures.append("Authoritative snapshot should contain 2 players and >=2 cargos")

		# 6. Verify disconnect cleanup releases held cargo and truck seats safely
		spawner.remove_player_for_peer(2)
		if crate.get_carrier_count() != 0 or crate.current_state != CargoBody.CargoState.FREE:
			failures.append("Disconnecting Peer 2 while holding crate must release handle and return crate to FREE")

		# Re-spawn Peer 2, put in truck driver seat, then disconnect while truck is moving
		var peer2_again: PlayerController = spawner.ensure_player_for_peer(2)
		truck.try_enter_seat(peer2_again, 0)
		truck.forward_speed = 9.0
		spawner.remove_player_for_peer(2)
		if truck.driver_actor != null:
			failures.append("Disconnecting Peer 2 while driving must clear truck driver seat ownership")

	level.free()

	if not failures.is_empty():
		_fail_and_quit(failures)
		return

	print("[PASS] Milestone 04 smoke test succeeded.")
	quit(0)


func _fail_and_quit(failures: Array[String]) -> void:
	for failure: String in failures:
		printerr("[FAIL] %s" % failure)
	quit(1)
