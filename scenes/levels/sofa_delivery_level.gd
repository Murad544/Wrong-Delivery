class_name SofaDeliveryLevel
extends Node3D

@export_file("*.tscn") var alternate_scene_path: String = "res://scenes/levels/physics_playground.tscn"

var _cargo_items: Array[CargoBody] = []

@onready var player: PlayerController = $Player
@onready var game_hud: GameHUD = $GameHUD
@onready var spawn_point: Marker3D = $SpawnPoint


func _ready() -> void:
	if player != null and spawn_point != null:
		player.global_transform = spawn_point.global_transform
	if game_hud != null and player != null:
		game_hud.bind_to_player(player)

	_register_level_cargo()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.physical_keycode == KEY_F4:
				reset_all_cargo()
				get_viewport().set_input_as_handled()
			elif key_event.physical_keycode == KEY_F5 and not alternate_scene_path.is_empty():
				get_tree().change_scene_to_file(alternate_scene_path)
				get_viewport().set_input_as_handled()


func reset_all_cargo() -> void:
	for cargo: CargoBody in _cargo_items:
		if cargo != null and is_instance_valid(cargo):
			cargo.reset_to_spawn()
			if cargo.cargo_damage != null:
				cargo.cargo_damage.reset_durability()
	if game_hud != null:
		game_hud.show_feedback_message("All cargo reset to checkpoint", false)


func get_cargo_items() -> Array[CargoBody]:
	return _cargo_items


func _register_level_cargo() -> void:
	_cargo_items.clear()
	var cargo_root: Node = get_node_or_null("CargoItems")
	if cargo_root == null:
		return
	for child: Node in cargo_root.get_children():
		if child is CargoBody:
			var cargo: CargoBody = child as CargoBody
			_cargo_items.append(cargo)
			if game_hud != null:
				game_hud.register_cargo(cargo)
