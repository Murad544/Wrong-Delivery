extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []

	var level_packed: PackedScene = load("res://scenes/levels/sofa_delivery.tscn") as PackedScene
	if level_packed == null:
		_fail_and_quit(["Failed to load res://scenes/levels/sofa_delivery.tscn"])
		return

	var level: Node = level_packed.instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame

	var player: PlayerController = level.get_node_or_null("Player") as PlayerController
	var truck: TruckController = level.get_node_or_null("DeliveryTruck") as TruckController
	var crate: CargoBody = level.get_node_or_null("CargoItems/WarehouseCrate") as CargoBody

	if player == null:
		failures.append("Player missing in sofa_delivery.tscn")
	if truck == null:
		failures.append("DeliveryTruck missing in sofa_delivery.tscn")
	if crate == null:
		failures.append("WarehouseCrate missing in sofa_delivery.tscn")

	if player != null and truck != null and crate != null:
		var bay: CargoBay = truck.cargo_bay
		if bay == null:
			failures.append("CargoBay missing on DeliveryTruck")

		# 1. Verify AGENTS.md §6 initial truck tuning values
		if not is_equal_approx(truck.max_forward_speed, 14.0):
			failures.append("Expected max_forward_speed 14.0, got %.1f" % truck.max_forward_speed)
		if not is_equal_approx(truck.max_reverse_speed, 5.0):
			failures.append("Expected max_reverse_speed 5.0, got %.1f" % truck.max_reverse_speed)
		if not is_equal_approx(truck.acceleration, 8.0):
			failures.append("Expected acceleration 8.0, got %.1f" % truck.acceleration)
		if not is_equal_approx(truck.braking_deceleration, 14.0):
			failures.append("Expected braking_deceleration 14.0, got %.1f" % truck.braking_deceleration)
		if not is_equal_approx(truck.max_steering_angle_degrees, 30.0):
			failures.append("Expected max_steering_angle_degrees 30.0, got %.1f" % truck.max_steering_angle_degrees)

		# 2. Prevent entering vehicle while holding cargo
		crate.interact_with_handle(0, player)
		truck.try_enter_seat(player, 0)
		if truck.driver_actor == player or player.is_seated_in_vehicle():
			failures.append("Player should not be allowed to enter truck while holding cargo")
		player.release_held_cargo()

		# 3. Enter Driver Seat, verify driving step & high-speed exit restriction
		truck.try_enter_seat(player, 0)
		if truck.driver_actor != player or not player.is_seated_in_vehicle():
			failures.append("Player should be seated as Driver after try_enter_seat")

		truck.apply_driving_step(0.5, 1.0, 0.5, false)
		if truck.forward_speed <= 0.0:
			failures.append("Truck should accelerate forward on positive throttle")

		# Verify Arcade Drift & Mini-Turbo Drift Boost mechanic
		truck.forward_speed = 10.0
		truck.apply_driving_step(0.8, 1.0, 1.0, true) # Handbrake + Full Left Steer at 10 m/s
		if not truck.is_drifting or truck.drift_charge_ratio < 0.85:
			failures.append("Truck should enter drift mode and charge drift boost when handbraking + steering at speed")
		truck.apply_driving_step(0.1, 1.0, 0.0, false) # Release handbrake -> trigger Drift Boost!
		if truck.drift_boost_timer <= 0.0 or truck.drift_boost_count < 1:
			failures.append("Releasing handbrake after a charged drift should trigger Mini-Turbo Drift Boost")

		truck.forward_speed = 8.0
		var fast_exit: Dictionary = truck.try_exit_vehicle(player)
		if bool(fast_exit.get("success", true)) or not player.is_seated_in_vehicle():
			failures.append("Exiting truck at high speed (8.0 m/s) should be restricted")

		truck.forward_speed = 0.0
		var parked_exit: Dictionary = truck.try_exit_vehicle(player)
		if not bool(parked_exit.get("success", false)) or player.is_seated_in_vehicle():
			failures.append("Exiting stationary truck should succeed")

		# Regression check: player root rotation must stay zero and WASD movement must match camera horizontal basis after exiting rotated truck
		if not player.rotation.is_zero_approx():
			failures.append("Player root rotation should remain zero after exiting rotated truck, got %s" % str(player.rotation))
		var forward_move_vec: Vector3 = player.compute_world_move_direction(Vector2(0.0, -1.0))
		var expected_cam_fwd: Vector3 = (-player.player_camera.get_horizontal_basis().z).normalized()
		if forward_move_vec.distance_to(expected_cam_fwd) > 0.01:
			failures.append("Player W movement direction desynced from camera forward after exiting truck")

		# 4. Load cargo into bay, test unsecured sliding vs secured stability, then unload
		if bay != null:
			crate.global_position = bay.global_position + Vector3(0.0, 0.4, 0.0)
			if not bay.load_cargo_immediately(crate, false):
				failures.append("load_cargo_immediately should succeed")
			if crate.current_state != CargoBody.CargoState.LOADED_UNSECURED:
				failures.append("Loaded crate should be in LOADED_UNSECURED state")

			var before_slide_pos: Vector3 = crate.global_position
			bay.step_bay_physics(0.2, 10.0, 8.0, false)
			if crate.global_position.distance_to(before_slide_pos) < 0.01:
				failures.append("Unsecured cargo should slide under strong acceleration/turning")

			# Secure cargo while parked
			var sec_res: Dictionary = bay.toggle_secure_loaded_cargo(player)
			if not bool(sec_res.get("success", false)) or crate.current_state != CargoBody.CargoState.SECURED:
				failures.append("Securing loaded cargo while parked should transition to SECURED")

			var secured_pos_local: Vector3 = bay.global_transform.affine_inverse() * crate.global_position
			bay.step_bay_physics(0.2, 12.0, 10.0, false)
			var after_secured_local: Vector3 = bay.global_transform.affine_inverse() * crate.global_position
			if secured_pos_local.distance_to(after_secured_local) > 0.001:
				failures.append("Secured cargo should not slide relative to the cargo bay")

			# Unsecure and unload back to CARRIED without spurious damage
			bay.toggle_secure_loaded_cargo(player)
			if crate.current_state != CargoBody.CargoState.LOADED_UNSECURED:
				failures.append("Toggling straps again should return cargo to LOADED_UNSECURED")

			var dur_before_unload: float = crate.cargo_damage.current_durability
			crate.interact_with_handle(0, player)
			if crate.current_state != CargoBody.CargoState.CARRIED or bay.has_loaded_cargo():
				failures.append("Grabbing unsecured cargo from bay should unload it into CARRIED state")
			if not is_equal_approx(crate.cargo_damage.current_durability, dur_before_unload):
				failures.append("Unloading cargo should not cause spurious damage")
			player.release_held_cargo()

	level.free()

	if not failures.is_empty():
		_fail_and_quit(failures)
		return

	print("[PASS] Milestone 03 smoke test succeeded.")
	quit(0)


func _fail_and_quit(failures: Array[String]) -> void:
	for failure: String in failures:
		printerr("[FAIL] %s" % failure)
	quit(1)
