class_name GameHUD
extends CanvasLayer

@export var feedback_display_seconds: float = 2.5
@export var show_diagnostics_by_default: bool = true

var _feedback_timer: float = 0.0
var _tracked_player: PlayerController = null
var _tracked_cargos: Array[CargoBody] = []

@onready var prompt_panel: PanelContainer = $RootMargin/CenterBottom/PromptPanel
@onready var prompt_label: Label = $RootMargin/CenterBottom/PromptPanel/PromptLabel
@onready var feedback_label: Label = $RootMargin/CenterBottom/FeedbackLabel
@onready var status_label: Label = $RootMargin/TopLeftPanel/VBox/StatusLabel
@onready var debug_panel: PanelContainer = $RootMargin/TopRightDebugPanel
@onready var debug_label: Label = $RootMargin/TopRightDebugPanel/DebugVBox/DebugStatsLabel


func _ready() -> void:
	set_interaction_prompt("", false)
	if feedback_label != null:
		feedback_label.visible = false
	if debug_panel != null:
		debug_panel.visible = show_diagnostics_by_default


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_F3:
			if debug_panel != null:
				debug_panel.visible = not debug_panel.visible
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0 and feedback_label != null:
			feedback_label.visible = false

	if debug_panel != null and debug_panel.visible:
		_refresh_diagnostics_text()


func bind_to_player(player: PlayerController) -> void:
	_tracked_player = player
	if player == null:
		return
	if player.interaction_controller != null:
		player.interaction_controller.prompt_changed.connect(set_interaction_prompt)
		player.interaction_controller.interaction_feedback.connect(show_feedback_message)
	if player.player_camera != null:
		player.player_camera.mouse_capture_changed.connect(_on_mouse_capture_changed)


func register_cargo(cargo: CargoBody) -> void:
	if cargo == null or _tracked_cargos.has(cargo):
		return
	_tracked_cargos.append(cargo)
	cargo.cargo_damaged.connect(
		func(dmg: float, cur: float, max_d: float, speed: float) -> void:
			show_feedback_message(
				"%s took %.0f dmg (%.1f m/s impact) — Durability: %.0f/%.0f" % [
					cargo.get_display_name(),
					dmg,
					speed,
					cur,
					max_d,
				],
				true
			)
	)


func set_interaction_prompt(prompt_text: String, is_valid: bool) -> void:
	if prompt_panel == null or prompt_label == null:
		return
	if prompt_text.is_empty():
		prompt_panel.visible = false
		prompt_label.text = ""
		return

	prompt_panel.visible = true
	prompt_label.text = prompt_text
	if is_valid:
		prompt_label.modulate = Color(1.0, 0.96, 0.78, 1.0)
	else:
		prompt_label.modulate = Color(1.0, 0.55, 0.55, 1.0)


func show_feedback_message(message: String, is_error: bool = false) -> void:
	if feedback_label == null:
		return
	feedback_label.text = message
	feedback_label.visible = not message.is_empty()
	feedback_label.modulate = Color(1.0, 0.5, 0.5, 1.0) if is_error else Color(0.65, 1.0, 0.75, 1.0)
	_feedback_timer = feedback_display_seconds


func _on_mouse_capture_changed(is_captured: bool) -> void:
	if status_label == null:
		return
	if is_captured:
		status_label.text = "Mouse: Captured (Esc to release) | F3: Debug | F4: Reset Cargo"
	else:
		status_label.text = "Mouse: Released (Click or Esc to capture)"


func _refresh_diagnostics_text() -> void:
	if debug_label == null:
		return

	var focus_cargo: CargoBody = _select_focus_cargo()
	if focus_cargo == null:
		debug_label.text = "No cargo registered in scene."
		return

	var dur_cur: float = focus_cargo.cargo_damage.current_durability if focus_cargo.cargo_damage != null else 0.0
	var dur_max: float = focus_cargo.cargo_damage.max_durability if focus_cargo.cargo_damage != null else 0.0
	var last_imp: float = focus_cargo.cargo_damage.last_impact_speed if focus_cargo.cargo_damage != null else 0.0
	var thresh: float = focus_cargo.cargo_damage.impact_speed_threshold if focus_cargo.cargo_damage != null else 0.0
	var force_mag: float = focus_cargo.carry_controller.last_applied_force.length() if focus_cargo.carry_controller != null else 0.0

	debug_label.text = (
		"Item: %s\n"
		+ "State: %s\n"
		+ "Durability: %.0f / %.0f\n"
		+ "Carriers: %d / %d\n"
		+ "Linear Speed: %.2f m/s\n"
		+ "Carry Force: %.1f N\n"
		+ "Last Impact: %.2f m/s (thresh %.1f)"
	) % [
		focus_cargo.get_display_name(),
		CargoBody.get_state_name(focus_cargo.current_state),
		dur_cur,
		dur_max,
		focus_cargo.get_carrier_count(),
		focus_cargo.get_required_carriers(),
		focus_cargo.linear_velocity.length(),
		force_mag,
		last_imp,
		thresh,
	]


func _select_focus_cargo() -> CargoBody:
	if _tracked_player != null and _tracked_player.is_holding_any_cargo():
		return _tracked_player.held_cargo

	var best: CargoBody = null
	var best_dist: float = INF
	var origin: Vector3 = _tracked_player.global_position if _tracked_player != null else Vector3.ZERO
	for cargo: CargoBody in _tracked_cargos:
		if cargo == null or not is_instance_valid(cargo):
			continue
		var d: float = cargo.global_position.distance_to(origin)
		if d < best_dist:
			best_dist = d
			best = cargo
	return best
