class_name PlayerSpawner
extends Node

signal local_player_changed(player: PlayerController)

@export var player_scene: PackedScene = preload("res://player/player.tscn")
@export var partner_spawn_offset: Vector3 = Vector3(1.6, 0.0, 0.0)

var level_root: Node3D = null
var base_spawn_transform: Transform3D = Transform3D.IDENTITY
var delivery_truck: TruckController = null
var players_by_peer: Dictionary = {}


func setup(
	owner_level: Node3D,
	host_player: PlayerController,
	spawn_tf: Transform3D,
	truck: TruckController
) -> void:
	level_root = owner_level
	base_spawn_transform = spawn_tf
	delivery_truck = truck
	players_by_peer.clear()

	if host_player != null:
		players_by_peer[1] = host_player
		host_player.configure_network_role(1, true)


func ensure_player_for_peer(peer_id: int) -> PlayerController:
	if players_by_peer.has(peer_id):
		var existing: PlayerController = players_by_peer[peer_id] as PlayerController
		if existing != null and is_instance_valid(existing):
			_refresh_local_role(existing)
			return existing

	if level_root == null or player_scene == null:
		return null

	var instance: PlayerController = player_scene.instantiate() as PlayerController
	if instance == null:
		return null

	instance.name = "Player_Peer_%d" % peer_id
	var spawn_pos: Vector3 = base_spawn_transform.origin + partner_spawn_offset
	instance.global_transform = Transform3D(Basis.IDENTITY, spawn_pos)
	level_root.add_child(instance)
	players_by_peer[peer_id] = instance
	_refresh_local_role(instance)
	return instance


func remove_player_for_peer(peer_id: int) -> void:
	if not players_by_peer.has(peer_id):
		return

	var player: PlayerController = players_by_peer[peer_id] as PlayerController
	if player != null and is_instance_valid(player):
		# Clean up held cargo handles on disconnect
		if player.is_holding_any_cargo():
			player.release_held_cargo()
		# Clean up vehicle seat ownership on disconnect
		if delivery_truck != null and is_instance_valid(delivery_truck):
			delivery_truck.force_remove_occupant(player)
		if peer_id != 1:
			player.queue_free()

	if peer_id != 1:
		players_by_peer.erase(peer_id)


func refresh_all_roles_for_current_session() -> void:
	var my_peer_id: int = 1
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			my_peer_id = multiplayer.get_unique_id()

	for pid_val: Variant in players_by_peer.keys():
		var pid: int = int(pid_val)
		var player: PlayerController = players_by_peer[pid] as PlayerController
		if player != null and is_instance_valid(player):
			var is_local: bool = (pid == my_peer_id)
			player.configure_network_role(pid, is_local)
			if is_local:
				local_player_changed.emit(player)


func get_player(peer_id: int) -> PlayerController:
	return players_by_peer.get(peer_id, null) as PlayerController


func get_local_player() -> PlayerController:
	var my_peer_id: int = 1
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			my_peer_id = multiplayer.get_unique_id()
	return get_player(my_peer_id)


func reset_all_players_to_spawn() -> void:
	var idx: int = 0
	for pid_val: Variant in players_by_peer.keys():
		var player: PlayerController = players_by_peer[pid_val] as PlayerController
		if player != null and is_instance_valid(player):
			if player.is_holding_any_cargo():
				player.release_held_cargo()
			var offset: Vector3 = Vector3.ZERO if idx == 0 else partner_spawn_offset * float(idx)
			player.global_transform = Transform3D(Basis.IDENTITY, base_spawn_transform.origin + offset)
			player.velocity = Vector3.ZERO
			idx += 1


func _refresh_local_role(player: PlayerController) -> void:
	if player == null:
		return
	var my_peer_id: int = 1
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			my_peer_id = multiplayer.get_unique_id()
	var is_local: bool = (player.peer_id == my_peer_id)
	player.configure_network_role(player.peer_id, is_local)
	if is_local:
		local_player_changed.emit(player)
