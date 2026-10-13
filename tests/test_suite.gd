extends SceneTree
const Maze = preload("res://scripts/modes/maze_generator.gd")
const Mountain = preload("res://scripts/modes/mountain_map.gd")
const Simulation = preload("res://scripts/core/match_simulation.gd")
var checks: int = 0
var failures: int = 0
var sim: Node2D
const ROSTER := [{"id": 1, "slot": 0}, {"id": 2, "slot": 1}, {"id": 3, "slot": 2}, {"id": 4, "slot": 3}]

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	_generation()
	await _new_match("maze")
	_items_and_hazards()
	_victory_and_pickups()
	await _new_match("mountain")
	_mountain_rules()
	await _new_match("maze")
	await _physics_and_timeout()
	_network_validation()
	sim.free()
	print("RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _new_match(mode: String) -> void:
	if is_instance_valid(sim):
		sim.free()
	sim = Simulation.new()
	root.add_child(sim)
	sim.initialize(mode, ROSTER, 729)
	sim.countdown = 0.0
	await physics_frame

func _generation() -> void:
	var goal := Vector2i(12, 7)
	for seed_value in range(80):
		var map_value := Maze.generate(seed_value)
		check(map_value == Maze.generate(seed_value), "same seed yields same maze")
		var preserved: Array = []
		for spawn in Maze.spawn_points():
			check(not Maze.route(map_value.cells, Maze.cell_at(spawn), goal).is_empty(), "corner reaches center")
		for y in range(1, Maze.HEIGHT - 1):
			for x in range(1, Maze.WIDTH - 1):
				if map_value.cells[Maze.index(Vector2i(x, y))] == 1 and preserved.size() < 12:
					preserved.append(Maze.center(Vector2i(x, y)) + Vector2(5, 4))
		var rebuilt := Maze.generate(seed_value + 1000, preserved)
		for point: Vector2 in preserved:
			check(not Maze.route(rebuilt.cells, Maze.cell_at(point), goal).is_empty(), "preserved player reaches center")
			for offset: Vector2 in [Vector2(-11, -11), Vector2(11, 11), Vector2(-11, 11), Vector2(11, -11)]:
				check(rebuilt.cells[Maze.index(Maze.cell_at(point + offset))] == 1, "preserved disk never intersects wall")
	var mountain := Mountain.generate()
	for point: Vector2 in mountain.spiral:
		check(Mountain.on_path(point, mountain, 4.0), "entire spiral traversable")
	for lane: Array in mountain.lanes:
		for point: Vector2 in lane:
			check(Mountain.on_path(point, mountain), "all four accesses connected")
	check(not Mountain.on_path(Vector2(360, 400), mountain), "outside mountain is fall zone")
	check(Mountain.on_path(Mountain.CENTER, mountain), "summit traversable")

func _items_and_hazards() -> void:
	var owner = sim.players[1]
	var before: Dictionary = {}
	for peer in sim.players:
		before[peer] = sim.players[peer].position
	owner.item = "regenerate"
	check(sim.use_item(1), "regeneration accepted")
	check(sim.revision == 2, "regeneration increments revision")
	for peer in before:
		check(before[peer] == sim.players[peer].position, "regeneration keeps exact coordinates")
		check(sim._valid_point(before[peer], 11), "regeneration clears player collision shape")
	check(not sim.use_item(1), "duplicate use rejected")
	check(not sim.use_item(999), "unknown player rejected")
	owner.item = "invert"
	sim.use_item(1)
	check(owner.inverted_until == 0, "owner never inverted")
	check(sim.players[2].inverted_until == sim.rules.effect_duration, "rival inverted for configured duration")
	owner.item = "holes"
	sim.use_item(1)
	check(sim.objects.size() == sim.rules.hole_count, "six holes created")
	check(sim.objects[0].arm_at == 1.0, "holes give warning")
	owner.item = "holes"
	sim.use_item(1)
	check(sim.objects.size() == sim.rules.hole_count, "hole activation replaces previous event")
	owner.item = "enemies"
	sim.use_item(1)
	check(sim.objects.filter(func(o: Dictionary) -> bool: return o.kind == "enemy").size() == 3, "three enemies created")
	var hole: Dictionary = sim.objects.filter(func(o: Dictionary) -> bool: return o.kind == "hole")[0]
	sim.time = 1.2
	owner.position = hole.position
	owner.item = "invert"
	sim._update_objects(0.0)
	check(owner.position == owner.spawn, "hole respawns owner too")
	check(owner.item.is_empty(), "respawn clears item")
	check(owner.protected_until > sim.time, "respawn grants protection")
	var enemy: Dictionary = sim.objects.filter(func(o: Dictionary) -> bool: return o.kind == "enemy")[0]
	owner.position = enemy.position
	var protected_point: Vector2 = owner.position
	sim._update_objects(0.0)
	check(owner.position == protected_point, "protection blocks enemy hit")
	sim.time = 30.0
	sim._update_objects(0.0)
	check(sim.objects.is_empty(), "temporary events expire")

func _victory_and_pickups() -> void:
	var owner = sim.players[1]
	var other = sim.players[2]
	owner.position = Maze.center(Vector2i(3, 3))
	other.position = owner.position
	sim._add_object("crate", owner.position, -1.0)
	sim._update_objects(0.0)
	check(not owner.item.is_empty() and other.item.is_empty(), "simultaneous crate pickup gives exactly one item")
	check(sim.objects.is_empty(), "crate consumed once")
	owner.position = Maze.center(Vector2i(12, 7))
	other.position = owner.position
	sim._check_cetro()
	check(sim.winner == 0, "cetro tie has deterministic winner")
	sim.finish(3)
	check(sim.winner == 0, "winner cannot be overwritten")

func _mountain_rules() -> void:
	var owner = sim.players[1]
	var other = sim.players[2]
	sim._update_summit(3.0)
	check(sim.summit_time == 0, "empty summit has no timer")
	owner.position = Mountain.CENTER
	sim._update_summit(10.0)
	check(sim.summit_time == 10.0 and sim.winner == -1, "exclusive summit advances")
	other.position = Mountain.CENTER
	sim._update_summit(1.0)
	check(sim.summit_time == 0 and sim.summit_slot == -1, "contested summit resets")
	other.position = other.spawn
	sim._update_summit(3.0)
	owner.position = owner.spawn
	sim._update_summit(1.0)
	check(sim.summit_time == 0, "leaving summit resets")
	owner.position = sim.map.spiral[80]
	sim._add_object("crate", owner.position, -1)
	sim._update_objects(0.0)
	check(owner.mass == 2.0 and is_equal_approx(owner.radius, 13.5), "growth increases size and push resistance")
	var old_impulse: Vector2 = owner.impulse
	sim._blast(owner.position, 65, 400)
	check(is_equal_approx((owner.impulse - old_impulse).length(), 200), "growth halves blast impulse")
	owner.impulse = Vector2.ZERO
	owner.grown_until = -1.0
	sim.advance(1.0 / 60)
	check(owner.mass == 1.0 and owner.radius == 10.0, "growth expires")
	owner.position = Vector2(360, 400)
	sim.advance(1.0 / 60)
	check(owner.position == owner.spawn, "fall returns to corner")
	var mine: Dictionary = sim.objects.filter(func(o: Dictionary) -> bool: return o.kind == "mine")[0]
	owner.protected_until = 0.0
	owner.position = mine.position
	sim._update_objects(0.0)
	check(mine.active_at > sim.time, "visible mine enters cooldown after touch")
	check(owner.impulse.length() > 0, "mine applies knockback")
	owner.impulse = Vector2.ZERO
	sim.time = mine.active_at + 0.1
	sim._update_objects(0.0)
	check(owner.impulse.length() > 0, "mine rearms after cooldown")
	owner.position = Mountain.CENTER
	other.position = other.spawn
	sim._update_summit(sim.rules.summit_seconds)
	check(sim.winner == 0, "15 continuous exclusive seconds wins")

func _physics_and_timeout() -> void:
	var owner = sim.players[1]
	var initial: Vector2 = owner.position
	for i in range(100):
		sim.set_input(1, Vector2.LEFT)
		sim.advance(1.0 / 60)
		await physics_frame
	check(owner.position.x >= Maze.ORIGIN.x + Maze.CELL + owner.radius - 0.1, "maze wall blocks player")
	owner.position = initial
	owner.velocity = Vector2.ZERO
	sim.set_input(1, Vector2.RIGHT)
	for i in range(90):
		sim.advance(1.0 / 60)
		await physics_frame
	check(owner.velocity.length() < 0.01, "stale input decelerates to rest")
	var other = sim.players[2]
	owner.position = initial
	other.position = initial + Vector2(16, 0)
	owner.protected_until = 0
	other.protected_until = 0
	sim._collide_players()
	check(owner.position.distance_to(other.position) >= 19.9, "players resolve overlap")
	check(owner.impulse.length() > 0 and other.impulse.length() > 0, "players exchange pushes")

func _network_validation() -> void:
	var session = root.get_node("Session")
	check(session.join("not-an-address", "Test") == ERR_INVALID_PARAMETER, "invalid address rejected before network connection")
	check(session.host("Test", false, 99999) == ERR_INVALID_PARAMETER, "invalid port rejected before opening network socket")
	session.status = "match"
	session.current_map = {"revision": 2}
	session.received_sequence = -1
	var state: Dictionary = sim.snapshot()
	state.revision = 2
	state.sequence = 10
	session._accept_state(state)
	check(session.received_sequence == 10, "new snapshot accepted")
	var older: Dictionary = state.duplicate(true)
	older.sequence = 9
	older.time = -5.0
	session._accept_state(older)
	check(session.current_state.time == state.time, "out of order snapshot cannot rewind game")
	older.sequence = 11
	older.revision = 1
	session._accept_state(older)
	check(session.received_sequence == 10, "old map revision cannot overwrite current map")
	sim.players[1].input_direction = Vector2.RIGHT
	sim.set_input(1, Vector2(INF, 0))
	check(sim.players[1].input_direction == Vector2.RIGHT, "non finite direction rejected")
	sim.set_input(1, Vector2(50, 50))
	check(sim.players[1].input_direction.length() <= 1.001, "input magnitude bounded by server")
	var raw := var_to_bytes(state)
	var encoded := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var decoded := encoded.decompress(raw.size(), FileAccess.COMPRESSION_ZSTD)
	check(decoded == raw, "network compression roundtrip preserves exact state")
	session.leave()
