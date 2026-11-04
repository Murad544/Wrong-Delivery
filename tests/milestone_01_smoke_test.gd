extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []

	var level_packed: PackedScene = load("res://scenes/levels/sofa_delivery.tscn") as PackedScene
	if level_packed == null:
		_fail_and_quit(["Failed to load res://scenes/levels/sofa_delivery.tscn"])
		return

	var level_instance: Node = level_packed.instantiate()
	root.add_child(level_instance)
	await process_frame
	await physics_frame

	var player: PlayerController = level_instance.get_node_or_null("Player") as PlayerController
	if player == null:
		failures.append("Player node missing or not PlayerController")
	else:
		PlayerController._ensure_input_actions()
		var required_actions: Array[String] = [
			"move_forward",
			"move_back",
			"move_left",
			"move_right",
			"sprint",
			"jump",
			"interact",
			"rotate_left",
			"rotate_right",
			"secure_cargo",
			"handbrake",
			"pause",
		]
		for action_name: String in required_actions:
			if not InputMap.has_action(action_name):
				failures.append("Missing InputMap action: %s" % action_name)

		if not is_equal_approx(player.walk_speed, 5.0):
			failures.append("Expected walk_speed 5.0, got %.2f" % player.walk_speed)
		if not is_equal_approx(player.sprint_speed, 7.0):
			failures.append("Expected sprint_speed 7.0, got %.2f" % player.sprint_speed)
		if not is_equal_approx(player.carry_speed, 2.5):
			failures.append("Expected carry_speed 2.5, got %.2f" % player.carry_speed)
		if not is_equal_approx(player.jump_velocity, 4.5):
			failures.append("Expected jump_velocity 4.5, got %.2f" % player.jump_velocity)

		player.is_carrying_heavy_cargo = true
		if player.can_jump():
			failures.append("Player should not be allowed to jump while carrying heavy cargo")
		if not is_equal_approx(player.get_target_move_speed(true), player.carry_speed):
			failures.append("Sprint should not bypass carry_speed while carrying heavy cargo")
		player.is_carrying_heavy_cargo = false

	var manifest: InteractableTarget = level_instance.get_node_or_null("Interactables/ManifestClipboard") as InteractableTarget
	if manifest == null:
		failures.append("ManifestClipboard interactable missing from level")
	else:
		var near_check: Dictionary = manifest.can_interact_from(manifest.global_position + Vector3(0, 0, -1.0))
		if not bool(near_check.get("allowed", false)):
			failures.append("ManifestClipboard should allow interaction within reach")
		var far_check: Dictionary = manifest.can_interact_from(manifest.global_position + Vector3(0, 0, -10.0))
		if bool(far_check.get("allowed", true)):
			failures.append("ManifestClipboard should reject interaction beyond max_interaction_distance")

	var terminal: InteractableTarget = level_instance.get_node_or_null("Interactables/DeliveryTerminal") as InteractableTarget
	if terminal == null:
		failures.append("DeliveryTerminal interactable missing from level")
	else:
		var disabled_check: Dictionary = terminal.can_interact_from(terminal.global_position)
		if bool(disabled_check.get("allowed", true)):
			failures.append("Disabled DeliveryTerminal should reject interaction")

	level_instance.free()

	if not failures.is_empty():
		_fail_and_quit(failures)
		return

	print("[PASS] Milestone 01 smoke test succeeded.")
	quit(0)


func _fail_and_quit(failures: Array[String]) -> void:
	for failure: String in failures:
		printerr("[FAIL] %s" % failure)
	quit(1)
