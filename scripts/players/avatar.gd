extends "res://scripts/core/motion_visual.gd"
const COLORS := [Color("67e4bc"), Color("ffb366"), Color("a9a0ff"), Color("ff7f9e")]
var data: Dictionary = {}
var clock: float = 0.0
var local: bool = false
var was_animated := false

func update_state(value: Dictionary, stamp: float = 0.0) -> void:
	var respawned: bool = value.get("respawn_serial", 0) != data.get("respawn_serial", 0)
	var appearance_changed: bool = data.is_empty() or value.radius != data.radius or value.slot != data.slot
	data = value
	update_motion(data.position, stamp, respawned)
	if appearance_changed:
		queue_redraw()

func _process(delta: float) -> void:
	advance_motion(delta)
	var animated: bool = not data.is_empty() and (data.protected_until > clock or data.inverted_until > clock)
	if animated or was_animated:
		queue_redraw()
	was_animated = animated

func _draw() -> void:
	if data.is_empty():
		return
	var radius: float = data.radius
	var color: Color = COLORS[int(data.slot)]
	var protected: bool = data.protected_until > clock
	if protected and int(clock * 10.0) % 2 == 0:
		color.a = 0.35
	if local:
		draw_arc(Vector2.ZERO, radius + 6, 0, TAU, 32, Color(color, 0.65), 1.5, true)
	draw_circle(Vector2(0, 3), radius + 1, Color(0, 0, 0, 0.3))
	draw_circle(Vector2.ZERO, radius + 1.5, Color("0a2028"))
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2(-radius * 0.25, -radius * 0.35), radius * 0.44, Color(1, 1, 1, 0.18))
	for x in [-0.32, 0.32]:
		draw_circle(Vector2(x * radius, -radius * 0.12), 2.5, Color("112c36"))
	draw_arc(Vector2(0, radius * 0.16), radius * 0.34, 0.15, PI - 0.15, 12, Color("112c36"), 1.4, true)
	draw_string(ThemeDB.fallback_font, Vector2(-4, -radius - 10), str(int(data.slot) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	if data.inverted_until > clock:
		draw_arc(Vector2.ZERO, radius + 3.0, clock * 2.0, clock * 2.0 + PI * 1.5, 24, Color("ff7f9e"), 2.0, true)
