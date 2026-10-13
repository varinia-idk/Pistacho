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
const Interp = preload("res://scripts/core/interpolation.gd")
const InputBuffer = preload("res://scripts/core/input_buffer.gd")
## Un modo nuevo = una escena más aquí; las rondas alternan en este orden.
const MODE_SCENES: Array[String] = ["res://scenes/modes/maze.tscn"]
const COLORS: Array[Color] = [Color("ff5a36"), Color("3fa9f5"), Color("ffd60a"), Color("c56bff")]
const POINTS: Array[int] = [3, 2, 1, 0]
const SLOTS := 4
const COUNTDOWN := 3.0
const CALIBRATION := 1.5    ## Últimos segundos de la cuenta en los que se promedia g0.
const ROUND_END_TIME := 3.0
const INPUT_TIMEOUT := 0.3  ## Sin input remoto durante este tiempo, la inclinación vuelve a cero.
const HISTORY := 256        ## Inputs predichos que recuerda un cliente (~4 s a 60 Hz).

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
var _sim_clock := 0.0                  ## Anfitrión: tiempo de simulación, va en cada estado.
var _clock := Interp.Clock.new()       ## Cliente: reloj del anfitrión y retardo de dibujo.
var _tracks: Array = []                ## Cliente: Interp.Track por ranura.
var _time_track := Interp.Track.new()  ## Cliente: tiempo del modo.
var _remote_inputs: Array = []             ## Anfitrión: un InputBuffer por ranura.
var _seq_in_step: Array[int] = [0, 0, 0, 0]  ## Anfitrión: input usado en el paso físico en curso.
var _seq_done: Array[int] = [0, 0, 0, 0]     ## Anfitrión: input ya reflejado en las posiciones.
var _predicted: Player = null          ## Cliente: su propia bola, simulada al instante (net_predict).
var _input_seq := 0
var _history: Dictionary[int, PackedVector2Array] = {}  ## Cliente: input -> [posición, velocidad] predichas.
var _reconciled := 0
var _server_fields := PackedFloat32Array()  ## Cliente: último estado del anfitrión para su bola.
var _predict_clock := 0.0
var correction_max := 0.0              ## Diagnóstico: mayor corrección reciente de la predicción, px.
var _commands := PackedVector3Array()
var _dash_pending := false
var _server_teleport := 0


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


## Física de jugadores y paredes: Config en vivo en el anfitrión; la cfg de la ronda en un cliente que predice.
func physics_params() -> Dictionary[String, float]:
	return Config.live() if Net.is_host() else mode.cfg


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
		if kind == Action.DASH:
			_dash_pending = true  # En el mismo comando/tick que la inclinación, en ambos equipos.
		else:
			Net.send_action.rpc_id(1, kind)


func set_input(slot: int, value: Vector2) -> void:
	if slot >= 0 and slot < players.size() and value.is_finite():
		players[slot].tilt = value.limit_length(1.0)


func remote_input(slot: int, round_id: int, first_seq: int, commands: PackedVector3Array) -> void:
	if phase == Phase.PLAYING and round_id == round_index and slot < _remote_inputs.size():
		_remote_inputs[slot].push(first_seq, commands)
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
	_remote_inputs.clear()
	_seq_in_step.fill(0)
	_seq_done.fill(0)
	for slot in SLOTS:
		_remote_inputs.append(InputBuffer.new())
	var mode_index := round_index % MODE_SCENES.size()
	var seed_value := _rng.randi()
	var cfg := Config.snapshot()
	_build_round(mode_index, seed_value, cfg)
	mode.build_physics()
	var spawns := mode.spawn_points()
	for slot in SLOTS:
		var player := Player.new()
		player.setup(slot, COLORS[slot], slot == local_slot, Config.live())
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
	_predicted = null


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
	if Net.online and Net.is_host():
		_sim_clock += delta
		if mode != null and not players.is_empty():
			_tick += 1
			if _tick % maxi(1, roundi(Engine.physics_ticks_per_second / Config.value("net_state_hz"))) == 0:
				Net.send_state(_pack_state())


func _play_step(delta: float) -> void:
	# Las posiciones que se envían al final de este tick son del paso anterior: su input es _seq_in_step.
	_seq_done = _seq_in_step.duplicate()
	if local_slot >= 0:
		set_input(local_slot, tilt.value)
		if tilt.consume_dash():
			action(local_slot, Action.DASH)
	for slot in SLOTS:
		if Net.is_remote_human(slot):
			_input_age[slot] += delta
			var buffer: InputBuffer = _remote_inputs[slot]
			var command := buffer.advance()
			set_input(slot, Vector2(command.x, command.y))
			_seq_in_step[slot] = buffer.sequence
			if _input_age[slot] > INPUT_TIMEOUT:
				players[slot].tilt = Vector2.ZERO
			elif command.z > 0.5:
				action(slot, Action.DASH)
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


