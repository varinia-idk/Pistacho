extends Node
signal changed
signal map_received(map: Dictionary)
signal state_received(state: Dictionary)
signal sound_requested(kind: String)
const Simulation = preload("res://scripts/core/match_simulation.gd")
const PROTOCOL := 1
const PORT := 24567
var roster: Array[Dictionary] = []
var status: String = "menu"
var message: String = ""
var mode: String = "maze"
var practice: bool = false
var simulation: Node2D
var current_map: Dictionary = {}
var current_state: Dictionary = {}
var pending_acks: Dictionary = {}
var barriers_started: int = 0
var input_clock: float = 0.0
var snapshot_clock: float = 0.0
var sequence: int = 0
var received_sequence: int = -1
var checkpoint_needed: bool = false
var snapshots_received: int = 0
var player_name: String = "Jugador"
var connect_deadline: int = 0
var tilt: Node

func _ready() -> void:
	# All traffic is client-to-host; peer-to-peer relay is unnecessary.
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): leave("No se pudo conectar con la sala."))
	multiplayer.server_disconnected.connect(func(): leave("El anfitrión cerró la sala."))

func local_id() -> int:
	return multiplayer.get_unique_id()

func is_host() -> bool:
	return practice or multiplayer.is_server()

func host(name_value: String, solo: bool = false, port: int = PORT) -> Error:
	leave()
	if port < 1 or port > 65535:
		message = "Introduce un puerto entre 1 y 65535."
		changed.emit()
		return ERR_INVALID_PARAMETER
	player_name = name_value.strip_edges().left(18)
	practice = solo
	if not solo:
		var peer := ENetMultiplayerPeer.new()
		var error := peer.create_server(port, 3)
		if error != OK:
			message = "No se pudo abrir la sala (puerto ocupado)."
			changed.emit()
			return error
		multiplayer.multiplayer_peer = peer
	roster = [{"id": 1, "slot": 0, "name": player_name if not player_name.is_empty() else "Jugador 1", "ready": solo}]
	status = "lobby"
	changed.emit()
	return OK

func join(address: String, name_value: String, port: int = PORT) -> Error:
	leave()
	if not address.is_valid_ip_address() or port < 1 or port > 65535:
		message = "Introduce una dirección IP y un puerto válidos."
		changed.emit()
		return ERR_INVALID_PARAMETER
	player_name = name_value.strip_edges().left(18)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		message = "No se pudo iniciar la conexión."
		changed.emit()
		return error
	multiplayer.multiplayer_peer = peer
	status = "connecting"
	connect_deadline = Time.get_ticks_msec() + 8000
	changed.emit()
	return OK

func leave(reason: String = "") -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_simulation()
	roster.clear()
	current_map = {}
	current_state = {}
	pending_acks.clear()
	practice = false
	status = "menu"
	message = reason
	changed.emit()

func _clear_simulation() -> void:
	if is_instance_valid(simulation):
		remove_child(simulation)
		simulation.queue_free()
	simulation = null

func local_addresses() -> String:
	var addresses: PackedStringArray = []
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127.") and not address.begins_with("169.254."):
			addresses.append(address)
	return ", ".join(addresses) if not addresses.is_empty() else "Sin conexión Wi-Fi"

func _connected() -> void:
	_register.rpc_id(1, PROTOCOL, player_name)

func _peer_connected(_id: int) -> void:
	pass # A peer joins the roster only after the protocol handshake.

@rpc("any_peer", "call_remote", "reliable", 0)
func _register(version: int, name_value: String) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if status != "lobby" or roster.size() >= 4 or version != PROTOCOL:
		_rejected.rpc_id(sender, "Sala llena, partida en curso o versión incompatible.")
		return
	for entry in roster:
		if entry.id == sender:
			return
	var slot := 0
	while roster.any(func(entry: Dictionary) -> bool: return entry.slot == slot):
		slot += 1
	roster.append({"id": sender, "slot": slot, "name": name_value.strip_edges().left(18) if not name_value.strip_edges().is_empty() else "Jugador %d" % (slot + 1), "ready": false})
	_publish_lobby()

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(reason: String) -> void:
	leave(reason)

