extends SceneTree
const Track = preload("res://scripts/core/motion_track.gd")
const Avatar = preload("res://scripts/players/avatar.gd")
const ArenaScene = preload("res://scenes/modes/arena.tscn")
var checks := 0
var failures := 0
var updates := 0
var samples: Array[float] = []
var arena: Node2D

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PRESENTATION FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_network_motion()
	_teleport_and_stops()
	await _local_presentation()
	print("PRESENTATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _network_motion() -> void:
	# 20Hz packets with variable arrival times rendered at common screen refresh rates.
	for fps: int in [30, 60, 90, 120]:
		var track = Track.new()
		var sent := 0
		var previous := Vector2.ZERO
		var min_step := INF
		var max_step := 0.0
		var step := 1.0 / fps
		for frame in range(fps * 3):
			var now := frame * step
			while sent < 60:
				var stamp := sent * 0.05
				var delay: float = 0.03 + [0.0, 0.014, -0.01, 0.006][sent % 4]
				if stamp + delay > now:
					break
				# One lost packet must fit inside the interpolation buffer.
				if sent != 24:
					track.push(Vector2(stamp * 120.0, 20.0), stamp)
				sent += 1
			var point: Vector2 = track.advance(step)
			if frame > fps:
				min_step = minf(min_step, point.x - previous.x)
				max_step = maxf(max_step, point.x - previous.x)
			previous = point
		check(absf(min_step - 120.0 / fps) < 0.001, "no pauses at %s FPS under LAN jitter: %s" % [fps, min_step])
		check(absf(max_step - min_step) < 0.001, "uniform speed at %s FPS: %s..%s" % [fps, min_step, max_step])
		check(track.samples.size() <= Track.MAX_SAMPLES, "bounded history")

func _teleport_and_stops() -> void:
	var track = Track.new()
	track.push(Vector2.ZERO, 0.0)
	track.push(Vector2(5, 0), 0.05)
	track.push(Vector2(10, 0), 0.1)
	check(track.advance(1.0) == Vector2(10, 0), "packet starvation stops at known position; no wall extrapolation")
	track.push(Vector2(40, 0), 0.8)
	check(track.advance(0.05).x > 30.0, "long outage resumes near current state")
	track.push(Vector2(1000, 0), 0.7)
	check(track.advance(0.1).x == 40.0, "old packet cannot rewind motion")
	var avatar := Avatar.new()
	root.add_child(avatar)
	avatar.set_process(false)
	var state := {"position": Vector2(10, 20), "radius": 10.0, "slot": 0, "protected_until": 0.0, "inverted_until": 0.0, "respawn_serial": 0}
	avatar.update_state(state, 0.0)
	var respawn := state.duplicate()
	respawn.position = Vector2(15, 20)
	respawn.respawn_serial = 1
	avatar.update_state(respawn, 0.05)
	avatar.advance_motion(0.01)
	check(avatar.position == Vector2(15, 20), "short respawn snaps without sliding")
	check(avatar.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "network visuals avoid double interpolation")
	avatar.local_simulation = true
	avatar.update_state(state, 0.1)
	check(avatar.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON, "local visuals use native physics interpolation")
	avatar.free()

func _local_presentation() -> void:
	var session = root.get_node("Session")
	check(ProjectSettings.get_setting("physics/common/physics_interpolation"), "project enables interpolation")
	session.host("Presentation", true)
	session.start_match(47)
	session.simulation.countdown = 0.0
	arena = ArenaScene.instantiate()
	arena.local_simulation = true
	root.add_child(arena)
	arena.set_map(session.current_map)
	arena.set_state(session.current_state)
	session.state_received.connect(_on_state)
	for i in range(30):
		await physics_frame
	await process_frame
	check(updates >= 29 and updates <= 31, "local presentation updates every physics tick, received %s" % updates)
	var regular := true
	for i in range(1, samples.size()):
		regular = regular and absf(samples[i] - samples[i - 1] - 1.0 / 60) < 0.00001
	check(regular, "local state timestamps have no 20Hz gaps")
	check(arena.avatars[1].local_simulation, "arena passes local interpolation mode")
	session.state_received.disconnect(_on_state)
	arena.free()
	session.leave()

func _on_state(state: Dictionary) -> void:
	updates += 1
	samples.append(state.time)
	arena.set_state(state)