## [reloj de simulación, tiempo del modo, ronda] y, por ranura, slot + PlayerView.STATE_FIELDS valores.
func _pack_state() -> PackedFloat32Array:
	var data := PackedFloat32Array([_sim_clock, mode.time, round_index])
	for player in players:
		var view := player.view
		data.append_array([player.slot, player.position.x, player.position.y, player.radius,
			PlayerView.FLAG_SHIELD if view.invulnerable else 0,
			player.linear_velocity.x, player.linear_velocity.y, view.falling, view.dash_ready, view.boost,
			_seq_done[player.slot], player.teleport_id])
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
	var predict := Config.flag("net_predict") and local_slot >= 0
	if predict:
		mode.build_physics()  # Paredes locales para predecir la bola propia.
	var spawns := mode.spawn_points()
	for slot in SLOTS:
		if predict and slot == local_slot:
			_predicted = Player.new()
			_predicted.setup(slot, COLORS[slot], true, cfg)
			_predicted.position = spawns[slot]  # Aún fuera del espacio físico.
			mode.add_child(_predicted)
			views.append(_predicted.view)
			continue
		var view := PlayerView.new()
		view.name = "Player%d" % slot
		view.color = COLORS[slot]
		view.radius = cfg["player_radius"]
		view.is_local = slot == local_slot
		view.make_remote(spawns[slot])
		mode.add_child(view)
		views.append(view)
	_history.clear()
	_input_seq = 0
	_reconciled = 0
	_predict_clock = 0.0
	_commands.clear()
	_dash_pending = false
	_server_teleport = 0
	_server_fields = PackedFloat32Array()
	_clock.reset()
	_time_track = Interp.Track.new()
	_tracks.clear()
	for slot in SLOTS:
		var track := Interp.Track.new()
		track.snap_distance = cfg["player_radius"] * 4.0  # Reapariciones: saltar, no cruzar el mapa.
		_tracks.append(track)
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
	if Net.is_host() or mode == null or _tracks.size() < SLOTS or data.size() != 3 + SLOTS * stride:
		return
	if int(data[2]) != round_index or (not _time_track.is_empty() and data[0] <= _time_track.newest()):
		return
	var server_time := data[0]
	_clock.observe(server_time, Time.get_ticks_usec() / 1e6, 1.0 / mode.cfg["net_state_hz"],
		Config.value("net_delay_min"), Config.value("net_delay_max"))
	_time_track.push(server_time, PackedFloat32Array([data[1]]))
	for i in SLOTS:
		var base := 3 + i * stride
		var slot := int(data[base])
		if slot < 0 or slot >= SLOTS:
			continue
		var fields := data.slice(base + 1, base + stride)
		if _predicted and slot == local_slot:
			_reconcile(fields)
		else:
			_tracks[slot].push(server_time, fields)


## Compara el estado del anfitrión con lo predicho para ese mismo input y corrige la diferencia:
## al instante en la física, poco a poco en lo que se ve.
func _reconcile(fields: PackedFloat32Array) -> void:
	_server_fields = fields
	var server_position := Vector2(fields[0], fields[1])
	var server_velocity := Vector2(fields[4], fields[5])
	var falling := fields[6] > 0.0
	_predicted.hold(falling)
	if int(fields[10]) != _server_teleport:
		_server_teleport = int(fields[10])
		_predicted.teleport(server_position)
		_history.clear()
		_reconciled = int(fields[9])
		return
	if falling:
		_history.clear()
		return
	var error: Vector2
	var velocity_error: Vector2
	var seq := int(fields[9])
	if phase != Phase.PLAYING or _history.is_empty():
		# Sin inputs que comparar (cuenta atrás, fin de ronda, tras caer): seguir al anfitrión directamente.
		error = server_position - _predicted.predicted_position()
		velocity_error = server_velocity - _predicted.predicted_velocity()
	elif seq > _reconciled and _history.has(seq):
		_reconciled = seq
		var past := _history[seq]
		error = server_position - past[0]
		velocity_error = server_velocity - past[1]
		for key: int in _history:
			if key > seq:
				_history[key] = PackedVector2Array([_history[key][0] + error, _history[key][1] + velocity_error])
	else:
		return
	if error.length() < 0.5 and velocity_error.length() < 5.0:
		return
	_predicted.correct(error, velocity_error)
	correction_max = maxf(correction_max, error.length())


## Cliente: todo se dibuja en el mismo instante pasado del anfitrión, entre dos estados conocidos.
func _process(delta: float) -> void:
	if Net.is_host() or mode == null or _time_track.is_empty():
		return
	var moment := _clock.render_time(Time.get_ticks_usec() / 1e6, delta, _time_track.newest())
	mode.time = _time_track.sample(moment)[0]
	for slot in mini(views.size(), _tracks.size()):
		if not _tracks[slot].is_empty():
			views[slot].apply_fields(_tracks[slot].sample(moment))
	if _predicted:
		var view := _predicted.view
		if not _server_fields.is_empty():
			# Caídas y escudo los decide el anfitrión.
			view.falling = _server_fields[6]
			view.invulnerable = int(_server_fields[3]) & PlayerView.FLAG_SHIELD != 0
	correction_max *= exp(-delta / 3.0)


func net_stats() -> String:
	if not Net.online or Net.is_host():
		return ""
	return "retardo %d ms · jitter %d ms · hueco máx %d ms · sin datos %d%s" % [
		roundi(_clock.delay * 1000.0), roundi(_clock.jitter * 1000.0), roundi(_clock.gap * 1000.0), _clock.stalls,
		" · corrección %.0f px" % correction_max if _predicted else " · sin predicción"]


func _client_step(delta: float) -> void:
	if _predicted:
		# Estado tras el paso que usó el input _input_seq (antes de aplicar el siguiente).
		_history[_input_seq] = PackedVector2Array([_predicted.predicted_position(), _predicted.predicted_velocity()])
		_history.erase(_input_seq - HISTORY)
	_input_seq += 1
	var dash := tilt.consume_dash() or _dash_pending
	_dash_pending = false
	_commands.append(Vector3(tilt.value.x, tilt.value.y, 1.0 if dash else 0.0))
	if _commands.size() > InputBuffer.REDUNDANCY:
		_commands.remove_at(0)
	Net.send_input.rpc_id(1, round_index, _input_seq - _commands.size() + 1, _commands)
	if _predicted:
		_predict_clock += delta
		_predicted.tilt = tilt.value
		if dash:
			_predicted.dash(_predict_clock)
		_predicted.step(_predict_clock)


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
