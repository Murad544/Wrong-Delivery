extends SceneTree

func _init() -> void:
	var failures: Array[String] = []

	# 1. Verify deterministic ScoringSystem math (AGENTS.md §7)
	var perfect_score: Dictionary = ScoringSystem.calculate_mission_score(100.0, 100.0, 145.0, 300.0, 0, 15)
	if int(perfect_score.get("final_score", -1)) != 100:
		failures.append("Expected perfect score 100, got %s" % str(perfect_score))

	var penalty_score: Dictionary = ScoringSystem.calculate_mission_score(75.0, 100.0, 335.0, 300.0, 1, 15)
	# damage_penalty = 25, overtime_penalty = floor(35/10)*2 = 6, major_mistake_penalty = 15 -> 100 - 25 - 6 - 15 = 54
	if int(penalty_score.get("final_score", -1)) != 54:
		failures.append("Expected penalized score 54, got %d (%s)" % [int(penalty_score.get("final_score", -1)), str(penalty_score)])

	var clamped_zero: Dictionary = ScoringSystem.calculate_mission_score(0.0, 100.0, 600.0, 300.0, 4, 15)
	if int(clamped_zero.get("final_score", -1)) != 0:
		failures.append("Expected clamped minimum score 0, got %d" % int(clamped_zero.get("final_score", -1)))

	# 2. Load and instantiate SofaDeliveryLevel
	var level_packed: PackedScene = load("res://scenes/levels/sofa_delivery.tscn") as PackedScene
	if level_packed == null:
		_fail_and_quit(["Failed to load res://scenes/levels/sofa_delivery.tscn"])
		return

	var level: SofaDeliveryLevel = level_packed.instantiate() as SofaDeliveryLevel
	root.add_child(level)

	var sofa: CargoBody = level.get_node_or_null("CargoItems/WarehouseSofa") as CargoBody
	var zone: DeliveryZone = level.delivery_zone
	var mission_mgr: MissionManager = level.mission_manager
	var results_ui: ResultsScreen = level.results_screen
	var p1: PlayerController = level.player

	if sofa == null or zone == null or mission_mgr == null or results_ui == null or p1 == null:
		failures.append("Missing required Milestone 06 nodes on SofaDeliveryLevel")
	else:
		# Verify expanded small-town environment generation & 20 Maple St location
		var generated_town: Node = level.get_node_or_null("BlockoutGeometry/TownBuilder/GeneratedTown")
		if generated_town == null or generated_town.get_child_count() < 6:
			failures.append("TownEnvironmentBuilder should generate small town districts, river bridge, and perimeter hills")
		if zone.global_position.x < 100.0:
			failures.append("Expected DeliveryZone at expanded Maple St cul-de-sac (x >= 100), got %s" % str(zone.global_position))

		# Register sofa inside delivery zone overlap list for deterministic validation test
		zone._on_body_entered(sofa)
		sofa.global_position = zone.global_position
		sofa.linear_velocity = Vector3.ZERO

		# 3. Verify sofa does NOT count as delivered while still loaded in truck
		sofa.transition_to(CargoBody.CargoState.LOADED_UNSECURED)
		zone.step_zone_validation(2.0, true)
		if zone.is_delivery_completed or mission_mgr.is_completed:
			failures.append("Sofa must not count as delivered while in LOADED_UNSECURED truck state")

		# 4. Verify sofa does NOT count as delivered while still CARRIED by a player
		sofa.transition_to(CargoBody.CargoState.FREE)
		p1.global_position = sofa.global_position + Vector3(-1.1, 0.0, 0.5)
		sofa.interact_with_handle(0, p1)
		zone.step_zone_validation(2.0, true)
		if zone.is_delivery_completed or mission_mgr.is_completed:
			failures.append("Sofa must not count as delivered while still CARRIED by a player")

		# 5. Release sofa in zone -> FREE & stationary -> settles for required_settle_seconds -> DELIVERED!
		p1.release_held_cargo()
		sofa.linear_velocity = Vector3.ZERO
		mission_mgr.elapsed_seconds = 180.0
		sofa.cargo_damage.current_durability = 88.0

		mission_mgr.step_mission(0.6, true)
		if zone.is_delivery_completed or mission_mgr.is_completed:
			failures.append("DeliveryZone should wait full required_settle_seconds (1.2s) before finalizing")

		mission_mgr.step_mission(0.7, true)
		if not zone.is_delivery_completed or not mission_mgr.is_completed:
			failures.append("DeliveryZone and MissionManager should finalize delivery after sofa settles for 1.2s")
		if sofa.current_state != CargoBody.CargoState.DELIVERED:
			failures.append("Sofa should transition to DELIVERED state upon completion")
		if not results_ui.is_showing():
			failures.append("ResultsScreen should be visible after mission completion")
		if int(mission_mgr.last_score_summary.get("final_score", -1)) != 88:
			failures.append("Expected final score 88 for 88% durability within target time, got %s" % str(mission_mgr.last_score_summary))

		# 6. Verify full mission restart resets sofa, zone, mission manager, and hides results screen
		level.restart_full_mission()
		if mission_mgr.is_completed or zone.is_delivery_completed:
			failures.append("restart_full_mission should clear completion flags")
		if sofa.current_state != CargoBody.CargoState.FREE or not is_equal_approx(sofa.cargo_damage.current_durability, 100.0):
			failures.append("restart_full_mission should reset sofa to FREE state and 100 durability")
		if results_ui.is_showing():
			failures.append("restart_full_mission should hide ResultsScreen")

	level.free()

	if not failures.is_empty():
		_fail_and_quit(failures)
		return

	print("[PASS] Milestone 06 smoke test succeeded.")
	quit(0)


func _fail_and_quit(failures: Array[String]) -> void:
	for failure: String in failures:
		printerr("[FAIL] %s" % failure)
	quit(1)
