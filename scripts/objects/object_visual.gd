extends "res://scripts/core/motion_visual.gd"
var data: Dictionary = {}
var clock: float = 0.0
var phase := -1
var box_style: StyleBoxFlat

func update_state(value: Dictionary, stamp: float = 0.0) -> void:
	data = value
	update_motion(value.position, stamp)

func _process(delta: float) -> void:
	advance_motion(delta)
	if data.is_empty():
		return
	var next_phase := int(clock >= data.get("arm_at", 0.0)) + int(clock >= data.get("active_at", 0.0)) * 2 + int(clock >= data.get("active_at", 0.0) - 1.0) * 4
	if phase != next_phase or data.kind in ["crate", "bomb"]:
		queue_redraw()
	phase = next_phase

func _draw() -> void:
	if data.is_empty():
		return
	match data.kind:
		"crate":
			var bob := sin(clock * 4.0) * 2.0
			draw_circle(Vector2(0, 5), 14, Color(0, 0, 0, 0.2))
			draw_style_box(_box(), Rect2(-12, -14 + bob, 24, 24))
			draw_string(ThemeDB.fallback_font, Vector2(-5, 4 + bob), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("283341"))
		"hole":
			if clock < data.arm_at:
				draw_arc(Vector2.ZERO, 14, 0, TAU, 24, Color("ffb366"), 2, true)
			else:
				draw_circle(Vector2.ZERO, 14, Color("445568"))
				draw_circle(Vector2.ZERO, 11, Color("060e19"))
				draw_arc(Vector2(0, 1), 9, 0, PI, 16, Color("7961a6"), 2, true)
		"enemy":
			draw_circle(Vector2.ZERO, 11, Color("ff7f9e"))
			draw_colored_polygon(PackedVector2Array([Vector2(-10, 3), Vector2(-10, 14), Vector2(-5, 9), Vector2(0, 14), Vector2(5, 9), Vector2(10, 14), Vector2(10, 3)]), Color("ff7f9e"))
			for x in [-4, 4]:
				draw_circle(Vector2(x, -1), 3, Color.WHITE)
				draw_circle(Vector2(x, 0), 1.4, Color("182539"))
		"bomb":
			if data.get("exploded", false):
				draw_circle(Vector2.ZERO, 65, Color(1, 0.65, 0.35, 0.3))
				draw_arc(Vector2.ZERO, 65, 0, TAU, 48, Color("ffb366"), 3, true)
			else:
				draw_circle(Vector2.ZERO, 65, Color(1, 0.4, 0.4, 0.08 + 0.05 * sin(clock * 18)))
				draw_arc(Vector2.ZERO, 65, 0, TAU, 48, Color("ff7f9e"), 1.5, true)
				draw_line(Vector2(-9, 0), Vector2(9, 0), Color("ff7f9e"), 2)
				draw_line(Vector2(0, -9), Vector2(0, 9), Color("ff7f9e"), 2)
				var height: float = maxf(0, data.arm_at - clock) * 90.0
				draw_circle(Vector2(0, -height), 9, Color("1b2435"))
				draw_arc(Vector2(0, -height), 10, 0, TAU, 20, Color("ffb366"), 2, true)
		"mine":
			var active: bool = clock >= data.active_at
			var soon: bool = clock >= data.active_at - 1.0
			if not active and not soon:
				draw_arc(Vector2.ZERO, 8, 0, TAU, 16, Color("576578"), 1, true)
				return
			var color := Color("ffb366") if active else Color("8f7c71")
			for i in range(8):
				var direction := Vector2.RIGHT.rotated(float(i) * TAU / 8.0)
				draw_line(direction * 5, direction * 11, color, 2, true)
			draw_circle(Vector2.ZERO, 7, Color("2c3044"))
			draw_circle(Vector2.ZERO, 3, color)

func _box() -> StyleBoxFlat:
	if box_style:
		return box_style
	var box := StyleBoxFlat.new()
	box.bg_color = Color("fbd88c")
	box.corner_radius_top_left = 5
	box.corner_radius_top_right = 5
	box.corner_radius_bottom_left = 5
	box.corner_radius_bottom_right = 5
	box.border_color = Color("fff0ca")
	box.set_border_width_all(2)
	box_style = box
	return box
