extends Node
## Red LAN: ENet y RPCs manuales en este autoload, con la misma ruta en todos los peers.
## Canales: 0 = eventos y acciones (fiables), 1 = input, 2 = estado. Van separados porque ENet
## retiene en un canal todo lo posterior a un paquete fiable perdido: un evento no debe frenar el estado.

signal roster_changed

enum Ev { ROSTER, ROUND, PHASE, VIBRATE }

const PORT := 7777
const MAX_CLIENTS := 3
const PROTOCOL := 1             ## Subir si cambia el formato de los mensajes.
const PEER_TIMEOUT_MIN_MS := 4000
const PEER_TIMEOUT_MAX_MS := 8000  ## Un teléfono que deja de responder pasa a bot como mucho tras este tiempo.
const THROTTLE_INTERVAL_MS := 5000  ## Valor por defecto de ENet; con aceleración y deceleración 0 no cambia.
const SETTINGS := "user://net.cfg"

var online := false
var hosting := false            ## Propio en vez de multiplayer.is_server(): sigue siendo válido con el peer cerrado.
## Peer de cada ranura; 0 = bot. El anfitrión siempre es el peer 1 en la ranura 0.
var slot_peers: Array[int] = [1, 0, 0, 0]
var ping_ms := -1.0
var status := ""                ## Último aviso para el menú (errores de conexión).
var last_ip := ""
var states_received := 0         ## Paquetes de estado recibidos (cliente), para depuración.


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS) == OK:
		last_ip = str(settings.get_value("net", "last_ip", ""))


func is_host() -> bool:
	return not online or hosting


func my_slot() -> int:
	if not online or hosting:
		return 0
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return -1
	return slot_peers.find(multiplayer.get_unique_id())


func is_remote_human(slot: int) -> bool:
	return online and slot_peers[slot] > 1


## IPv4 privadas de este dispositivo, para que los demás se conecten.
func private_ipv4() -> Array[String]:
	var result: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			result.append(ip)
		elif ip.begins_with("172."):
			var second := ip.get_slice(".", 1).to_int()
			if second >= 16 and second <= 31:
				result.append(ip)
	return result


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		status = "No se pudo abrir la sala: el puerto %d está ocupado o bloqueado" % PORT
		return error
	multiplayer.multiplayer_peer = peer
	(multiplayer as SceneMultiplayer).server_relay = false
	online = true
	hosting = true
	status = ""
	slot_peers = [1, 0, 0, 0]
	roster_changed.emit()
	return OK


## remember: guardar la IP para el menú (los tests no tocan las preferencias).
func join(ip: String, remember := true) -> Error:
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		status = "IP no válida"
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, PORT)
	if error != OK:
		status = "No se pudo iniciar la conexión"
		return error
	multiplayer.multiplayer_peer = peer
	online = true
	slot_peers = [0, 0, 0, 0]
	status = "Conectando a %s…" % ip
	if remember:
		last_ip = ip
		var settings := ConfigFile.new()
		settings.set_value("net", "last_ip", ip)
		settings.save(SETTINGS)
	return OK


func leave() -> void:
	if online:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	hosting = false
	slot_peers = [1, 0, 0, 0]
	ping_ms = -1.0


## El anfitrión no acepta conexiones nuevas durante la partida.
func lock(locked: bool) -> void:
	if online and is_host():
		multiplayer.multiplayer_peer.refuse_new_connections = locked


func broadcast(kind: Ev, args: Array) -> void:
	if online and is_host():
		event.rpc(kind, args)


func send_state(data: PackedFloat32Array) -> void:
	if online and is_host():
		state.rpc(data)


func vibrate_slot(slot: int, ms: int) -> void:
	if is_remote_human(slot):
		event.rpc_id(slot_peers[slot], Ev.VIBRATE, [ms])


func _process(_delta: float) -> void:
	if not online or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var total := 0.0
	var count := 0
	for peer_id in ([1] if not is_host() else slot_peers.filter(func(id: int) -> bool: return id > 1)):
		var packet_peer := enet.get_peer(peer_id)
		if packet_peer:
			total += packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			count += 1
	ping_ms = total / count if count > 0 else -1.0


# --- RPCs (spec §6) ---

## seq numera los inputs del cliente: el anfitrión lo devuelve en el estado para la predicción.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func send_input(tilt: Vector2, seq: int) -> void:
	var slot := _sender_slot()
	if slot > 0 and tilt.is_finite():
		Game.remote_input(slot, tilt.limit_length(1.0), seq)


@rpc("any_peer", "call_remote", "reliable", 0)
func send_action(kind: int) -> void:
	var slot := _sender_slot()
	if slot > 0 and kind >= 0 and kind < Game.Action.size():
		Game.action(slot, kind)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func state(data: PackedFloat32Array) -> void:
	states_received += 1
	Game.apply_state(data)


@rpc("authority", "call_remote", "reliable", 0)
func event(kind: int, args: Array) -> void:
	match kind:
		Ev.ROSTER:
			if int(args[0]) != PROTOCOL:
				leave.call_deferred()
				status = "El anfitrión usa otra versión del juego"
				Game.to_menu()
				return
			slot_peers.assign(args[1])
			roster_changed.emit()
			Game.joined_lobby()
		Ev.ROUND:
			Game.client_round(args)
		Ev.PHASE:
			Game.client_phase(args)
		Ev.VIBRATE:
			Game.vibrate(int(args[0]))


func _sender_slot() -> int:
	if not online or not is_host():
		return -1
	return slot_peers.find(multiplayer.get_remote_sender_id())


func _broadcast_roster() -> void:
	broadcast(Ev.ROSTER, [PROTOCOL, slot_peers])
	roster_changed.emit()


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	var slot := slot_peers.find(0)
	if slot < 0 or Game.phase != Game.Phase.LOBBY:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_tune_peer((multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id))
	slot_peers[slot] = id
	_broadcast_roster()


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	var slot := slot_peers.find(id)
	if slot < 0:
		return
	slot_peers[slot] = 0
	Game.peer_left(slot)
	_broadcast_roster()


## Tiempo de espera corto y sin el throttle de ENet, que descarta paquetes no fiables cuando la
## latencia sube (Wi-Fi con altibajos): el estado pesa ~5 KB/s y perderlo se ve a saltos.
func _tune_peer(packet_peer: ENetPacketPeer) -> void:
	packet_peer.set_timeout(0, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
	packet_peer.throttle_configure(THROTTLE_INTERVAL_MS, 0, 0)


func _on_connected() -> void:
	_tune_peer((multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(1))
	status = "Conectado; esperando la sala…"


# leave() diferido: no se cambia el peer dentro de una señal emitida por él.
func _on_connection_failed() -> void:
	leave.call_deferred()
	status = "No se pudo conectar (¿IP correcta, misma red, partida en curso?)"
	Game.to_menu()


func _on_server_disconnected() -> void:
	leave.call_deferred()
	status = "Se perdió la conexión con el anfitrión"
	Game.to_menu()
