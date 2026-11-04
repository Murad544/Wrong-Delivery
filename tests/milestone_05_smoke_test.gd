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

	var spawner: PlayerSpawner = level.player_spawner
	var sofa: CargoBody = level.get_node_or_null("CargoItems/WarehouseSofa") as CargoBody

	if spawner == null or sofa == null:
		failures.append("Missing PlayerSpawner or WarehouseSofa in sofa_delivery.tscn")
	else:
		var p1: PlayerController = spawner.get_player(1)
		var p2: PlayerController = spawner.ensure_player_for_peer(2)
		var ctrl: CarryController = sofa.carry_controller

		# Position p1 at LeftHandle (0) and p2 at RightHandle (1)
		p1.global_position = sofa.global_position + Vector3(-1.15, 0.0, 0.8)
		p2.global_position = sofa.global_position + Vector3(1.15, 0.0, 0.8)

		# 1. Single player grabs LeftHandle -> under-staffed (1/2)
		sofa.interact_with_handle(0, p1)
		if sofa.get_carrier_count() != 1 or ctrl.is_fully_staffed():
			failures.append("Sofa with 1 carrier should report 1/2 and not be fully staffed")

		# 2. Second player grabs RightHandle -> full co-op lift (2/2)
		sofa.interact_with_handle(1, p2)
		if sofa.get_carrier_count() != 2 or not ctrl.is_fully_staffed():
			failures.append("Sofa with 2 carriers on Left & Right handles should be fully staffed (2/2)")

		# 3. Both move in same direction -> full carry speed, low strain
		p1.last_move_intent_world = Vector3(0.0, 0.0, 1.0)
		p2.last_move_intent_world = Vector3(0.0, 0.0, 1.0)
		ctrl._evaluate_coop_coordination(0.016)
		if ctrl.coop_speed_multiplier < 0.9:
			failures.append("Same-direction co-op carry should have speed multiplier >= 0.9, got %.2f" % ctrl.coop_speed_multiplier)
		if ctrl.current_strain_ratio > 0.35:
			failures.append("Same-direction co-op carry should have low strain, got %.2f" % ctrl.current_strain_ratio)

		# 4. One moves, one stays -> slower progress and visible tilt/strain
		p1.last_move_intent_world = Vector3(0.0, 0.0, 1.0)
		p2.last_move_intent_world = Vector3.ZERO
		ctrl._evaluate_coop_coordination(0.016)
		if ctrl.coop_speed_multiplier > 0.65 or ctrl.coop_speed_multiplier < 0.45:
			failures.append("One-moving/one-stationary should have ~0.55 speed multiplier, got %.2f" % ctrl.coop_speed_multiplier)
		if absf(ctrl._target_roll_tilt_rad) < 0.05:
			failures.append("One-moving/one-stationary should produce visible tilt")

		# 5. Opposite directions -> little net progress, high strain
		p1.last_move_intent_world = Vector3(0.0, 0.0, -1.0)
		p2.last_move_intent_world = Vector3(0.0, 0.0, 1.0)
		ctrl._evaluate_coop_coordination(0.016)
		if ctrl.coop_speed_multiplier > 0.25:
			failures.append("Opposite-direction co-op carry should have low speed multiplier <= 0.25, got %.2f" % ctrl.coop_speed_multiplier)
		if ctrl.current_strain_ratio < 0.7:
			failures.append("Opposite-direction co-op carry should produce high strain >= 0.7, got %.2f" % ctrl.current_strain_ratio)

		# 6. One carrier releases -> grace period active
		p2.release_held_cargo()
		if sofa.get_carrier_count() != 1 or ctrl._single_release_grace_timer <= 0.0:
			failures.append("Releasing 1 of 2 carriers should activate single_release_grace_timer")

		# 7. Exceeding separation distance auto-detaches safely
		sofa.interact_with_handle(1, p2)
		p2.global_position = p1.global_position + Vector3(7.0, 0.0, 0.0)
		ctrl._validate_carrier_distances()
		if sofa.get_carrier_count() != 0 or sofa.current_state != CargoBody.CargoState.FREE:
			failures.append("Exceeding carrier separation limit must auto-detach and return sofa to FREE")

	level.free()

	if not failures.is_empty():
		_fail_and_quit(failures)
		return

	print("[PASS] Milestone 05 smoke test succeeded.")
	quit(0)


func _fail_and_quit(failures: Array[String]) -> void:
	for failure: String in failures:
		printerr("[FAIL] %s" % failure)
	quit(1)
