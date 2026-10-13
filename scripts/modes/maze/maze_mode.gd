extends "res://scripts/core/game_mode.gd"
## Laberinto: todos salen de la esquina superior izquierda; gana quien toque la meta opuesta.

const MazeGen = preload("res://scripts/modes/maze/maze_generator.gd")
const WALL_VISUAL := 4.0
const FLOOR := Color(0.07, 0.11, 0.16)
const ROOM := Color(0.11, 0.17, 0.24)
const WALL := Color(0.86, 0.91, 0.95)
const GOAL := Color(1.0, 0.8, 0.25)
const WARN := Color(1.0, 0.5, 0.12)
const HOLE_RIM := Color(0.2, 0.15, 0.12)

var data: MazeGen.Data
var cell := 72.0
var thick := 6.0
var player_radius := 20.0
var hole_radius := 30.0
var hole_offset := 0.0
var hole_centers: Dictionary[int, Vector2] = {}
var goal_point := Vector2.ZERO
var goal_radius := 30.0
var dist_start := PackedInt32Array()
var dist_goal := PackedInt32Array()
var segments := PackedVector2Array()  ## Pares (inicio, fin) de paredes fusionadas.
var finish_order: Array[int] = []
var history: Dictionary[int, Array] = {}
var _effects := Node2D.new()
var _walls: StaticBody2D
var _bot_run: Dictionary[int, int] = {}
var _bot_axis: Dictionary[int, Vector2] = {}
var _bot_hole: Dictionary[int, int] = {}


func title() -> String:
	return "Laberinto"


func setup(_seed_value: int) -> void:
	super(_seed_value)
	var cfg := Config.snapshot()
	player_radius = cfg["player_radius"]
	thick = MazeGen.wall_thickness(cfg)
	cell = MazeGen.cell_size(cfg)
	var size := MazeGen.grid_size(cfg)
	data = MazeGen.generate(seed_value, size.x, size.y, cfg)
	dist_start = MazeGen.distances(data, data.start)
	dist_goal = MazeGen.distances(data, data.goal)
	# El centro del jugador cae si está a menos de (radio_agujero - 0.5·radio) del centro.
	# El desplazamiento deja una franja segura de hole_pass px al otro lado del pasillo.
	hole_radius = cfg["hole_radius"] * player_radius
	var half_clear := (cell - thick) * 0.5
	hole_offset = clampf(cfg["hole_pass"] + hole_radius + 0.5 * player_radius - half_clear, 0.0, half_clear)
	for i: int in data.holes:
		hole_centers[i] = cell_center(data.cell_of(i)) + _across(i) * hole_offset * data.holes[i]
	goal_point = Vector2(data.cols - 1, data.rows - 1) * cell
	goal_radius = cell * 0.45
	_build_segments()
	_effects.name = "Effects"
	_effects.draw.connect(_draw_effects)
	add_child(_effects)
	queue_redraw()


func build_physics() -> void:
	var body := StaticBody2D.new()
	_walls = body
	body.name = "Walls"
	body.collision_layer = Player.LAYER_WALLS
	body.collision_mask = 0
	body.physics_material_override = PhysicsMaterial.new()
	Player.configure_wall_material(body.physics_material_override)
	Config.changed.connect(_on_config_changed)
	for i in range(0, segments.size(), 2):
		var from := segments[i]
		var to := segments[i + 1]
		var shape := RectangleShape2D.new()
		if is_equal_approx(from.y, to.y):
			shape.size = Vector2(to.x - from.x + thick, thick)
		else:
			shape.size = Vector2(thick, to.y - from.y + thick)
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = (from + to) * 0.5
		body.add_child(collider)
	add_child(body)


func _on_config_changed(_key: String) -> void:
	Player.configure_wall_material(_walls.physics_material_override)


func spawn_points() -> Array[Vector2]:
	return [cell_center(Vector2i(0, 0)), cell_center(Vector2i(1, 0)), cell_center(Vector2i(0, 1)), cell_center(Vector2i(1, 1))]


func map_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(data.cols, data.rows) * cell)


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cell


func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(point.x / cell), 0, data.cols - 1), clampi(floori(point.y / cell), 0, data.rows - 1))


## Eje perpendicular al pasillo recto de la celda i.
func _across(i: int) -> Vector2:
	return Vector2.RIGHT if data.straight_axis(data.cell_of(i)) == 0 else Vector2.DOWN


## Centro de la franja segura junto al agujero.
func pass_point(i: int) -> Vector2:
	var wall_side := (cell - thick) * 0.5 - player_radius
	var hole_side := hole_offset - (hole_radius - 0.5 * player_radius)
	return cell_center(data.cell_of(i)) + _across(i) * (hole_side - wall_side) * 0.5 * data.holes[i]


