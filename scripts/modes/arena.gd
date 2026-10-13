extends Node2D
const Maze = preload("res://scripts/modes/maze_generator.gd")
const Mountain = preload("res://scripts/modes/mountain_map.gd")
const Avatar = preload("res://scripts/players/avatar.gd")
const ObjectVisual = preload("res://scripts/objects/object_visual.gd")
const AvatarScene = preload("res://scenes/players/avatar.tscn")
const ObjectScene = preload("res://scenes/objects/object_visual.tscn")
var map: Dictionary = {}
var state: Dictionary = {}
var avatars: Dictionary = {}
var visuals: Dictionary = {}
var local_peer: int = 1
var local_simulation := false
var summit_visual: Node2D
var elapsed: float = 0.0
var rules: Resource = preload("res://resources/game_rules.tres")

func _ready() -> void:
	summit_visual = Node2D.new()
	add_child(summit_visual)
	summit_visual.draw.connect(_draw_summit)

func set_map(value: Dictionary) -> void:
	map = value
	for visual in visuals.values():
		visual.queue_free()
	visuals.clear()
	if is_instance_valid(summit_visual):
		summit_visual.queue_redraw()
	queue_redraw()

func set_state(value: Dictionary) -> void:
	state = value
	elapsed = state.time
	if not map.is_empty() and map.kind == "mountain":
		summit_visual.queue_redraw()
	var stamp := float(state.time) - float(state.countdown)
	var active_players: Array = []
	for player: Dictionary in state.players:
		active_players.append(player.id)
		if not avatars.has(player.id):
			var avatar = AvatarScene.instantiate()
			avatar.z_index = 5
			add_child(avatar)
			avatars[player.id] = avatar
		avatars[player.id].local = player.id == local_peer
		avatars[player.id].local_simulation = local_simulation
		avatars[player.id].update_state(player, stamp)
	for id in avatars.keys():
		if not active_players.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	var active_objects: Array = []
	for object: Dictionary in state.objects:
		active_objects.append(object.id)
		if not visuals.has(object.id):
			var visual = ObjectScene.instantiate()
			visual.z_index = 2
			add_child(visual)
			visuals[object.id] = visual
		visuals[object.id].local_simulation = local_simulation
		visuals[object.id].update_state(object, stamp)
	for id in visuals.keys():
		if not active_objects.has(id):
			visuals[id].queue_free()
			visuals.erase(id)

func _process(delta: float) -> void:
	elapsed += delta
	for avatar in avatars.values():
		avatar.clock = elapsed
	for visual in visuals.values():
		visual.clock = elapsed

func _draw() -> void:
	if map.is_empty():
		return
	if map.kind == "maze":
		_draw_maze()
	else:
		_draw_mountain()

func _draw_maze() -> void:
	draw_style_box(_panel(Color("172c39"), 16), Rect2(Maze.ORIGIN - Vector2(10, 10), Vector2(920, 560)))
	for y in range(Maze.HEIGHT):
		for x in range(Maze.WIDTH):
			var pos := Maze.ORIGIN + Vector2(x, y) * Maze.CELL
			if map.cells[Maze.index(Vector2i(x, y))] == 0:
				draw_style_box(_panel(Color("304b56"), 4), Rect2(pos + Vector2.ONE, Vector2.ONE * (Maze.CELL - 2)))
				draw_line(pos + Vector2(5, 4), pos + Vector2(Maze.CELL - 5, 4), Color("426470"), 2, true)
			else:
				draw_circle(pos + Vector2.ONE * 18, 1, Color("29434c"))
	var points := Maze.spawn_points()
	for i in range(4):
		draw_arc(points[i], 15, 0, TAU, 32, Color(Avatar.COLORS[i], 0.6), 2, true)
	var goal := Maze.center(Vector2i(12, 7))
	draw_circle(goal, 22, Color(1, 0.85, 0.5, 0.12))
	draw_line(goal + Vector2(0, -7), goal + Vector2(0, 13), Color("fbd88c"), 4, true)
	draw_colored_polygon(PackedVector2Array([goal + Vector2(0, -18), goal + Vector2(8, -10), goal + Vector2(0, -2), goal + Vector2(-8, -10)]), Color("fbd88c"))

func _draw_mountain() -> void:
	for i in range(5):
		var radius := 246.0 - i * 48.0
		draw_circle(Mountain.CENTER + Vector2(0, 9), radius, Color("101e2c"))
		draw_circle(Mountain.CENTER, radius, Color("1a2e3a").lightened(float(i) * 0.035))
		draw_arc(Mountain.CENTER, radius, 0, TAU, 96, Color("304755"), 1, true)
	for lane: Array in map.lanes:
		_draw_path(lane)
	_draw_path(map.spiral)
	var points: Array = map.spawns
	for i in range(4):
		draw_arc(points[i], 15, 0, TAU, 32, Avatar.COLORS[i], 2, true)
	draw_circle(Mountain.CENTER, Mountain.SUMMIT_RADIUS, Color("fbd88c"))
	draw_circle(Mountain.CENTER, 22, Color("536061"))
	var crown := PackedVector2Array([Vector2(-12, 6), Vector2(-15, -9), Vector2(-6, -2), Vector2(0, -13), Vector2(6, -2), Vector2(15, -9), Vector2(12, 6)])
	for i in range(crown.size()):
		crown[i] += Mountain.CENTER
	draw_colored_polygon(crown, Color("fbd88c"))

func _draw_summit() -> void:
	if map.get("kind", "") == "mountain" and state.get("summit_slot", -1) >= 0:
		var progress: float = state.summit_time / rules.summit_seconds
		summit_visual.draw_arc(Mountain.CENTER, 32, -PI * 0.5, -PI * 0.5 + TAU * minf(progress, 1.0), 64, Avatar.COLORS[int(state.summit_slot)], 4, true)

func _draw_path(points: Array) -> void:
	var packed := PackedVector2Array(points)
	draw_polyline(packed, Color("101b27"), Mountain.HALF_WIDTH * 2 + 5, true)
	draw_polyline(packed, Color("637d7d"), Mountain.HALF_WIDTH * 2, true)
	draw_polyline(packed, Color("a2b3a0"), Mountain.HALF_WIDTH * 2 - 5, true)

func _panel(color: Color, radius: int) -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = color
	panel.corner_radius_top_left = radius
	panel.corner_radius_top_right = radius
	panel.corner_radius_bottom_left = radius
	panel.corner_radius_bottom_right = radius
	return panel
