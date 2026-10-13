extends Node2D
signal map_changed(map: Dictionary)
signal event_occurred(kind: String)
const Maze = preload("res://scripts/modes/maze_generator.gd")
const Mountain = preload("res://scripts/modes/mountain_map.gd")
const Player = preload("res://scripts/players/player.gd")
const ITEMS := ["regenerate", "invert", "holes", "enemies"]
var rules: Resource = preload("res://resources/game_rules.tres")
var map: Dictionary = {}
var players: Dictionary = {}
var objects: Array[Dictionary] = []
var time: float = 0.0
var countdown: float = 3.0
var winner: int = -1
var summit_slot: int = -1
var summit_time: float = 0.0
var next_crate: float = 20.0
var next_bomb: float = 4.0
var revision: int = 0
var next_object_id: int = 0
var rng := RandomNumberGenerator.new()
var walls: Node2D
var practice: bool = false
var announcement: String = ""

func initialize(mode: String, roster: Array, seed_value: int, solo: bool = false) -> void:
	rng.seed = seed_value
	practice = solo
	next_crate = rules.first_crate
	next_bomb = rules.bomb_interval
	map = Maze.generate(seed_value) if mode == "maze" else Mountain.generate()
	revision = 1
	map.revision = revision
	_build_walls()
	var spawns: Array = Maze.spawn_points() if mode == "maze" else map.spawns
	for entry: Dictionary in roster:
		var player = load("res://scenes/players/player.tscn").instantiate()
		player.slot = int(entry.slot)
		player.peer_id = int(entry.id)
		player.spawn = spawns[player.slot]
		player.position = player.spawn
		player.radius = rules.player_radius
		add_child(player)
		players[player.peer_id] = player
	if mode == "mountain":
		for i in range(6):
			_add_object("mine", map.spiral[35 + i * 41], -1.0)
	map_changed.emit(map)

func _build_walls() -> void:
	if walls:
		remove_child(walls)
		walls.queue_free()
	walls = Node2D.new()
	add_child(walls)
	if map.kind != "maze":
		return
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	walls.add_child(body)
	for y in range(Maze.HEIGHT):
		for x in range(Maze.WIDTH):
			if map.cells[Maze.index(Vector2i(x, y))] != 0:
				continue
			var collision := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = Vector2.ONE * Maze.CELL
			collision.shape = shape
			collision.position = Maze.center(Vector2i(x, y))
			body.add_child(collision)

func set_input(peer: int, direction: Vector2) -> void:
	if players.has(peer) and direction.is_finite():
		players[peer].input_direction = direction.limit_length()
		players[peer].input_age = 0.0

func advance(delta: float) -> void:
	if winner >= 0:
		return
	if countdown > 0.0:
		countdown = maxf(0.0, countdown - delta)
		return
	time += delta
	for player in players.values():
		if player.grown_until <= time and player.mass > 1.0:
			player.mass = 1.0
			player.set_radius(rules.player_radius)
		player.step(delta, time, rules)
	_collide_players()
	if map.kind == "mountain":
		for player in players.values():
			if not Mountain.on_path(player.position, map, player.radius * 0.3):
				_respawn(player)
		_update_summit(delta)
		if time >= next_bomb:
			next_bomb += rules.bomb_interval
			var target: Vector2 = map.spiral[rng.randi_range(18, 300)]
			if rng.randf() < 0.5 and not players.is_empty():
				target = players.values()[rng.randi_range(0, players.size() - 1)].position
			var bomb := _add_object("bomb", target, time + rules.bomb_warning + 0.4)
			bomb.arm_at = time + rules.bomb_warning
			bomb.exploded = false
	else:
		_check_cetro()
	if winner >= 0:
		return
	if time >= next_crate:
		next_crate += rules.crate_interval
		var crates := objects.filter(func(object: Dictionary) -> bool: return object.kind == "crate")
		if crates.size() < (rules.max_crates if map.kind == "maze" else 1):
			_add_object("crate", _safe_point(), -1.0)
	_update_objects(delta)

func _collide_players() -> void:
	var list := players.values()
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			var a = list[i]
			var b = list[j]
			if a.protected_until > time or b.protected_until > time:
				continue
			var difference: Vector2 = b.position - a.position
			var overlap: float = a.radius + b.radius - difference.length()
			if overlap <= 0.0:
				continue
			var normal := difference.normalized() if difference.length() > 0.01 else Vector2.RIGHT
			var mass_sum: float = a.mass + b.mass
			a.move_and_collide(-normal * overlap * b.mass / mass_sum)
			b.move_and_collide(normal * overlap * a.mass / mass_sum)
			var closing: float = maxf(0.0, (a.velocity - b.velocity).dot(normal))
			a.impulse -= normal * (rules.push_force + closing * 0.5) / a.mass
			b.impulse += normal * (rules.push_force + closing * 0.5) / b.mass

