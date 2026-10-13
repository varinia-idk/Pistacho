extends RefCounted
## Piezas de interfaz dibujadas por código (sin imágenes externas).

const PlayerView = preload("res://scripts/players/player_view.gd")
const Style = preload("res://scripts/ui/style.gd")


## Bola de un jugador, del tamaño mínimo del control.
class Ball extends Control:
	var color := Color.WHITE
	var look := Vector2(0.6, 0.8).normalized()

	func _init(ball_color: Color, size_px := 44.0) -> void:
		color = ball_color
		custom_minimum_size = Vector2.ONE * size_px
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		PlayerView.draw_ball(self, size * 0.5, minf(size.x, size.y) * 0.42, color, look)


## Medalla con número de puesto: oro, plata, bronce y gris.
class Medal extends Control:
	var place := 1

	func _init(place_value: int) -> void:
		place = place_value
		custom_minimum_size = Vector2(52.0, 52.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var colors: Array[Color] = [Style.GOLD, Style.SILVER, Style.BRONZE, Style.LINE]
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c, r, colors[mini(place - 1, 3)].darkened(0.3), true, -1.0, true)
		draw_circle(c, r * 0.82, colors[mini(place - 1, 3)], true, -1.0, true)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0.0, c.y + 9.0), str(place), HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Style.INK)


## Corona dorada para el ganador de la partida.
class Crown extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(120.0, 80.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var points := PackedVector2Array([Vector2(w * 0.1, h * 0.9), Vector2(w * 0.05, h * 0.25), Vector2(w * 0.3, h * 0.55),
			Vector2(w * 0.5, h * 0.05), Vector2(w * 0.7, h * 0.55), Vector2(w * 0.95, h * 0.25), Vector2(w * 0.9, h * 0.9)])
		draw_colored_polygon(points, Style.GOLD)
		draw_polyline(points + PackedVector2Array([points[0]]), Style.GOLD.darkened(0.3), 4.0, true)
		for x in [0.05, 0.5, 0.95]:
			draw_circle(Vector2(w * x, h * (0.05 if x == 0.5 else 0.25)), 7.0, Style.GOLD.lightened(0.3), true, -1.0, true)


## Indicador circular del dash: se llena al recargar y brilla cuando está listo.
class DashGauge extends Control:
	var charge := 1.0  ## 0..1; "ready" chocaría con la señal de Node.
	var shielded := false

	func _init() -> void:
		custom_minimum_size = Vector2(150.0, 150.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		var full := charge >= 1.0
		draw_circle(c, r + 6.0, Color(0, 0, 0, 0.35), true, -1.0, true)
		draw_circle(c, r, Style.PANEL, true, -1.0, true)
		if charge > 0.0:
			var sector := PackedVector2Array([c])
			for k in 41:
				sector.append(c + Vector2.from_angle(-PI / 2.0 + TAU * charge * k / 40.0) * r)
			draw_colored_polygon(sector, Style.MINT if full else Color(Style.MINT, 0.35))
		if full:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
			draw_arc(c, r + 3.0 + 4.0 * pulse, 0.0, TAU, 48, Color(Style.MINT_LIGHT, 0.5 + 0.4 * pulse), 4.0, true)
		draw_string(ThemeDB.fallback_font, Vector2(0.0, c.y + 10.0), "DASH", HORIZONTAL_ALIGNMENT_CENTER, size.x, 28,
			Style.INK if full else Style.TEXT)
		if shielded:
			var s := Vector2(size.x - 34.0, 26.0)
			draw_colored_polygon(PackedVector2Array([s + Vector2(0, -22), s + Vector2(20, -14), s + Vector2(17, 10), s + Vector2(0, 24),
				s + Vector2(-17, 10), s + Vector2(-20, -14)]), Color(0.7, 0.95, 1.0))