func set_ready(value: bool) -> void:
	if is_host():
		_update_ready(1, value)
	else:
		_ready_request.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable", 0)
func _ready_request(value: bool) -> void:
	if is_host():
		_update_ready(multiplayer.get_remote_sender_id(), value)

func _update_ready(peer: int, value: bool) -> void:
	if status != "lobby":
		return
	for entry in roster:
		if entry.id == peer:
			entry.ready = value
	_publish_lobby()

func choose_mode(value: String) -> void:
	if not is_host() or status != "lobby" or value not in ["maze", "mountain"]:
		return
	mode = value
	_publish_lobby()

func _publish_lobby() -> void:
	if not practice:
		_send_to_clients("_lobby", [roster, mode, message])
	changed.emit()

func _send_to_clients(method_name: String, arguments: Array) -> void:
	if practice or not multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return
	var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var connected := multiplayer.get_peers()
	for entry in roster:
		var peer: int = entry.id
		if peer == 1 or not connected.has(peer):
			continue
		var connection := transport.get_peer(peer)
		if connection != null and connection.get_state() == ENetPacketPeer.STATE_CONNECTED and connection.get_channels() > 0:
			callv("rpc_id", [peer, method_name] + arguments)

@rpc("authority", "call_remote", "reliable", 0)
func _lobby(entries: Array, selected_mode: String, notice: String) -> void:
	roster.assign(entries)
	mode = selected_mode
	message = notice
	status = "lobby"
	changed.emit()

func can_start() -> bool:
	return is_host() and status == "lobby" and (practice or roster.size() >= 2) and roster.all(func(entry: Dictionary) -> bool: return entry.ready)

func start_match(seed_value: int = -1) -> void:
	if not can_start():
		return
	_clear_simulation()
	sequence = 0
	input_clock = 0.0
	snapshot_clock = 0.0
	received_sequence = -1
	snapshots_received = 0
	status = "match"
	message = ""
	simulation = Simulation.new()
	add_child(simulation)
	simulation.initialize(mode, roster, randi() if seed_value < 0 else seed_value, practice)
	simulation.map_changed.connect(_on_map_changed)
	simulation.event_occurred.connect(_on_event)
	current_map = simulation.map
	current_state = simulation.snapshot()
	if not practice:
		_send_to_clients("_begin", [current_map, roster, current_state])
	_start_barrier()
	map_received.emit(current_map)
	state_received.emit(current_state)
	changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _begin(map_value: Dictionary, entries: Array, state: Dictionary) -> void:
	roster.assign(entries)
	mode = map_value.kind
	status = "match"
	received_sequence = -1
	snapshots_received = 0
	current_map = map_value
	current_state = state
	map_received.emit(current_map)
	state_received.emit(state)
	changed.emit()
	_map_ack.rpc_id(1, int(current_map.revision))

func _start_barrier() -> void:
	pending_acks.clear()
	if not practice:
		for entry in roster:
			if entry.id != 1:
				pending_acks[entry.id] = int(current_map.revision)
	barriers_started = Time.get_ticks_msec()

func _on_map_changed(map_value: Dictionary) -> void:
	current_map = map_value
	_start_barrier()
	if not practice:
		_send_to_clients("_new_map", [map_value])
	map_received.emit(map_value)

@rpc("authority", "call_remote", "reliable", 0)
func _new_map(map_value: Dictionary) -> void:
	current_map = map_value
	map_received.emit(map_value)
	_map_ack.rpc_id(1, int(map_value.revision))