func _check_cetro() -> void:
	var goal: Vector2 = Maze.center(Vector2i(12, 7))
	var candidates: Array = []
	for player in players.values():
		if player.position.distance_to(goal) < player.radius + 12.0:
			candidates.append(player)
	candidates.sort_custom(func(a, b) -> bool:
		var da: float = a.position.distance_squared_to(goal)
		var db: float = b.position.distance_squared_to(goal)
		return a.slot < b.slot if is_equal_approx(da, db) else da < db)
	if not candidates.is_empty():
		finish(candidates[0].slot)

func _update_summit(delta: float) -> void:
	var occupants: Array = []
	for player in players.values():
		if player.position.distance_to(Mountain.CENTER) <= Mountain.SUMMIT_RADIUS - player.radius * 0.4:
			occupants.append(player.slot)
	if occupants.size() != 1:
		summit_slot = -1
		summit_time = 0.0
		return
	if summit_slot != occupants[0]:
		summit_slot = occupants[0]
		summit_time = 0.0
	summit_time += delta
	if summit_time >= rules.summit_seconds:
		finish(summit_slot)

func finish(slot: int) -> void:
	if winner >= 0:
		return
	winner = slot
	event_occurred.emit("win")

func _respawn(player) -> void:
	# Move invulnerable occupants away before restoring the exact spawn.
	for other in players.values():
		if other == player or other.position.distance_to(player.spawn) > other.radius + rules.player_radius:
			continue
		var candidates := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
		for offset: Vector2 in candidates:
			var point: Vector2 = player.spawn + offset * (other.radius + rules.player_radius + 2.0)
			if _valid_point(point, other.radius):
				other.position = point
				break
	player.respawn(time, rules)
	event_occurred.emit("respawn")

func _valid_point(point: Vector2, clearance: float = 0.0) -> bool:
	if map.kind == "mountain":
		return Mountain.on_path(point, map, clearance * 0.3)
	for offset: Vector2 in [Vector2.ZERO, Vector2(clearance, clearance), Vector2(-clearance, clearance), Vector2(clearance, -clearance), Vector2(-clearance, -clearance)]:
		var cell := Maze.cell_at(point + offset)
		if cell.x < 0 or cell.y < 0 or cell.x >= Maze.WIDTH or cell.y >= Maze.HEIGHT or map.cells[Maze.index(cell)] == 0:
			return false
	return true

func _safe_point() -> Vector2:
	var choices: Array[Vector2] = []
	if map.kind == "maze":
		for y in range(1, Maze.HEIGHT - 1):
			for x in range(1, Maze.WIDTH - 1):
				if map.cells[Maze.index(Vector2i(x, y))] == 1:
					choices.append(Maze.center(Vector2i(x, y)))
	else:
		for i in range(20, 290, 3):
			choices.append(map.spiral[i])
	var safe: Array[Vector2] = []
	for point in choices:
		if point.distance_to(Mountain.CENTER if map.kind == "mountain" else Maze.center(Vector2i(12, 7))) < 55.0:
			continue
		var blocked := false
		for player in players.values():
			if point.distance_to(player.position) < 65.0 or point.distance_to(player.spawn) < 55.0:
				blocked = true
		for object in objects:
			if point.distance_to(object.position) < 32.0:
				blocked = true
		if not blocked:
			safe.append(point)
	return safe[rng.randi_range(0, safe.size() - 1)] if not safe.is_empty() else Vector2(-1000, -1000)

func _add_object(kind: String, point: Vector2, expires: float) -> Dictionary:
	next_object_id += 1
	var object := {"id": next_object_id, "kind": kind, "position": point, "expires": expires, "arm_at": time, "active_at": time}
	if point.x >= 0.0:
		objects.append(object)
		event_occurred.emit("spawn")
	return object

