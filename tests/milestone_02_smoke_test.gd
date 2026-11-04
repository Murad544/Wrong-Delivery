extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []

	var playground_packed: PackedScene = load("res://scenes/levels/physics_playground.tscn") as PackedScene
	if playground_packed == null:
		_fail_and_quit(["Failed to load res://scenes/levels/physics_playground.tscn"])
		return

	var playground: Node = playground_packed.instantiate()
	root.add_child(playground)
	await process_frame
	await physics_frame

	var player: PlayerController = playground.get_node_or_null("Player") as PlayerController
	var crate: CargoBody = playground.get_node_or_null("CargoItems/StandardCrate") as CargoBody
	var sofa: CargoBody = playground.get_node_or_null("CargoItems/PlaygroundSofa") as CargoBody

	if player == null:
		failures.append("Player missing in physics_playground.tscn")
	if crate == null:
		failures.append("StandardCrate missing in physics_playground.tscn")
	if sofa == null:
		failures.append("PlaygroundSofa missing in physics_playground.tscn")

	if crate != null and sofa != null and player != null:
		# 1. Verify CargoData tuning
		if crate.get_required_carriers() != 1:
			failures.append("Expected crate required_carriers == 1")
		if sofa.get_required_carriers() != 2:
			failures.append("Expected sofa required_carriers == 2")
		if not is_equal_approx(sofa.mass, 30.0):
			failures.append("Expected sofa mass 30.0 kg, got %.1f" % sofa.mass)

		# 2. Verify State Machine transitions
		if crate.current_state != CargoBody.CargoState.FREE:
			failures.append("Crate should start in FREE state")
		if crate.can_transition_to(CargoBody.CargoState.SECURED):
			failures.append("FREE -> SECURED direct transition should be disallowed")
		if not crate.transition_to(CargoBody.CargoState.LOADED_UNSECURED):
			failures.append("FREE -> LOADED_UNSECURED should succeed")
		if not crate.transition_to(CargoBody.CargoState.SECURED):
			failures.append("LOADED_UNSECURED -> SECURED should succeed")
		if not crate.transition_to(CargoBody.CargoState.LOADED_UNSECURED):
			failures.append("SECURED -> LOADED_UNSECURED should succeed")
		crate.reset_to_spawn()

		# 3. Verify Damage threshold & cooldown
		var dmg_node: CargoDamage = crate.cargo_damage
		dmg_node.reset_durability()
		var tiny_dmg: float = dmg_node.process_impact(1.2, true)
		if tiny_dmg > 0.0 or not is_equal_approx(dmg_node.current_durability, 100.0):
			failures.append("Sub-threshold impact (1.2 m/s) should cause 0 damage")

		var hard_dmg: float = dmg_node.process_impact(6.0, true)
		if hard_dmg <= 0.0 or dmg_node.current_durability >= 100.0:
			failures.append("Above-threshold impact (6.0 m/s) should reduce durability")

		var cooldown_dmg: float = dmg_node.process_impact(7.0, true)
		if cooldown_dmg > 0.0:
			failures.append("Immediate impact during cooldown should be ignored")
		dmg_node.reset_durability()

		# 4. Verify Grab / Carry / Single-carrier vs 2-carrier rules
		var grab_msg: String = crate.interact_with_handle(0, player)
		if crate.current_state != CargoBody.CargoState.CARRIED:
			failures.append("Crate should enter CARRIED state when grabbed (got msg: %s)" % grab_msg)
		if not player.is_holding_any_cargo():
			failures.append("Player should report holding cargo after grabbing crate")

		# Player should not be able to grab sofa while holding crate
		var second_grab_msg: String = sofa.interact_with_handle(0, player)
		if sofa.get_carrier_count() != 0:
			failures.append("Player should not be able to grab sofa while already holding crate (%s)" % second_grab_msg)

		# Release crate and test grabbing 1 handle on 2-carrier sofa
		player.release_held_cargo()
		if crate.current_state != CargoBody.CargoState.FREE or player.is_holding_any_cargo():
			failures.append("Releasing crate should return crate to FREE and clear player held state")

		sofa.interact_with_handle(0, player)
		if sofa.get_carrier_count() != 1 or sofa.carry_controller.is_fully_staffed():
			failures.append("Single carrier on 2-person sofa should not be marked fully staffed")
		player.release_held_cargo()

	playground.free()

	if not failures.is_empty():
		_fail_and_quit(failures)
		return

	print("[PASS] Milestone 02 smoke test succeeded.")
	quit(0)


func _fail_and_quit(failures: Array[String]) -> void:
	for failure: String in failures:
		printerr("[FAIL] %s" % failure)
	quit(1)
