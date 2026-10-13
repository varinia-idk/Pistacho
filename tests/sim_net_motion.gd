extends Node
## Movimiento continuo en espacio libre: ejercita la reconciliación real, no solo el reloj de dibujo.

var role := ""
var elapsed := 0.0
var jumps := 0
var max_step := 0.0
var max_correction := 0.0
var previous := Vector2.ZERO
var started := false
var direction := 0
var sampled := false
var final_position := Vector2.ZERO
var scenario := "free"
var dash_count := 0
var teleport_count := 0
var last_teleport := 0
var triggered := false
var requested_dash := false
var final_dashes := 0
var final_teleports := 0

func _ready() -> void:
	role = OS.get_cmdline_user_args()[0]
	scenario = OS.get_cmdline_user_args()[1]
	Config.reset()
	Config.set_value("rounds", 1)
	Game.world = Node2D.new()
	add_child(Game.world)
	Game.round_started.connect(_prepare)
	Game.phase_changed.connect(_phase)
	Game._rng.seed = 1234
	if role == "host":
		if Net.host() != OK:
			get_tree().quit(1)
			return
		Game.to_lobby()
		Net.roster_changed.connect(func() -> void:
			if Game.phase == Game.Phase.LOBBY and Net.slot_peers[1] > 1:
				Game.start_match())
	else:
		var peer := ENetMultiplayerPeer.new()
		peer.create_client("127.0.0.1", 17777)
		multiplayer.multiplayer_peer = peer
		Net.online = true
		Net.slot_peers = [0, 0, 0, 0]

func _prepare() -> void:
	# Quitar paredes/agujeros/bots aísla las correcciones espurias de los choques y las caídas.
	if scenario != "walls":
		Game.mode.get_node("Walls").collision_layer = 0
	Game.mode.hole_centers.clear()
	Game.mode.goal_point = Vector2(100000, 100000)
	Game.mode.get_node("Effects").hide()
	Game.bots.clear()
	for player in Game.players:
		player.collision_mask = 1 if scenario == "walls" else 0
	var body = Game.players[1] if role == "host" else Game._predicted
	body.dashed.connect(func() -> void: dash_count += 1)

func _phase(phase: Game.Phase) -> void:
	if phase == Game.Phase.PLAYING:
		started = true
		previous = Game.views[1].global_position

func _physics_process(delta: float) -> void:
	if not started:
		return
	elapsed += delta
	if role == "host" and elapsed >= 4.0 and not triggered:
		triggered = true
		if scenario == "contact":
			Game.players[1].apply_central_impulse(Vector2(250.0, 0.0))
		elif scenario == "respawn":
			Game.players[1].start_fall(Game.mode.time, Vector2(200, 35))
	if elapsed >= 15.0 and not sampled:
		sampled = true
		final_position = Game.views[1].global_position
		final_dashes = dash_count
		final_teleports = Game.players[1].teleport_id if role == "host" else teleport_count
		if role == "host":
			print("MOTION host_final=%.3f,%.3f" % [final_position.x, final_position.y])
	if role == "client":
		if scenario == "walls" and elapsed >= 2.0 and not requested_dash:
			Game.request_action(Game.Action.DASH)
			requested_dash = true
		var next_direction := 1 if int(elapsed / 1.5) % 2 == 0 else -1
		if elapsed > 12.0:
			next_direction = 0
		if next_direction != direction:
			for code in [KEY_RIGHT, KEY_LEFT]:
				var key := InputEventKey.new()
				key.physical_keycode = code
				key.pressed = (code == KEY_RIGHT and next_direction == 1) or (code == KEY_LEFT and next_direction == -1)
				Input.parse_input_event(key)
			direction = next_direction
	if elapsed >= (18.0 if role == "host" else 16.0):
		if role == "client":
			print("MOTION jumps=%d max_step=%.2f correction=%.2f final=%.3f,%.3f" % [jumps, max_step, max_correction, final_position.x, final_position.y])
		print("MOTION %s dashes=%d teleports=%d" % [role, final_dashes, final_teleports])
		get_tree().quit()

func _process(delta: float) -> void:
	if not started or role != "client":
		return
	var current: Vector2 = Game.views[1].global_position
	var step := current.distance_to(previous)
	var epoch: int = Game._predicted.teleport_id
	if epoch != last_teleport:
		teleport_count += 1
		last_teleport = epoch
	elif elapsed > 0.5:
		max_step = maxf(max_step, step)
		var speed_limit := 930.0 if scenario == "walls" else 380.0
		if step > speed_limit * maxf(delta, 1.0 / 60.0) + 6.0:
			jumps += 1
	max_correction = maxf(max_correction, Game.correction_max)
	previous = current