func use_item(peer: int) -> bool:
	if not players.has(peer) or winner >= 0 or countdown > 0.0:
		return false
	var player = players[peer]
	var item: String = player.item
	if item.is_empty():
		return false
	player.item = ""
	match item:
		"regenerate":
			var points: Array = []
			for participant in players.values():
				points.append(participant.position)
			map = Maze.generate(rng.randi(), points, rules.player_radius + 2.0)
			revision += 1
			map.revision = revision
			objects.clear()
			_build_walls()
			map_changed.emit(map)
		"invert":
			for other in players.values():
				if other != player:
					other.inverted_until = time + rules.effect_duration
		"holes", "enemies":
			var kind := "hole" if item == "holes" else "enemy"
			objects = objects.filter(func(object: Dictionary) -> bool: return object.kind != kind)
			var count: int = rules.hole_count if kind == "hole" else rules.enemy_count
			for i in range(count):
				var object := _add_object(kind, _safe_point(), time + rules.effect_duration + (1.0 if kind == "hole" else 0.0))
				object.arm_at = time + (1.0 if kind == "hole" else 0.0)
	announcement = "J%d · %s" % [player.slot + 1, item_name(item)]
	event_occurred.emit("item")
	return true

static func item_name(item: String) -> String:
	return {"regenerate": "Nuevo laberinto", "invert": "Controles invertidos", "holes": "Agujeros", "enemies": "Perseguidores", "growth": "Gigante"}.get(item, "Sin objeto")

func _update_objects(delta: float) -> void:
	var remove: Array[int] = []
	for object in objects:
		if object.expires >= 0.0 and time >= object.expires:
			remove.append(object.id)
			continue
		if object.kind == "enemy":
			_move_enemy(object, delta)
		if object.kind == "bomb" and time >= object.arm_at and not object.exploded:
			object.exploded = true
			_blast(object.position, 65.0, 430.0)
			event_occurred.emit("blast")
		for player in players.values():
			var distance: float = player.position.distance_to(object.position)
			match object.kind:
				"crate":
					if distance < player.radius + 13.0 and player.item.is_empty() and not remove.has(object.id):
						if map.kind == "maze":
							player.item = ITEMS[rng.randi_range(0, ITEMS.size() - 1)]
						else:
							if not _can_grow(player):
								continue
							player.mass = rules.growth_mass
							player.grown_until = time + rules.effect_duration
							player.set_radius(rules.player_radius * rules.growth_scale)
						remove.append(object.id)
						event_occurred.emit("pickup")
				"hole", "enemy":
					if time >= object.arm_at and player.protected_until <= time and distance < player.radius + (12.0 if object.kind == "hole" else 9.0):
						_respawn(player)
				"mine":
					if time >= object.active_at and player.protected_until <= time and distance < player.radius + 9.0:
						object.active_at = time + rules.mine_respawn
						_blast(object.position, 55.0, 460.0)
						event_occurred.emit("blast")
	if not remove.is_empty():
		objects = objects.filter(func(object: Dictionary) -> bool: return not remove.has(object.id))
		event_occurred.emit("remove")

func _can_grow(player) -> bool:
	var radius: float = rules.player_radius * rules.growth_scale
	if not _valid_point(player.position, radius):
		return false
	for other in players.values():
		if other != player and player.position.distance_to(other.position) < radius + other.radius:
			return false
	return true

func _blast(point: Vector2, radius: float, force: float) -> void:
	for player in players.values():
		if player.protected_until > time or player.position.distance_to(point) > radius:
			continue
		var normal: Vector2 = (player.position - point).normalized()
		if normal == Vector2.ZERO:
			normal = Vector2.RIGHT.rotated(float(player.slot) * PI * 0.5)
		player.impulse += normal * force / player.mass

func _move_enemy(object: Dictionary, delta: float) -> void:
	var target = null
	var best := INF
	for player in players.values():
		if player.protected_until > time:
			continue
		var distance: float = player.position.distance_squared_to(object.position)
		if distance < best:
			best = distance
			target = player
	if target == null:
		return
	if not object.has("route") or time >= object.get("repath", 0.0):
		object.route = Maze.route(map.cells, Maze.cell_at(object.position), Maze.cell_at(target.position))
		object.repath = time + 0.5
	var destination: Vector2 = target.position
	if object.route.size() > 1:
		destination = Maze.center(object.route[1])
		if object.position.distance_to(destination) < 3.0:
			object.route.pop_front()
	object.position = object.position.move_toward(destination, 85.0 * delta)

func snapshot() -> Dictionary:
	var states: Array = []
	for player in players.values():
		states.append(player.state())
	var visible_objects: Array = []
	for object in objects:
		var copy: Dictionary = object.duplicate()
		copy.erase("route")
		copy.erase("repath")
		visible_objects.append(copy)
	return {"time": time, "countdown": countdown, "winner": winner, "summit_slot": summit_slot, "summit_time": summit_time, "players": states, "objects": visible_objects, "revision": revision, "announcement": announcement}
