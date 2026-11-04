class_name ResultsScreen
extends CanvasLayer

signal restart_requested()

@onready var root_panel: Control = $OverlayBackground
@onready var title_label: Label = $OverlayBackground/CenterContainer/CardPanel/Margin/VBox/TitleLabel
@onready var rating_label: Label = $OverlayBackground/CenterContainer/CardPanel/Margin/VBox/RatingLabel
@onready var breakdown_label: Label = $OverlayBackground/CenterContainer/CardPanel/Margin/VBox/BreakdownLabel
@onready var score_label: Label = $OverlayBackground/CenterContainer/CardPanel/Margin/VBox/ScoreLabel
@onready var restart_button: Button = $OverlayBackground/CenterContainer/CardPanel/Margin/VBox/RestartButton


func _ready() -> void:
	hide_results()
	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if root_panel == null or not root_panel.visible:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_on_restart_pressed()
				get_viewport().set_input_as_handled()


func show_results(summary: Dictionary) -> void:
	if root_panel == null:
		return
	root_panel.visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var contract: String = String(summary.get("contract_name", "Contract Complete"))
	var rating: String = String(summary.get("rating", "Delivered"))
	var elapsed: float = float(summary.get("elapsed_seconds", 0.0))
	var target_t: float = float(summary.get("target_time_seconds", 300.0))
	var dur_rem: float = float(summary.get("durability_remaining", 100.0))
	var dur_max: float = float(summary.get("max_durability", 100.0))
	var dmg_pen: int = int(summary.get("damage_penalty", 0))
	var ovt_pen: int = int(summary.get("overtime_penalty", 0))
	var mst_pen: int = int(summary.get("major_mistake_penalty", 0))
	var mst_cnt: int = int(summary.get("major_mistakes_count", 0))
	var bonus_pts: int = int(summary.get("bonus_points", 0))
	var final_sc: int = int(summary.get("final_score", 100))

	if title_label != null:
		title_label.text = "DELIVERY COMPLETE — %s" % contract
	if rating_label != null:
		rating_label.text = "Rating: %s" % rating
	if breakdown_label != null:
		breakdown_label.text = (
			"Elapsed Time: %s (Target: %s)\n"
			+ "Cargo Durability: %.0f / %.0f\n"
			+ "----------------------------------------\n"
			+ "Base Delivery Score:       100\n"
			+ "Damage Penalty:            -%d\n"
			+ "Overtime Penalty:          -%d\n"
			+ "Major Mistakes (%d):       -%d\n"
			+ "Style & Parcel Bonus:      +%d"
		) % [
			ScoringSystem.format_time_mm_ss(elapsed),
			ScoringSystem.format_time_mm_ss(target_t),
			dur_rem,
			dur_max,
			dmg_pen,
			ovt_pen,
			mst_cnt,
			mst_pen,
			bonus_pts,
		]
	if score_label != null:
		score_label.text = "FINAL SCORE: %d / 100" % final_sc


func hide_results() -> void:
	if root_panel != null:
		root_panel.visible = false


func is_showing() -> bool:
	return root_panel != null and root_panel.visible


func _on_restart_pressed() -> void:
	restart_requested.emit()
