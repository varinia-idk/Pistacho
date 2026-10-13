extends Control
## Fondo animado de los menús: degradado, laberinto tenue que se desplaza y bolas que ruedan y rebotan.

const PlayerView = preload("res://scripts/players/player_view.gd")
const Style = preload("res://scripts/ui/style.gd")
const CELL := 96.0
const BALLS := 5

var _offset := 0.0
var _balls: Array[Dictionary] = []
var _walls := PackedVector2Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7  # Mismo fondo siempre: es decoración.
	# Paredes sueltas de un laberinto imaginario, en coordenadas de celda.
	for i in 90:
		var cell := Vector2(_rng.randi_range(0, 30), _rng.randi_range(0, 16))
		_walls.append(cell)
		_walls.append(cell + (Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.DOWN))
	var colors: Array[Color] = [Color("ff6b57"), Color("4cb4ff"), Color("ffd45c"), Color("c77dff"), Style.MINT]
	for i in BALLS:
		_balls.append({"pos": Vector2(_rng.randf_range(200, 1700), _rng.randf_range(150, 900)),
			"vel": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(60, 120), "color": colors[i], "size": _rng.randf_range(26, 46)})


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_offset = fmod(_offset + delta * 12.0, CELL)
	for ball in _balls:
		ball.pos += ball.vel * delta
		for axis in 2:
			var limit: float = size[axis] - ball.size
			if ball.pos[axis] < ball.size or ball.pos[axis] > limit:
				ball.vel[axis] = -ball.vel[axis]
				ball.pos[axis] = clampf(ball.pos[axis], ball.size, limit)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Style.BG_2, Style.BG_2, Style.BG, Style.BG]))
	var line := Color(Style.LINE, 0.55)
	for i in range(0, _walls.size(), 2):
		var a := _walls[i] * CELL + Vector2(-_offset, _offset * 0.5)
		var b := _walls[i + 1] * CELL + Vector2(-_offset, _offset * 0.5)
		draw_line(a, b, line, 6.0, true)
	# Viñeta: bordes más oscuros, el centro respira.
	for k in 6:
		draw_rect(Rect2(Vector2.ONE * -k * 40.0, Vector2(w, h) + Vector2.ONE * k * 80.0), Color(0, 0, 0, 0.05), false, 80.0)
	for ball in _balls:
		PlayerView.draw_ball(self, ball.pos, ball.size, ball.color, (ball.vel as Vector2).normalized())
