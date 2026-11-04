class_name SofaDeliveryLevel
extends Node3D

@export_file("*.tscn") var alternate_scene_path: String = "res://scenes/levels/physics_playground.tscn"

var _cargo_items: Array[CargoBody] = []

var network_manager: NetworkManager = null
var player_spawner: PlayerSpawner = null
var cargo_manager: CargoManager = null
var state_sync: StateSync = null

@onready var player: PlayerController = $Player
@onready var game_hud: GameHUD = $GameHUD
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var delivery_truck: TruckController = get_node_or_null("DeliveryTruck") as TruckController


func _enter_tree() -> void:
	_ensure_networking_nodes()


func _ready() -> void:
	var spawn_tf: Transform3D = spawn_point.global_transform if spawn_point != null else Transform3D.IDENTITY
	if player != null and spawn_point != null:
		player.global_transform = spawn_tf

	_register_level_cargo()

	if cargo_manager != null:
		cargo_manager.register_cargos(_cargo_items)

	if player_spawner != null:
		player_spawner.local_player_changed.connect(_on_local_player_changed)
		player_spawner.setup(self, player, spawn_tf, delivery_truck)

	if state_sync != null:
		state_sync.setup(network_manager, player_spawner, cargo_manager, delivery_truck, game_hud)

	if network_manager != null:
		network_manager.peer_joined.connect(_on_network_peer_joined)
		network_manager.peer_left.connect(_on_network_peer_left)

	if game_hud != null:
		if player != null:
			game_hud.bind_to_player(player)
		if delivery_truck != null:
			game_hud.register_truck(delivery_truck)
		game_hud.bind_networking(network_manager, state_sync)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			var code: Key = key_event.physical_keycode
			if code == KEY_4 or code == KEY_F4:
				if network_manager == null or network_manager.is_host_or_offline():
					reset_all_cargo()
				elif game_hud != null:
					game_hud.show_feedback_message("Only the Host can reset the mission checkpoint", true)
				get_viewport().set_input_as_handled()
			elif (code == KEY_5 or code == KEY_F5) and not alternate_scene_path.is_empty():
				if network_manager != null and network_manager.is_online():
					network_manager.disconnect_session(false)
				get_tree().change_scene_to_file(alternate_scene_path)
				get_viewport().set_input_as_handled()


func reset_all_cargo() -> void:
	if delivery_truck != null and is_instance_valid(delivery_truck):
		delivery_truck.reset_to_spawn()

	for cargo: CargoBody in _cargo_items:
		if cargo != null and is_instance_valid(cargo):
			cargo.reset_to_spawn()
			if cargo.cargo_damage != null:
				cargo.cargo_damage.reset_durability()
	if game_hud != null:
		game_hud.show_feedback_message("Truck and all cargo reset to checkpoint", false)


func get_cargo_items() -> Array[CargoBody]:
	return _cargo_items


func _ensure_networking_nodes() -> void:
	network_manager = get_node_or_null("NetworkManager") as NetworkManager
	if network_manager == null:
		network_manager = NetworkManager.new()
		network_manager.name = "NetworkManager"
		add_child(network_manager)

	player_spawner = get_node_or_null("PlayerSpawner") as PlayerSpawner
	if player_spawner == null:
		player_spawner = PlayerSpawner.new()
		player_spawner.name = "PlayerSpawner"
		add_child(player_spawner)

	cargo_manager = get_node_or_null("CargoManager") as CargoManager
	if cargo_manager == null:
		cargo_manager = CargoManager.new()
		cargo_manager.name = "CargoManager"
		add_child(cargo_manager)

	state_sync = get_node_or_null("StateSync") as StateSync
	if state_sync == null:
		state_sync = StateSync.new()
		state_sync.name = "StateSync"
		add_child(state_sync)


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


func _on_network_peer_joined(peer_id: int) -> void:
	if player_spawner != null:
		player_spawner.ensure_player_for_peer(peer_id)
		player_spawner.refresh_all_roles_for_current_session()


func _on_network_peer_left(peer_id: int) -> void:
	if player_spawner != null:
		player_spawner.remove_player_for_peer(peer_id)
		player_spawner.refresh_all_roles_for_current_session()


func _on_local_player_changed(local_player: PlayerController) -> void:
	if game_hud != null and local_player != null:
		game_hud.bind_to_player(local_player)
