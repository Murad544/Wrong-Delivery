class_name NetworkManager
extends Node

signal session_changed(mode_name: String, status_detail: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal network_feedback(message: String, is_error: bool)

@export var default_port: int = 7777
@export_range(2, 4, 1) var max_players: int = 2

var session_mode: String = "Offline"
var connected_peers: Array[int] = [1]


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_parse_cli_network_args()


func host_lan_game(port: int = -1) -> Dictionary:
	disconnect_session(false)
	var use_port: int = port if port > 0 else default_port
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(use_port, max_players - 1)
	if err != OK:
		var err_msg: String = "Failed to host on UDP port %d (Error %d)" % [use_port, int(err)]
		network_feedback.emit(err_msg, true)
		return {"success": false, "message": err_msg}

	multiplayer.multiplayer_peer = peer
	session_mode = "Host"
	connected_peers = [1]
	var status: String = "Hosting LAN on port %d (1/%d players)" % [use_port, max_players]
	session_changed.emit(session_mode, status)
	network_feedback.emit(status, false)
	return {"success": true, "message": status}


func join_lan_game(address: String = "127.0.0.1", port: int = -1) -> Dictionary:
	disconnect_session(false)
	var clean_addr: String = address.strip_edges()
	if clean_addr.is_empty():
		clean_addr = "127.0.0.1"
	var use_port: int = port if port > 0 else default_port

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(clean_addr, use_port)
	if err != OK:
		var err_msg: String = "Failed to connect to %s:%d (Error %d)" % [clean_addr, use_port, int(err)]
		network_feedback.emit(err_msg, true)
		return {"success": false, "message": err_msg}

	multiplayer.multiplayer_peer = peer
	session_mode = "Connecting"
	connected_peers = []
	var status: String = "Connecting to %s:%d..." % [clean_addr, use_port]
	session_changed.emit(session_mode, status)
	network_feedback.emit(status, false)
	return {"success": true, "message": status}


func disconnect_session(emit_notice: bool = true) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	var previous_peers: Array[int] = connected_peers.duplicate()
	for pid: int in previous_peers:
		if pid != 1:
			peer_left.emit(pid)

	session_mode = "Offline"
	connected_peers = [1]
	session_changed.emit(session_mode, "Single-Player / Offline (Press F2 for LAN Co-op)")
	if emit_notice:
		network_feedback.emit("Disconnected from LAN session", false)


func is_online() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host_or_offline() -> bool:
	if not is_online():
		return true
	return multiplayer.is_server()


func _on_peer_connected(id: int) -> void:
	if not connected_peers.has(id):
		connected_peers.append(id)
	peer_joined.emit(id)
	if multiplayer.is_server():
		var status: String = "Hosting LAN (%d/%d players) — Peer %d connected" % [connected_peers.size(), max_players, id]
		session_changed.emit("Host", status)
		network_feedback.emit("Player (Peer %d) joined the game!" % id, false)


func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	peer_left.emit(id)
	if multiplayer.is_server():
		var status: String = "Hosting LAN (%d/%d players) — Peer %d left" % [connected_peers.size(), max_players, id]
		session_changed.emit("Host", status)
		network_feedback.emit("Player (Peer %d) disconnected" % id, true)


func _on_connected_to_server() -> void:
	var my_id: int = multiplayer.get_unique_id()
	session_mode = "Client"
	connected_peers = [1, my_id]
	var status: String = "Connected as Client (Peer %d)" % my_id
	session_changed.emit(session_mode, status)
	network_feedback.emit(status, false)
	peer_joined.emit(my_id)


func _on_connection_failed() -> void:
	disconnect_session(false)
	session_changed.emit("Offline", "Connection failed (Offline mode)")
	network_feedback.emit("Could not connect to LAN host", true)


func _on_server_disconnected() -> void:
	disconnect_session(false)
	session_changed.emit("Offline", "Host disconnected (Returned to Offline mode)")
	network_feedback.emit("Host closed the LAN session", true)


func _parse_cli_network_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	var port: int = default_port
	var ip: String = "127.0.0.1"
	var want_host: bool = false
	var want_join: bool = false

	for arg: String in args:
		if arg == "--host":
			want_host = true
		elif arg == "--join":
			want_join = true
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--ip="):
			ip = arg.trim_prefix("--ip=")

	if want_host:
		call_deferred("host_lan_game", port)
	elif want_join:
		call_deferred("join_lan_game", ip, port)
