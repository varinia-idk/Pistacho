extends Node
## Flujo de la partida: sala, rondas, puntos, input local y bots.
## Solo el anfitrión simula. Los clientes reconstruyen el mapa con la semilla y la configuración
## de la ronda, envían su inclinación y dibujan el estado que reciben.

signal phase_changed(phase: Phase)
signal round_started

enum Phase { MENU, LOBBY, COUNTDOWN, PLAYING, ROUND_END, MATCH_END }
enum Action { DASH, ITEM }

const GameMode = preload("res://scripts/core/game_mode.gd")
const Player = preload("res://scripts/players/player.gd")
const PlayerView = preload("res://scripts/players/player_view.gd")
const Bot = preload("res://scripts/players/bot.gd")
const TiltReader = preload("res://scripts/input/tilt_reader.gd")
## Un modo nuevo = una escena más aquí; las rondas alternan en este orden.
const MODE_SCENES: Array[String] = ["res://scenes/modes/maze.tscn"]
const COLORS: Array[Color] = [Color("ff5a36"), Color("3fa9f5"), Color("ffd60a"), Color("c56bff")]
const POINTS: Array[int] = [3, 2, 1, 0]
const SLOTS := 4
const COUNTDOWN := 3.0
const CALIBRATION := 1.5    ## Últimos segundos de la cuenta en los que se promedia g0.
const ROUND_END_TIME := 3.0
const INPUT_TIMEOUT := 0.3  ## Sin input remoto durante este tiempo, la inclinación vuelve a cero.
const STATE_EVERY := 2      ## Ticks físicos entre paquetes de estado: 60 Hz / 2 = 30 Hz.

var phase := Phase.MENU
var phase_left := 0.0
var world: Node2D
var mode: GameMode
var players: Array[Player] = []        ## Cuerpos físicos, solo en el anfitrión.
var views: Array[PlayerView] = []      ## Vistas por ranura en todos los peers.
var bots: Dictionary[int, Bot] = {}    ## Ranura -> bot (anfitrión).
var local_slot := 0  ## -1 = sin jugador local (simulación solo con bots).
var scores: Array[int] = [0, 0, 0, 0]
var round_index := 0
var rounds_total := 5
var last_ranking: Array[int] = []
var tilt := TiltReader.new()
var _rng := RandomNumberGenerator.new()
var _input_age: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _tick := 0


func _ready() -> void:
	_rng.randomize()


func player_name(slot: int) -> String:
	if slot == local_slot:
		return "Tú"
	if Net.slot_peers[slot] == 0 or (slot < players.size() and players[slot].is_bot):
		return "Bot %d" % (slot + 1)
	return "Anfitrión" if slot == 0 else "Jugador %d" % (slot + 1)


func local_view() -> PlayerView:
	return views[local_slot] if local_slot >= 0 and local_slot < views.size() else null


## Puesto final: más puntos primero; empate por ranura.
func match_ranking() -> Array[int]:
	var order: Array[int] = [0, 1, 2, 3]
	order.sort_custom(func(a: int, b: int) -> bool: return scores[a] > scores[b] or (scores[a] == scores[b] and a < b))
	return order


# --- Flujo (anfitrión u offline) ---

func start_match() -> void:
	if not Net.is_host():
		return
	local_slot = Net.my_slot() if local_slot >= 0 else -1
	scores = [0, 0, 0, 0]
	round_index = 0
	rounds_total = Config.count("rounds")
	Net.lock(true)
	_start_round()


func to_menu() -> void:
	_clear_round()
	_set_phase(Phase.MENU)


func to_lobby() -> void:
	_clear_round()
	Net.lock(false)
	_set_phase(Phase.LOBBY)


## Intención del jugador local (botón, tecla o gesto): directa en el anfitrión, por red en clientes.
func request_action(kind: Action) -> void:
	if Net.is_host():
		action(local_slot, kind)
	elif phase == Phase.PLAYING:
		Net.send_action.rpc_id(1, kind)


func set_input(slot: int, value: Vector2) -> void:
	if slot >= 0 and slot < players.size() and value.is_finite():
		players[slot].tilt = value.limit_length(1.0)


