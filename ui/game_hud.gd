class_name GameHUD
extends CanvasLayer

@export var feedback_display_seconds: float = 2.5
@export var show_diagnostics_by_default: bool = true

var _feedback_timer: float = 0.0
var _tracked_player: PlayerController = null
var _tracked_cargos: Array[CargoBody] = []
var _tracked_truck: TruckController = null
var _network_manager: NetworkManager = null
var _state_sync: StateSync = null
var _net_status_detail: String = "Offline (F1: Host LAN | F2: Join 127.0.0.1)"

@onready var prompt_panel: PanelContainer = $RootMargin/CenterBottom/PromptPanel
@onready var prompt_label: Label = $RootMargin/CenterBottom/PromptPanel/PromptLabel
@onready var feedback_label: Label = $RootMargin/CenterBottom/FeedbackLabel
@onready var status_label: Label = $RootMargin/TopLeftPanel/VBox/StatusLabel
@onready var net_status_label: Label = get_node_or_null("RootMargin/TopLeftPanel/VBox/NetStatusLabel") as Label
@onready var debug_panel: PanelContainer = $RootMargin/TopRightDebugPanel
@onready var debug_label: Label = $RootMargin/TopRightDebugPanel/DebugVBox/DebugStatsLabel


func _ready() -> void:
	set_interaction_prompt("", false)
	if feedback_label != null:
		feedback_label.visible = false
	if debug_panel != null:
		debug_panel.visible = show_diagnostics_by_default
	_update_net_status_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.physical_keycode == KEY_F3:
				if debug_panel != null:
					debug_panel.visible = not debug_panel.visible
				get_viewport().set_input_as_handled()
			elif key_event.physical_keycode == KEY_F1 and _network_manager != null:
				_network_manager.host_lan_game()
				get_viewport().set_input_as_handled()
			elif key_event.physical_keycode == KEY_F2 and _network_manager != null:
				_network_manager.join_lan_game("127.0.0.1")
				get_viewport().set_input_as_handled()
			elif key_event.physical_keycode == KEY_F6 and _state_sync != null:
				var sim_msg: String = _state_sync.cycle_simulated_latency()
				show_feedback_message(sim_msg, false)
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
		if not player.interaction_controller.prompt_changed.is_connected(set_interaction_prompt):
			player.interaction_controller.prompt_changed.connect(set_interaction_prompt)
		if not player.interaction_controller.interaction_feedback.is_connected(show_feedback_message):
			player.interaction_controller.interaction_feedback.connect(show_feedback_message)
	if player.player_camera != null:
		if not player.player_camera.mouse_capture_changed.is_connected(_on_mouse_capture_changed):
			player.player_camera.mouse_capture_changed.connect(_on_mouse_capture_changed)


func bind_networking(net_mgr: NetworkManager, sync_node: StateSync) -> void:
	_network_manager = net_mgr
	_state_sync = sync_node
	if _network_manager != null:
		_network_manager.session_changed.connect(
			func(_mode: String, detail: String) -> void:
				_net_status_detail = detail
				_update_net_status_label()
		)
		_network_manager.network_feedback.connect(show_feedback_message)


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


func register_truck(truck: TruckController) -> void:
	if truck == null:
		return
	_tracked_truck = truck
	if truck.cargo_bay != null:
		truck.cargo_bay.cargo_loaded.connect(
			func(c: CargoBody) -> void:
				show_feedback_message(
					"Loaded %s into truck bay (Press F at rear strap anchor to secure)" % c.get_display_name(),
					false
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
		status_label.text = "F1: Host LAN | F2: Join LAN | F3: HUD | F4: Reset | F5: Scene | F6: Latency Sim"
	else:
		status_label.text = "Mouse Released (Click or Esc to capture) | F1: Host | F2: Join"


func _update_net_status_label() -> void:
	if net_status_label != null:
		net_status_label.text = "Network: %s" % _net_status_detail


func _refresh_diagnostics_text() -> void:
	if debug_label == null:
		return

	var lines: Array[String] = []

	if _network_manager != null:
		var my_pid: int = 1
		if _network_manager.is_online():
			my_pid = multiplayer.get_unique_id()
		var sim_ms: float = _state_sync.simulated_latency_ms if _state_sync != null else 0.0
		lines.append("[Multiplayer]")
		lines.append("Mode: %s | My Peer ID: %d | Peers: %s" % [
			_network_manager.session_mode,
			my_pid,
			str(_network_manager.connected_peers)
		])
		lines.append("Sim Latency (F6): %.0f ms" % sim_ms)
		lines.append("")

	var focus_cargo: CargoBody = _select_focus_cargo()
	if focus_cargo != null:
		var dur_cur: float = focus_cargo.cargo_damage.current_durability if focus_cargo.cargo_damage != null else 0.0
		var dur_max: float = focus_cargo.cargo_damage.max_durability if focus_cargo.cargo_damage != null else 0.0
		var last_imp: float = focus_cargo.cargo_damage.last_impact_speed if focus_cargo.cargo_damage != null else 0.0
		var thresh: float = focus_cargo.cargo_damage.impact_speed_threshold if focus_cargo.cargo_damage != null else 0.0
		var force_mag: float = focus_cargo.carry_controller.last_applied_force.length() if focus_cargo.carry_controller != null else 0.0

		lines.append("[Cargo]")
		lines.append("Item: %s (%s)" % [focus_cargo.get_display_name(), CargoBody.get_state_name(focus_cargo.current_state)])
		lines.append("Durability: %.0f / %.0f" % [dur_cur, dur_max])
		lines.append("Carriers: %d / %d | Force: %.0f N" % [focus_cargo.get_carrier_count(), focus_cargo.get_required_carriers(), force_mag])
		lines.append("Last Impact: %.2f m/s (thresh %.1f)" % [last_imp, thresh])

	if _tracked_truck != null and is_instance_valid(_tracked_truck):
		var spd: float = _tracked_truck.forward_speed
		var kmh: float = absf(spd) * 3.6
		var seat_str: String = "On Foot"
		if _tracked_player != null and _tracked_player.is_seated_in_vehicle():
			seat_str = _tracked_player.seated_role
		var bay: CargoBay = _tracked_truck.cargo_bay
		var bay_count: int = bay.get_loaded_cargos().size() if bay != null else 0
		var stab_pct: float = (bay.current_stability_ratio * 100.0) if bay != null else 100.0
		var bay_warn: String = bay.current_warning_text if bay != null else "EMPTY"

		lines.append("")
		lines.append("[Delivery Truck]")
		lines.append("Role: %s | Speed: %.1f m/s (%.0f km/h)" % [seat_str, spd, kmh])
		lines.append("Lat Accel: %.2f m/s² | Handbrake: %s" % [
			_tracked_truck.lateral_acceleration,
			"ON" if _tracked_truck.is_handbrake_active else "OFF"
		])
		lines.append("Cargo Bay: %d item(s) | Stability: %.0f%%" % [bay_count, stab_pct])
		lines.append("Bay Status: %s" % bay_warn)

	debug_label.text = "\n".join(lines)


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
