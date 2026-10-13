extends Node
## Prueba LAN con procesos reales en localhost; la lanza tests/run_lan.sh.
##   godot --headless --path . res://tests/sim_lan.tscn -- host <clientes>
##   godot --headless --path . res://tests/sim_lan.tscn -- client <segundos_hasta_irse | 0>
## Imprime líneas "LAN ..." que run_lan.sh compara entre procesos.

const SAMPLE_AFTER := 3.0

var role := ""
var expected := 0
var leave_after := 0.0
var _playing_for := 0.0
var _spawn := Vector2.ZERO
var _sampled := false
var _states_at_start := 0
var _was_in_match := false
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	var world := Node2D.new()
	add_child(world)
	Game.world = world
	Game.round_started.connect(_on_round_started)
	Game.phase_changed.connect(_on_phase)
	if role == "host":
		expected = int(args[1])
		Config.set_value("rounds", 1)
		Net.host()
		Game.to_lobby()
		Net.roster_changed.connect(_on_roster)
	else:
		leave_after = float(args[1])
		Net.join("127.0.0.1", false)


func _on_roster() -> void:
	var humans := Net.slot_peers.filter(func(id: int) -> bool: return id > 1).size()
	if Game.phase == Game.Phase.LOBBY and humans == expected:
		Game.start_match()
	elif Game.phase == Game.Phase.PLAYING:
		for slot in Game.SLOTS:
			if slot > 0 and Game.players[slot].is_bot and slot <= expected:
				print("LAN host ranura%d bot" % slot)


func _on_round_started() -> void:
	var mode = Game.mode
	print("LAN mapa %d" % hash([mode.data.walls, mode.data.holes, mode.cell, mode.data.seed_used]))


func _on_phase(phase: Game.Phase) -> void:
	if phase == Game.Phase.PLAYING:
		_was_in_match = true
		_playing_for = 0.0
		_sampled = false
		_states_at_start = Net.states_received
		var slot := 1 if role == "host" else Net.my_slot()
		_spawn = _position_of(slot)
		# Abajo: de la celda (1,0) a la (1,1), dentro de la sala de salida sin paredes internas.
		if role == "client" and Net.my_slot() == 1:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_DOWN
			key.pressed = true
			Input.parse_input_event(key)
	elif phase == Game.Phase.MATCH_END:
		print("LAN %s fin" % role)
		if role == "host":
			await get_tree().create_timer(1.0).timeout
			Net.leave()
			_quit()
	elif phase == Game.Phase.MENU and role == "client" and _was_in_match:
		print("LAN client desconectado: %s" % Net.status)
		_quit()


func _position_of(slot: int) -> Vector2:
	if role == "host":
		return Game.players[slot].position
	return Game.views[slot].target


func _physics_process(delta: float) -> void:
	if Game.phase != Game.Phase.PLAYING or _done:
		return
	_playing_for += delta
	var slot := 1 if role == "host" else Net.my_slot()
	if not _sampled and _playing_for >= SAMPLE_AFTER:
		_sampled = true
		print("LAN %s ranura%d dy=%.0f" % [role, slot, _position_of(slot).y - _spawn.y])
		if role == "client":
			print("LAN client estados %.1f Hz" % ((Net.states_received - _states_at_start) / _playing_for))
	if role == "client" and leave_after > 0.0 and _playing_for >= leave_after:
		print("LAN client ranura%d se va" % slot)
		Net.leave()
		_quit()


func _quit() -> void:
	_done = true
	get_tree().quit()