@rpc("any_peer", "call_remote", "reliable", 0)
func _map_ack(revision_value: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if is_host() and pending_acks.get(sender, -1) == revision_value:
		pending_acks.erase(sender)

func _physics_process(delta: float) -> void:
	if status == "connecting" and Time.get_ticks_msec() > connect_deadline:
		leave("La conexión tardó demasiado. Comprueba IP, Wi-Fi y sala.")
	if status != "match":
		return
	var direction: Vector2 = tilt.direction if is_instance_valid(tilt) else Vector2.ZERO
	if is_host():
		simulation.set_input(1, direction)
	else:
		input_clock += delta
		if input_clock >= 1.0 / 30.0:
			input_clock = fmod(input_clock, 1.0 / 30.0)
			_submit_input.rpc_id(1, direction)
	if not is_host():
		return
	if not pending_acks.is_empty():
		if Time.get_ticks_msec() - barriers_started > 8000:
			for peer in pending_acks.keys():
				multiplayer.multiplayer_peer.disconnect_peer(peer)
			pending_acks.clear()
		return
	simulation.advance(delta)
	# Local presentation receives every physics step, independently of network cadence.
	current_state = simulation.snapshot()
	snapshot_clock += delta
	if snapshot_clock >= 0.05 or checkpoint_needed:
		snapshot_clock = fmod(snapshot_clock, 0.05)
		sequence += 1
		current_state.sequence = sequence
		if not practice:
			if checkpoint_needed:
				_send_to_clients("_checkpoint", [current_state])
			else:
				var raw := var_to_bytes(current_state)
				_send_to_clients("_snapshot", [raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size()])
		checkpoint_needed = false
	current_state.sequence = sequence
	state_received.emit(current_state)
	if simulation.winner >= 0:
		status = "results"
		changed.emit()

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_input(direction: Vector2) -> void:
	if is_host() and status == "match" and is_instance_valid(simulation):
		simulation.set_input(multiplayer.get_remote_sender_id(), direction)

func use_item() -> void:
	if status != "match":
		return
	if is_host():
		simulation.use_item(1)
	else:
		_use.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 0)
func _use() -> void:
	if is_host() and status == "match" and pending_acks.is_empty():
		simulation.use_item(multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snapshot(packet: PackedByteArray, decoded_size: int) -> void:
	if decoded_size <= 0 or decoded_size > 262144:
		return
	var decoded = bytes_to_var(packet.decompress(decoded_size, FileAccess.COMPRESSION_ZSTD))
	if decoded is Dictionary:
		snapshots_received += 1
		_accept_state(decoded)

@rpc("authority", "call_remote", "reliable", 0)
func _checkpoint(state: Dictionary) -> void:
	_accept_state(state)

func _accept_state(state: Dictionary) -> void:
	if status not in ["match", "results"] or int(state.revision) != int(current_map.get("revision", -1)):
		return
	if int(state.sequence) <= received_sequence:
		return
	received_sequence = int(state.sequence)
	current_state = state
	state_received.emit(state)
	if state.winner >= 0 and status != "results":
		status = "results"
		changed.emit()

func _on_event(kind: String) -> void:
	checkpoint_needed = true
	if kind in ["pickup", "item", "blast", "respawn", "win"]:
		sound_requested.emit(kind)
		if not practice:
			_send_to_clients("_sound", [kind])

@rpc("authority", "call_remote", "reliable", 0)
func _sound(kind: String) -> void:
	sound_requested.emit(kind)

func back_to_lobby() -> void:
	if not is_host() or status not in ["match", "results"]:
		return
	_clear_simulation()
	status = "lobby"
	message = ""
	for entry in roster:
		entry.ready = practice
	_publish_lobby()

func _peer_disconnected(peer: int) -> void:
	if not is_host():
		return
	roster = roster.filter(func(entry: Dictionary) -> bool: return entry.id != peer)
	pending_acks.erase(peer)
	if is_instance_valid(simulation) and simulation.players.has(peer):
		var player = simulation.players[peer]
		simulation.players.erase(peer)
		simulation.remove_child(player)
		player.queue_free()
		checkpoint_needed = true
	if status in ["match", "results"] and roster.size() < 2:
		back_to_lobby()
		message = "Partida cancelada: faltan jugadores."
	if status == "lobby":
		_publish_lobby()
	elif status in ["match", "results"]:
		_send_to_clients("_roster_update", [roster])
		changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _roster_update(entries: Array) -> void:
	roster.assign(entries)
	changed.emit()
