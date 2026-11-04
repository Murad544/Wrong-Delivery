class_name LobbyScene
extends Control

@export_file("*.tscn") var game_level_scene: String = "res://scenes/levels/sofa_delivery.tscn"

@onready var ip_input: LineEdit = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/IpInput
@onready var port_input: LineEdit = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PortInput
@onready var status_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var host_btn: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HostButton
@onready var join_btn: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/JoinButton
@onready var solo_btn: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SoloButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	solo_btn.pressed.connect(_on_solo_pressed)


func _on_host_pressed() -> void:
	var port: int = int(port_input.text) if port_input != null else 7777
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, 1)
	if err != OK:
		status_label.text = "Failed to host on port %d (Error %d)" % [port, int(err)]
		return
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(game_level_scene)


func _on_join_pressed() -> void:
	var ip: String = ip_input.text.strip_edges() if ip_input != null else "127.0.0.1"
	var port: int = int(port_input.text) if port_input != null else 7777
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		status_label.text = "Failed to connect to %s:%d" % [ip, port]
		return
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(game_level_scene)


func _on_solo_pressed() -> void:
	get_tree().change_scene_to_file(game_level_scene)