## Frente del colapso en pasos BFS desde la salida; lead adelanta el aviso.
func collapse_front(lead: float) -> float:
	var reach := (time - Config.value("collapse_start") + lead) * Config.value("collapse_rate")
	return minf(reach, float(dist_start[data.index(data.goal)] - 3))


func physics_step(delta: float) -> void:
	super(delta)
	var front := collapse_front(0.0)
	# La reaparición se aplica tras la caída y debe seguir a salvo al acabar la invulnerabilidad.
	var safe_front := collapse_front(Config.value("warn_time") + Config.value("fall_time") + Config.value("invuln_time"))
	var fall_limit := hole_radius - 0.5 * player_radius
	for player in players:
		if player.state != Player.State.ALIVE:
			continue
		var c := cell_at(player.position)
		_track(player.slot, c)
		if finish_order.is_empty() and player.position.distance_to(goal_point) < goal_radius:
			finish_order.append(player.slot)
			continue
		if player.is_invulnerable():
			continue
		var in_hole := false
		for i: int in hole_centers:
			if player.position.distance_to(hole_centers[i]) < fall_limit:
				in_hole = true
				break
		if in_hole:
			player.start_fall(time, _respawn_back(player.slot, safe_front))
		elif dist_start[data.index(c)] < front:
			player.start_fall(time, _respawn_forward(c, safe_front))


func get_winner() -> int:
	return finish_order[0] if not finish_order.is_empty() else -1


func ranking() -> Array[int]:
	var result: Array[int] = finish_order.duplicate()
	var rest: Array[Player] = []
	for player in players:
		if not result.has(player.slot):
			rest.append(player)
	rest.sort_custom(func(a: Player, b: Player) -> bool:
		var da := dist_goal[data.index(cell_at(a.position))]
		var db := dist_goal[data.index(cell_at(b.position))]
		return da < db or (da == db and a.slot < b.slot))
	for player in rest:
		result.append(player.slot)
	return result


func _track(slot: int, c: Vector2i) -> void:
	if not history.has(slot):
		history[slot] = []
	var trail: Array = history[slot]
	if trail.is_empty() or trail.back() != c:
		trail.append(c)
		if trail.size() > 48:
			trail.pop_front()


## ~N celdas atrás en el historial, sin agujeros ni zonas de colapso.
func _respawn_back(slot: int, safe_front: float) -> Vector2:
	var trail: Array = history.get(slot, [])
	var wanted := Config.count("respawn_back")
	var chosen := Vector2i(-1, -1)
	var counted := 0
	for k in range(trail.size() - 2, -1, -1):
		var c: Vector2i = trail[k]
		var i := data.index(c)
		if data.holes.has(i) or dist_start[i] < safe_front:
			continue
		chosen = c
		counted += 1
		if counted >= wanted:
			break
	if chosen.x < 0:
		return _respawn_forward(trail.back() if not trail.is_empty() else data.start, safe_front)
	return cell_center(chosen)


## Primera celda segura avanzando hacia la meta, por delante del aviso de colapso.
func _respawn_forward(from: Vector2i, safe_front: float) -> Vector2:
	var c := from
	for guard in data.walls.size():
		var i := data.index(c)
		if dist_start[i] >= safe_front + 1.0 and not data.holes.has(i):
			break
		var next := _next_toward_goal(c)
		if next == c:
			break
		c = next
	return cell_center(c)


func _next_toward_goal(c: Vector2i) -> Vector2i:
	var here := dist_goal[data.index(c)]
	for dir in 4:
		if data.is_open(c, dir):
			var next := c + MazeGen.DIRS[dir]
			if dist_goal[data.index(next)] == here - 1:
				return next
	return c


func bot_desired_velocity(player: Player) -> Vector2:
	var c := cell_at(player.position)
	var i := data.index(c)
	var max_speed := Config.value("max_speed") * lerpf(0.55, 1.0, Config.value("bot_skill"))
	_bot_run[player.slot] = 0
	if dist_goal[i] <= 1:
		return (goal_point - player.position).normalized() * max_speed * 0.6
	var next := _next_toward_goal(c)
	var dir := next - c
	var run := 1
	var probe := next
	while run < 8:
		var after := _next_toward_goal(probe)
		if after == probe or after - probe != dir:
			break
		probe = after
		run += 1
	var hole := -1
	if data.holes.has(i):
		hole = i
	elif data.holes.has(data.index(next)):
		hole = data.index(next)
	var axis := Vector2(dir)
	var across := axis.orthogonal()
	var corner := Config.value("bot_corner") * Config.value("max_speed")
	var brake := Config.value("tilt_accel") * 0.7
	var to_turn := maxf((cell_center(probe) - player.position).dot(axis), 0.0)
	var speed := minf(max_speed, sqrt(corner * corner + 2.0 * brake * to_turn))
	var lane := cell_center(c)
	if hole >= 0:
		lane = pass_point(hole)
		speed = minf(speed, corner)
	_bot_run[player.slot] = run
	_bot_axis[player.slot] = axis
	_bot_hole[player.slot] = hole
	var lateral := (lane - player.position).dot(across)
	return axis * speed + across * clampf(lateral * 6.0, -max_speed, max_speed)


