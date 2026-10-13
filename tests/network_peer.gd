extends SceneTree
## Real ENet integration peer. Driven by run_network.py; no game test hooks.
const Tilt = preload("res://scripts/input/tilt_input.gd")
var session
var role: String = "client"
var count: int = 4
var port: int = 24677
var mode: String = "maze"
var start_time: int = 0
var stage: int = 0
var observed: Dictionary = {}
var saw_results: bool = false
var launched: bool = false
var reported: bool = false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"role": role = pair[1]
			"count": count = int(pair[1])
			"port": port = int(pair[1])
			"mode": mode = pair[1]
	_start.call_deferred()

func _start() -> void:
	session = root.get_node("Session")
	var tilt := Tilt.new()
	root.add_child(tilt)
	tilt.set_process(false)
	tilt.set_physics_process(false)
	tilt.direction = Vector2(0.6, 0.4)
	session.tilt = tilt
	start_time = Time.get_ticks_msec()
	var error: Error
	if role == "host":
		error = session.host("Host", false, port)
		session.choose_mode(mode)
		session.set_ready(true)
	else:
		error = session.join("127.0.0.1", "Client", port)
	if error != OK:
		push_error("NETWORK setup failed: " + error_string(error))
		quit(1)

func _process(_delta: float) -> bool:
	if session == null:
		return false
	if Time.get_ticks_msec() - start_time > 23000:
		push_error("NETWORK timeout: %s %s stage=%d observed=%s" % [role, session.status, stage, observed])
		quit(1)
		return false
	if session.status == "lobby":
		if saw_results:
			if role == "host":
				return false
			if not reported:
				reported = true
				print("NETWORK PASS %s %s count=%d lobby-return" % [role, mode, count])
				session.leave()
				quit(0)
			return false
		if role == "client":
			for entry: Dictionary in session.roster:
				if entry.id == session.local_id() and not entry.ready:
					session.set_ready(true)
		elif session.roster.size() == count and session.can_start() and not launched:
			launched = true
			session.start_match(729)
	if session.status == "match":
		launched = true
		var state: Dictionary = session.current_state
		if state.get("players", []).size() == count:
			observed.players = true
		if state.get("revision", 0) == 2:
			observed.regenerated = true
		for player: Dictionary in state.get("players", []):
			if player.slot != 0 and player.inverted_until > state.time:
				observed.inverted = true
		for object: Dictionary in state.get("objects", []):
			observed[object.kind] = true
		if role == "host" and session.pending_acks.is_empty():
			var sim = session.simulation
			if sim.time > 0.5 and stage == 0:
				sim.next_crate = sim.time
				stage = 1
			if sim.time > 1.0 and stage == 1 and mode == "maze":
				sim.players[1].item = "regenerate"
				sim.use_item(1)
				stage = 2
			if sim.time > 1.5 and stage == 2:
				sim.players[1].item = "invert"
				sim.use_item(1)
				stage = 3
			if sim.time > 2.0 and stage == 3:
				sim.players[1].item = "holes"
				sim.use_item(1)
				stage = 4
			if sim.time > 2.5 and stage == 4:
				sim.players[1].item = "enemies"
				sim.use_item(1)
				stage = 5
			if sim.time > 5.0:
				sim.finish(0)
	if session.status == "results" and not saw_results:
		saw_results = true
		var valid: bool = observed.has("players") and observed.has("crate")
		if role == "client":
			valid = valid and session.snapshots_received >= 10
		if mode == "maze":
			valid = valid and observed.has("regenerated") and observed.has("inverted") and observed.has("hole") and observed.has("enemy")
		else:
			valid = valid and observed.has("mine") and observed.has("bomb")
		if not valid or session.current_state.winner != 0:
			push_error("NETWORK state missing: " + str(observed))
			quit(1)
		else:
			print("FINAL_STATE %s" % var_to_bytes(session.current_state).hex_encode().sha256_text())
		if role == "host":
			_return_later()
	return false

func _return_later() -> void:
	await create_timer(1.0).timeout
	session.back_to_lobby()
	# Give reliable lobby packets time to arrive before closing the server.
	await create_timer(1.0).timeout
	print("NETWORK PASS host %s count=%d lobby-return" % [mode, count])
	session.leave()
	quit(0)