func remote_input(slot: int, value: Vector2) -> void:
	if phase == Phase.PLAYING:
		set_input(slot, value)
		_input_age[slot] = 0.0


func action(slot: int, kind: Action) -> void:
	if phase != Phase.PLAYING or slot < 0 or slot >= players.size():
		return
	match kind:
		Action.DASH:
			players[slot].dash(mode.time)
		Action.ITEM:
			pass  # Fase 3: cajas sorpresa.


## Un humano se desconectó: su ranura pasa a bot sin detener la ronda.
func peer_left(slot: int) -> void:
	if slot < players.size() and not players[slot].is_bot:
		players[slot].is_bot = true
		bots[slot] = Bot.new(slot, _rng.randi())


func _start_round() -> void:
	var mode_index := round_index % MODE_SCENES.size()
	var seed_value := _rng.randi()
	var cfg := Config.snapshot()
	_build_round(mode_index, seed_value, cfg)
	mode.build_physics()
	var spawns := mode.spawn_points()
	for slot in SLOTS:
		var player := Player.new()
		player.setup(slot, COLORS[slot], slot == local_slot)
		player.position = spawns[slot]  # Aún fuera del espacio físico; después solo teleport().
		mode.add_player(player)
		players.append(player)
		views.append(player.view)
		if slot == local_slot or Net.is_remote_human(slot):
			player.hit.connect(func(strength: float) -> void: _haptic(slot, int(clampf(strength * 0.15, 15.0, 60.0))))
			player.fell.connect(_haptic.bind(slot, 120))
			player.dashed.connect(_haptic.bind(slot, 30))
			_input_age[slot] = 0.0
		elif mode.uses_bots():
			player.is_bot = true
			bots[slot] = Bot.new(slot, _rng.randi())
	Net.broadcast(Net.Ev.ROUND, [mode_index, seed_value, cfg, round_index, rounds_total, scores])
	tilt.reset()
	_set_phase(Phase.COUNTDOWN, COUNTDOWN)
	round_started.emit()


## Parte común a anfitrión y clientes: el mapa sale solo de (modo, semilla, cfg).
func _build_round(mode_index: int, seed_value: int, cfg: Dictionary[String, float]) -> void:
	_clear_round()
	var scene: PackedScene = load(MODE_SCENES[mode_index])
	mode = scene.instantiate()
	world.add_child(mode)
	mode.setup(seed_value, cfg)


func _clear_round() -> void:
	if is_instance_valid(mode):
		# Fuera del árbol ya, para que el modo siguiente conserve su nombre (ruta estable).
		mode.get_parent().remove_child(mode)
		mode.queue_free()
	mode = null
	players.clear()
	views.clear()
	bots.clear()


func _physics_process(delta: float) -> void:
	tilt.update(delta)
	match phase:
		Phase.COUNTDOWN:
			phase_left -= delta
			if phase_left <= CALIBRATION and phase_left > 0.0 and not tilt.calibrating:
				tilt.begin_calibration()
			if phase_left <= 0.0 and tilt.calibrating:
				tilt.end_calibration()
			if phase_left <= 0.0 and Net.is_host():
				_set_phase(Phase.PLAYING)
		Phase.PLAYING:
			if Net.is_host():
				_play_step(delta)
			else:
				_client_step(delta)
		Phase.ROUND_END:
			phase_left -= delta
			if phase_left <= 0.0 and Net.is_host():
				_next_round()
	if Net.online and Net.is_host() and mode != null and not players.is_empty():
		_tick += 1
		if _tick % STATE_EVERY == 0:
			Net.send_state(_pack_state())


func _play_step(delta: float) -> void:
	if local_slot >= 0:
		set_input(local_slot, tilt.value)
		if tilt.consume_dash():
			action(local_slot, Action.DASH)
	for slot in SLOTS:
		if Net.is_remote_human(slot):
			_input_age[slot] += delta
			if _input_age[slot] > INPUT_TIMEOUT:
				players[slot].tilt = Vector2.ZERO
	for slot: int in bots:
		bots[slot].think(mode, players[slot], delta)
	mode.physics_step(delta)
	if mode.get_winner() >= 0 or mode.time >= mode.cfg["round_time"]:
		_end_round()