## Válido tras bot_desired_velocity en el mismo paso.
func bot_wants_dash(player: Player) -> bool:
	if _bot_run.get(player.slot, 0) < 4 or _bot_hole.get(player.slot, -1) >= 0:
		return false
	var axis: Vector2 = _bot_axis[player.slot]
	var speed := player.linear_velocity.length()
	return speed > 120.0 and player.linear_velocity.dot(axis) > 0.95 * speed


func _build_segments() -> void:
	segments.clear()
	for y in data.rows + 1:
		var start := -1
		for x in data.cols + 1:
			var wall := x < data.cols and _wall_above(x, y)
			if wall and start < 0:
				start = x
			elif not wall and start >= 0:
				segments.append(Vector2(start, y) * cell)
				segments.append(Vector2(x, y) * cell)
				start = -1
	for x in data.cols + 1:
		var start := -1
		for y in data.rows + 1:
			var wall := y < data.rows and _wall_left(x, y)
			if wall and start < 0:
				start = y
			elif not wall and start >= 0:
				segments.append(Vector2(x, start) * cell)
				segments.append(Vector2(x, y) * cell)
				start = -1


func _wall_above(x: int, y: int) -> bool:
	if y == data.rows:
		return not data.is_open(Vector2i(x, y - 1), 2)
	return not data.is_open(Vector2i(x, y), 0)


func _wall_left(x: int, y: int) -> bool:
	if x == data.cols:
		return not data.is_open(Vector2i(x - 1, y), 1)
	return not data.is_open(Vector2i(x, y), 3)


func _process(_delta: float) -> void:
	_effects.queue_redraw()


func _draw() -> void:
	draw_rect(map_rect(), FLOOR)
	draw_rect(Rect2(Vector2.ZERO, Vector2(2, 2) * cell), ROOM)
	draw_rect(Rect2(Vector2(data.cols - 2, data.rows - 2) * cell, Vector2(2, 2) * cell), ROOM.lerp(GOAL, 0.15))
	# Agujeros recortados al interior de su celda: lo dibujado es exactamente lo alcanzable.
	for i: int in hole_centers:
		var interior := Rect2(Vector2(data.cell_of(i)) * cell, Vector2.ONE * cell).grow(-thick * 0.5)
		_draw_clipped_circle(hole_centers[i], hole_radius, interior, HOLE_RIM)
		_draw_clipped_circle(hole_centers[i], hole_radius - 0.5 * player_radius, interior, Color.BLACK)
	for i in range(0, segments.size(), 2):
		var extend := (segments[i + 1] - segments[i]).normalized() * WALL_VISUAL * 0.5
		draw_line(segments[i] - extend, segments[i + 1] + extend, WALL, WALL_VISUAL, true)


func _draw_clipped_circle(center: Vector2, radius: float, clip: Rect2, color: Color) -> void:
	var circle := PackedVector2Array()
	for k in 40:
		circle.append(center + Vector2.from_angle(TAU * k / 40.0) * radius)
	var box := PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)])
	for polygon in Geometry2D.intersect_polygons(circle, box):
		draw_colored_polygon(polygon, color)


func _draw_effects() -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	# Meta.
	_effects.draw_circle(goal_point, goal_radius * (1.0 + 0.08 * pulse), Color(GOAL, 0.25), true, -1.0, true)
	var star := PackedVector2Array()
	for k in 10:
		var r := goal_radius * (0.8 if k % 2 == 0 else 0.38)
		star.append(goal_point + Vector2.from_angle(-PI / 2.0 + TAU * k / 10.0) * r)
	_effects.draw_colored_polygon(star, GOAL)
	# Colapso: aviso naranja = exactamente las celdas que caerán; negro = ya colapsadas.
	var front := collapse_front(0.0)
	var warn_front := collapse_front(Config.value("warn_time"))
	if warn_front <= 0.0:
		return
	for i in dist_start.size():
		var d := dist_start[i]
		if d >= warn_front:
			continue
		var rect := Rect2(Vector2(data.cell_of(i)) * cell, Vector2.ONE * cell)
		if d < front:
			_effects.draw_rect(rect, Color.BLACK)
		else:
			_effects.draw_rect(rect, Color(WARN, 0.25 + 0.35 * pulse))
			var center := rect.get_center()
			for k in 3:
				var tip := center + Vector2.from_angle(float((i * 97 + k * 131) % 360) * PI / 180.0) * cell * 0.45
				_effects.draw_line(center, tip, WARN, 2.0, true)
