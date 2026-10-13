extends Control
signal direction_changed(direction: Vector2)
var value := Vector2.ZERO
var finger: int = -1
var dragging: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_input_event)

func _input_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and finger == -1:
			finger = event.index
			dragging = true
			_update(event.position)
		elif not event.pressed and event.index == finger:
			_reset()
	elif event is InputEventScreenDrag and event.index == finger:
		_update(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			_update(event.position)
		else:
			_reset()
	elif event is InputEventMouseMotion and dragging and finger == -1:
		_update(event.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset()

func _update(point: Vector2) -> void:
	value = ((point - size * 0.5) / 48.0).limit_length()
	direction_changed.emit(value)
	queue_redraw()

func _reset() -> void:
	dragging = false
	finger = -1
	value = Vector2.ZERO
	direction_changed.emit(value)
	queue_redraw()

func _draw() -> void:
	draw_circle(size * 0.5, 55, Color(0.4, 0.9, 0.75, 0.08))
	draw_arc(size * 0.5, 54, 0, TAU, 48, Color(0.4, 0.9, 0.75, 0.35), 2, true)
	draw_circle(size * 0.5 + value * 38, 19, Color(0.4, 0.9, 0.75, 0.65))
