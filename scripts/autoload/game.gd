extends Node
## Flujo de la partida: rondas, puntos, input local y bots. Solo el anfitrión simula.

signal phase_changed(phase: Phase)
signal round_started

enum Phase { MENU, COUNTDOWN, PLAYING, ROUND_END, MATCH_END }
enum Action { DASH, ITEM }

const GameMode = preload("res://scripts/core/game_mode.gd")
const Player = preload("res://scripts/players/player.gd")
const Bot = preload("res://scripts/players/bot.gd")
const TiltReader = preload("res://scripts/input/tilt_reader.gd")
## Un modo nuevo = una escena más aquí; las rondas alternan en este orden.
const MODE_SCENES: Array[String] = ["res://scenes/modes/maze.tscn"]
const COLORS: Array[Color] = [Color("ff5a36"), Color("3fa9f5"), Color("ffd60a"), Color("c56bff")]
const POINTS: Array[int] = [3, 2, 1, 0]
const SLOTS := 4
const COUNTDOWN := 3.0
const CALIBRATION := 1.5  ## Últimos segundos de la cuenta en los que se promedia g0.
const ROUND_END_TIME := 3.0

var phase := Phase.MENU
var phase_left := 0.0
var world: Node2D
var mode: GameMode
var players: Array[Player] = []
var bots: Array[Bot] = []
var local_slot := 0
var scores: Array[int] = [0, 0, 0, 0]
var round_index := 0
var rounds_total := 5
var last_ranking: Array[int] = []
var tilt := TiltReader.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func is_host() -> bool:
	return true


func player_name(slot: int) -> String:
	return "Tú" if slot == local_slot else "Bot %d" % (slot + 1)


func local_player() -> Player:
	return players[local_slot] if local_slot < players.size() else null


func start_match() -> void:
	scores = [0, 0, 0, 0]
	round_index = 0
	rounds_total = Config.count("rounds")
	_start_round()


func to_menu() -> void:
	_clear_round()
	_set_phase(Phase.MENU)


## Puesto final: más puntos primero; empate por ranura.
func match_ranking() -> Array[int]:
	var order: Array[int] = [0, 1, 2, 3]
	order.sort_custom(func(a: int, b: int) -> bool: return scores[a] > scores[b] or (scores[a] == scores[b] and a < b))
	return order


func set_input(slot: int, value: Vector2) -> void:
	if slot < players.size() and value.is_finite():
		players[slot].tilt = value.limit_length(1.0)


func action(slot: int, kind: Action) -> void:
	if phase != Phase.PLAYING or slot >= players.size():
		return
	match kind:
		Action.DASH:
			players[slot].dash(mode.time)
		Action.ITEM:
			pass  # Fase 3: cajas sorpresa.


func _start_round() -> void:
	_clear_round()
	var scene: PackedScene = load(MODE_SCENES[round_index % MODE_SCENES.size()])
	mode = scene.instantiate()
	world.add_child(mode)
	mode.setup(_rng.randi())
	mode.build_physics()
	var spawns := mode.spawn_points()
	for slot in SLOTS:
		var player := Player.new()
		player.setup(slot, COLORS[slot], slot == local_slot)
		player.position = spawns[slot]  # Aún fuera del espacio físico; después solo teleport().
		mode.add_player(player)
		players.append(player)
		if slot == local_slot:
			player.hit.connect(_on_local_hit)
			player.fell.connect(_vibrate.bind(120))
			player.dashed.connect(_vibrate.bind(30))
		elif mode.uses_bots():
			bots.append(Bot.new(slot, _rng.randi()))
	tilt.reset()
	_set_phase(Phase.COUNTDOWN, COUNTDOWN)
	round_started.emit()


func _clear_round() -> void:
	if is_instance_valid(mode):
		# Fuera del árbol ya, para que el modo siguiente conserve su nombre (ruta estable).
		mode.get_parent().remove_child(mode)
		mode.queue_free()
	mode = null
	players.clear()
	bots.clear()


func _physics_process(delta: float) -> void:
	tilt.update(delta)
	match phase:
		Phase.COUNTDOWN:
			phase_left -= delta
			if phase_left <= CALIBRATION and not tilt.calibrating and phase_left > 0.0:
				tilt.begin_calibration()
			if phase_left <= 0.0:
				tilt.end_calibration()
				_set_phase(Phase.PLAYING)
		Phase.PLAYING:
			_play_step(delta)
		Phase.ROUND_END:
			phase_left -= delta
			if phase_left <= 0.0:
				_next_round()


func _play_step(delta: float) -> void:
	set_input(local_slot, tilt.value)
	if tilt.consume_dash():
		action(local_slot, Action.DASH)
	for bot in bots:
		bot.think(mode, players[bot.slot], delta)
	mode.physics_step(delta)
	if mode.get_winner() >= 0 or mode.time >= Config.value("round_time"):
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


func _set_phase(value: Phase, duration: float = 0.0) -> void:
	phase = value
	phase_left = duration
	phase_changed.emit(phase)


func _on_local_hit(strength: float) -> void:
	_vibrate(int(clampf(strength * 0.15, 15.0, 60.0)))


func _vibrate(ms: int) -> void:
	if Config.flag("vibration"):
		Input.vibrate_handheld(ms)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_SPACE:
		action(local_slot, Action.DASH)
	elif key.physical_keycode == KEY_E:
		action(local_slot, Action.ITEM)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		tilt.reset()
		set_input(local_slot, Vector2.ZERO)