func _end_round() -> void:
	last_ranking = mode.ranking()
	for place in last_ranking.size():
		scores[last_ranking[place]] += POINTS[place]
	for player in players:
		player.tilt = Vector2.ZERO
	_set_phase(Phase.ROUND_END, ROUND_END_TIME)


func _next_round() -> void:
	round_index += 1
	if round_index >= rounds_total:
		_set_phase(Phase.MATCH_END)
	else:
		_start_round()


## La cuenta atrás no se difunde: la implica el evento ROUND.
func _set_phase(value: Phase, duration: float = 0.0) -> void:
	phase = value
	phase_left = duration
	if value != Phase.COUNTDOWN:
		Net.broadcast(Net.Ev.PHASE, [value, duration, last_ranking, scores])
	phase_changed.emit(phase)


## Por ranura: slot + PlayerView.STATE_FIELDS valores.
func _pack_state() -> PackedFloat32Array:
	var data := PackedFloat32Array([mode.time])
	for player in players:
		var view := player.view
		data.append_array([player.slot, player.position.x, player.position.y, player.radius,
			PlayerView.FLAG_SHIELD if view.invulnerable else 0,
			player.linear_velocity.x, player.linear_velocity.y, view.falling, view.dash_ready, view.boost])
	return data


func _haptic(slot: int, ms: int) -> void:
	if slot == local_slot:
		vibrate(ms)
	else:
		Net.vibrate_slot(slot, ms)


func vibrate(ms: int) -> void:
	if Config.flag("vibration"):
		Input.vibrate_handheld(ms)


# --- Cliente ---

func joined_lobby() -> void:
	if not Net.is_host() and phase == Phase.MENU:
		Net.status = ""
		_set_phase(Phase.LOBBY)


## args: [modo, semilla, cfg, ronda, rondas, puntos].
func client_round(args: Array) -> void:
	var raw: Dictionary = args[2]
	var cfg: Dictionary[String, float] = {}
	for key: String in Config.DEFAULTS:
		cfg[key] = float(raw.get(key, Config.DEFAULTS[key][0]))
	round_index = int(args[3])
	rounds_total = int(args[4])
	scores.assign(args[5])
	local_slot = Net.my_slot()
	_build_round(int(args[0]), int(args[1]), cfg)
	var spawns := mode.spawn_points()
	for slot in SLOTS:
		var view := PlayerView.new()
		view.name = "Player%d" % slot
		view.color = COLORS[slot]
		view.radius = cfg["player_radius"]
		view.is_local = slot == local_slot
		view.make_follower(spawns[slot])
		mode.add_child(view)
		views.append(view)
	tilt.reset()
	_set_phase(Phase.COUNTDOWN, COUNTDOWN)
	round_started.emit()


## args: [fase, duración, clasificación, puntos].
func client_phase(args: Array) -> void:
	var value := int(args[0]) as Phase
	last_ranking.assign(args[2])
	scores.assign(args[3])
	if value == Phase.LOBBY or value == Phase.MENU:
		_clear_round()
	if value == Phase.PLAYING and tilt.calibrating:
		tilt.end_calibration()
	phase = value
	phase_left = float(args[1])
	phase_changed.emit(phase)


func apply_state(data: PackedFloat32Array) -> void:
	var stride := 1 + PlayerView.STATE_FIELDS
	if Net.is_host() or mode == null or views.size() < SLOTS or data.size() < 1 + SLOTS * stride:
		return
	mode.time = data[0]
	for i in SLOTS:
		var base := 1 + i * stride
		var slot := int(data[base])
		if slot >= 0 and slot < SLOTS:
			views[slot].apply_state(data.slice(base + 1, base + stride))


func _client_step(delta: float) -> void:
	mode.time += delta  # Entre paquetes; cada estado lo corrige.
	Net.send_input.rpc_id(1, tilt.value)
	if tilt.consume_dash():
		request_action(Action.DASH)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_SPACE:
		request_action(Action.DASH)
	elif key.physical_keycode == KEY_E:
		request_action(Action.ITEM)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		tilt.reset()
		set_input(local_slot, Vector2.ZERO)
