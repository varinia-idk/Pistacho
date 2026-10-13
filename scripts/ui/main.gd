extends Control
const Tilt = preload("res://scripts/input/tilt_input.gd")
const Sounds = preload("res://scripts/core/sound_bank.gd")
const Arena = preload("res://scripts/modes/arena.gd")
const TouchStick = preload("res://scripts/ui/touch_stick.gd")
const Avatar = preload("res://scripts/players/avatar.gd")
const Simulation = preload("res://scripts/core/match_simulation.gd")
const MINT := Color("67e4bc")
const WHITE := Color("edf4ef")
const MUTED := Color("94aab3")
var session
var tilt: Node
var sounds: Node
var design: Node2D
var screen: Control
var arena: Node2D
var name_value: String = "Jugador"
var address_value: String = "192.168.1.2"
var port_value: String = "24567"
var timer_label: Label
var state_label: Label
var sensor_label: Label
var item_button: Button
var touch_toggle: Button
var player_labels: Dictionary = {}
var stick: Control
var shown_status: String = ""
var notification_time: float = 0.0
var last_announcement: String = ""
var calibration_dot: Control
var rules: Resource = preload("res://resources/game_rules.tres")

func _ready() -> void:
	# UI layout changes per render frame; only moving game visuals opt into interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme_value := Theme.new()
	theme_value.default_font_size = 20
	theme = theme_value
	session = get_node("/root/Session")
	tilt = Tilt.new()
	add_child(tilt)
	session.tilt = tilt
	sounds = Sounds.new()
	add_child(sounds)
	session.sound_requested.connect(sounds.play)
	session.changed.connect(_rebuild)
	session.map_received.connect(_receive_map)
	session.state_received.connect(_receive_state)
	design = Node2D.new()
	add_child(design)
	resized.connect(_resize)
	_rebuild()
	_resize()
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_keep_on(true)

func _resize() -> void:
	if not is_instance_valid(design):
		return
	var usable := Rect2(Vector2.ZERO, size)
	if OS.has_feature("mobile"):
		var physical := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if physical.x > 0 and physical.y > 0 and safe.size.x > 0:
			usable = Rect2(safe.position * size / physical, safe.size * size / physical)
	var factor := minf(usable.size.x / 1280.0, usable.size.y / 720.0)
	design.scale = Vector2.ONE * factor
	design.position = usable.position + (usable.size - Vector2(1280, 720) * factor) * 0.5
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0c1925"))
	# One batched draw instead of a separate polygon/draw call for every background dot.
	var dots := PackedVector2Array()
	for x in range(0, int(size.x), 48):
		for y in range(0, int(size.y), 48):
			dots.append(Vector2(x - 0.5, y))
			dots.append(Vector2(x + 0.5, y))
	draw_multiline(dots, Color("1b2c39"), 2.0)
	draw_circle(Vector2(size.x * 0.15, size.y * 0.85), 240, Color(0.12, 0.3, 0.31, 0.16))
	draw_circle(Vector2(size.x * 0.9, size.y * 0.12), 220, Color(0.33, 0.27, 0.43, 0.12))

func _rebuild() -> void:
	if not is_instance_valid(design):
		return
	for child in design.get_children():
		design.remove_child(child)
		child.queue_free()
	screen = Control.new()
	screen.size = Vector2(1280, 720)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.add_child(screen)
	arena = null
	timer_label = null
	sensor_label = null
	state_label = null
	item_button = null
	touch_toggle = null
	stick = null
	calibration_dot = null
	player_labels.clear()
	shown_status = session.status
	match shown_status:
		"menu", "connecting": _menu()
		"lobby": _lobby()
		"match", "results": _game()

func _menu() -> void:
	_label("PISTACHO", Vector2(72, 45), 24, MINT)
	_label("Inclina. Compite.\nConquista.", Vector2(72, 132), 62, WHITE)
	_label("Un teléfono, un personaje.\nHasta cuatro amigos en la misma red Wi-Fi.", Vector2(76, 305), 22, MUTED)
	_panel(Rect2(76, 416, 525, 168), Color("162b37"))
	_label("01   LABERINTO", Vector2(100, 437), 18, MINT)
	_label("Encuentra el cetro. Cambia las reglas.", Vector2(100, 467), 19)
	_label("02   REY DE LA MONTAÑA", Vector2(100, 516), 18, Color("fbd88c"))
	_label("Una cima. Quince segundos de gloria.", Vector2(100, 546), 19)
	_panel(Rect2(690, 98, 508, 545), Color("152936"))
	_label("VAMOS A JUGAR", Vector2(726, 127), 28)
	_label("Tu nombre", Vector2(728, 181), 16, MUTED)
	var name_box := _field(name_value, Rect2(726, 209, 432, 44))
	name_box.max_length = 18
	name_box.text_changed.connect(func(value: String): name_value = value)
	_button("Crear sala", Rect2(726, 274, 432, 52), func(): _host(false), true)
	_label("Unirse por dirección IP", Vector2(728, 348), 16, MUTED)
	var address := _field(address_value, Rect2(726, 375, 305, 44))
	address.text_changed.connect(func(value: String): address_value = value)
	var port := _field(port_value, Rect2(1041, 375, 117, 44))
	port.text_changed.connect(func(value: String): port_value = value)
	_button("Conectar", Rect2(726, 438, 432, 48), _join)
	_button("Practicar en solitario", Rect2(726, 512, 432, 48), func(): _host(true))
	_label("Sin cuentas · Sin servidor externo", Vector2(757, 587), 15, MUTED)
	_label(session.message, Vector2(76, 617), 18, Color("ffb366"), Vector2(520, 60))
	_label("WASD / flechas en escritorio  ·  Inclinación en Android", Vector2(76, 676), 15, MUTED)
	if session.status == "connecting":
		_panel(Rect2(350, 250, 580, 220), Color("203943"))
		_label("Conectando con la sala…", Vector2(395, 295), 29)
		_button("Cancelar", Rect2(420, 380, 440, 50), func(): session.leave())

func _join() -> void:
	if not port_value.is_valid_int():
		session.message = "Introduce un puerto numérico."
		_rebuild()
		return
	session.join(address_value.strip_edges(), name_value, int(port_value))

func _host(solo: bool) -> void:
	if not port_value.is_valid_int():
		session.message = "Introduce un puerto numérico."
		_rebuild()
		return
	session.host(name_value, solo, int(port_value))

func _lobby() -> void:
	_label("PISTACHO / SALA", Vector2(48, 32), 22, MINT)
	_button("Salir", Rect2(1110, 25, 124, 44), func(): session.leave())
	_label("Preparados para competir", Vector2(48, 96), 40)
	var connection: String = "Práctica individual" if session.practice else "IP: %s   ·   UDP %s" % [session.local_addresses() if session.is_host() else address_value, port_value]
	_label(connection, Vector2(50, 155), 18, MUTED, Vector2(1180, 50))
	_panel(Rect2(48, 217, 570, 380), Color("152936"))
	for i in range(4):
		var y := 239 + i * 78
		var entry: Dictionary = {}
		for candidate: Dictionary in session.roster:
			if candidate.slot == i:
				entry = candidate
		_panel(Rect2(68, y, 530, 64), Color("1d3540"))
		_label("%02d" % (i + 1), Vector2(87, y + 15), 25, Avatar.COLORS[i])
		_label(entry.get("name", "Esperando jugador…"), Vector2(145, y + 17), 22, WHITE if not entry.is_empty() else MUTED)
		_label("LISTO" if entry.get("ready", false) else "—", Vector2(491, y + 20), 16, MINT)
	_label("MODO DE JUEGO", Vector2(660, 220), 16, MUTED)
	var maze_button := _button("Laberinto", Rect2(660, 253, 260, 50), func(): session.choose_mode("maze"), session.mode == "maze")
	var mountain_button := _button("Rey de la montaña", Rect2(936, 253, 296, 50), func(): session.choose_mode("mountain"), session.mode == "mountain")
	maze_button.disabled = not session.is_host()
	mountain_button.disabled = not session.is_host()
	_label("Calibra y mantenlo quieto medio segundo.\nBasta una inclinación pequeña para moverte.", Vector2(660, 330), 21, WHITE)
	_button("Calibrar posición neutral", Rect2(660, 405, 360, 46), func(): tilt.calibrate())
	calibration_dot = Control.new()
	calibration_dot.position = Vector2(1090, 424)
	calibration_dot.draw.connect(func():
		calibration_dot.draw_arc(Vector2.ZERO, 28, 0, TAU, 32, MUTED, 1.5, true)
		calibration_dot.draw_circle(tilt.direction * 23, 6, MINT))
	screen.add_child(calibration_dot)
	_label("Sensibilidad", Vector2(660, 474), 16, MUTED)
	var slider := HSlider.new()
	slider.position = Vector2(810, 477)
	slider.size = Vector2(210, 25)
	slider.min_value = 0.6
	slider.max_value = 3.0
	slider.step = 0.1
	slider.value = tilt.sensitivity
	slider.value_changed.connect(tilt.save_sensitivity)
	screen.add_child(slider)
	touch_toggle = _button("", Rect2(1050, 468, 182, 40), func():
		tilt.use_touch = not tilt.use_touch
		_rebuild())
	var player_ready: bool = false
	for entry: Dictionary in session.roster:
		if entry.id == session.local_id():
			player_ready = entry.ready
	_button("✓ Listo" if player_ready else "Estoy listo", Rect2(660, 547, 260, 52), func(): session.set_ready(not player_ready), player_ready)
	var start := _button("Comenzar" if session.is_host() else "Esperando anfitrión", Rect2(936, 547, 296, 52), func(): session.start_match(), true)
	start.disabled = not session.can_start()
	_label(session.message if not session.message.is_empty() else "Misma red Wi-Fi o hotspot · Todos deben marcarse listos", Vector2(50, 643), 18, MUTED)
	sensor_label = _label("", Vector2(660, 627), 15, MUTED)

func _game() -> void:
	arena = load("res://scenes/modes/arena.tscn").instantiate()
	design.add_child(arena)
	design.move_child(arena, 0)
	arena.local_peer = session.local_id()
	arena.local_simulation = session.is_host()
	arena.set_map(session.current_map)
	arena.set_state(session.current_state)
	_panel(Rect2(24, 16, 1232, 66), Color("152936"))
	_label("PISTACHO", Vector2(44, 34), 24, MINT)
	_label("LABERINTO" if session.mode == "maze" else "REY DE LA MONTAÑA", Vector2(230, 38), 20)
	timer_label = _label("00:00", Vector2(779, 34), 25, Color("fbd88c"))
	_button("Calibrar", Rect2(900, 28, 110, 42), func(): tilt.calibrate())
	_button("♫", Rect2(1021, 28, 52, 42), func(): sounds.muted = not sounds.muted)
	_button("Salir", Rect2(1084, 28, 151, 42), func(): session.leave())
	for entry: Dictionary in session.roster:
		var y: float = 119 + int(entry.slot) * 91
		_panel(Rect2(24, y, 139, 77), Color("152936"))
		_label("J%d  %s" % [int(entry.slot) + 1, "TÚ" if entry.id == session.local_id() else ""], Vector2(38, y + 9), 20, Avatar.COLORS[int(entry.slot)])
		player_labels[entry.slot] = _label(entry.name, Vector2(38, y + 39), 14, MUTED, Vector2(115, 32))
	state_label = _label("", Vector2(235, 675), 18, Color("fbd88c"), Vector2(800, 35))
	sensor_label = _label("", Vector2(24, 668), 12, MUTED, Vector2(200, 35))
	item_button = _button("SIN\nOBJETO", Rect2(1120, 538, 136, 120), func(): session.use_item(), true)
	item_button.add_theme_font_size_override("font_size", 17)
	_label("ESPACIO", Vector2(1145, 671), 12, MUTED)
	_label("Llega al cetro" if session.mode == "maze" else str(rules.summit_seconds) + " s solo en la cima", Vector2(1116, 119), 14, MUTED, Vector2(140, 65))
	stick = load("res://scenes/ui/touch_stick.tscn").instantiate()
	stick.position = Vector2(28, 524)
	stick.size = Vector2(125, 125)
	stick.direction_changed.connect(func(value: Vector2): tilt.touch_direction = value)
	screen.add_child(stick)
	stick.visible = tilt.use_touch
	if session.status == "results":
		_results()

func _results() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.08, 0.8)
	shade.size = Vector2(1280, 720)
	screen.add_child(shade)
	_panel(Rect2(360, 188, 560, 340), Color("203943"))
	var slot: int = session.current_state.get("winner", 0)
	var winner_name: String = "Jugador %d" % (slot + 1)
	for entry: Dictionary in session.roster:
		if entry.slot == slot:
			winner_name = entry.name
	_label("VICTORIA", Vector2(534, 220), 26, Color("fbd88c"))
	_label(winner_name, Vector2(394, 275), 42, Avatar.COLORS[slot], Vector2(490, 70), HORIZONTAL_ALIGNMENT_CENTER)
	_label("conquistó el cetro" if session.mode == "maze" else "conquistó la montaña", Vector2(415, 351), 24, WHITE, Vector2(450, 40), HORIZONTAL_ALIGNMENT_CENTER)
	if session.is_host():
		_button("Volver a la sala", Rect2(430, 435, 420, 54), func(): session.back_to_lobby(), true)
	else:
		_label("Esperando al anfitrión…", Vector2(488, 448), 21, MUTED)

func _receive_map(value: Dictionary) -> void:
	if is_instance_valid(arena):
		arena.set_map(value)

func _receive_state(value: Dictionary) -> void:
	if is_instance_valid(arena):
		arena.set_state(value)
	var announcement: String = value.get("announcement", "")
	if announcement != last_announcement:
		last_announcement = announcement
		notification_time = 4.0

func _process(delta: float) -> void:
	if is_instance_valid(calibration_dot):
		calibration_dot.queue_redraw()
	if is_instance_valid(sensor_label):
		sensor_label.text = tilt.source
	if is_instance_valid(touch_toggle):
		touch_toggle.text = "Táctil: %s" % ("sí" if tilt.use_touch else "no")
	if is_instance_valid(stick):
		stick.visible = tilt.use_touch
	if shown_status not in ["match", "results"] or session.current_state.is_empty():
		return
	var state: Dictionary = session.current_state
	if is_instance_valid(timer_label):
		var seconds := int(state.time)
		timer_label.text = "%02d:%02d" % [int(seconds / 60.0), seconds % 60]
	if not is_instance_valid(item_button):
		return
	item_button.disabled = true
	item_button.text = "SIN\nOBJETO" if session.mode == "maze" else "CAJA\nAUTO"
	for player: Dictionary in state.players:
		if player.id != session.local_id():
			continue
		if not player.item.is_empty():
			item_button.disabled = false
			item_button.text = "%s\nUSAR" % Simulation.item_name(player.item).to_upper().replace(" ", "\n")
		var text: String = ""
		if player.inverted_until > state.time:
			text = "Invertido · %ds" % ceili(player.inverted_until - state.time)
		elif player.grown_until > state.time:
			text = "Gigante · %ds" % ceili(player.grown_until - state.time)
		elif player.protected_until > state.time:
			text = "Protegido · %ds" % ceili(player.protected_until - state.time)
		if player_labels.has(player.slot) and not text.is_empty():
			player_labels[player.slot].text = text
		elif player_labels.has(player.slot):
			for entry: Dictionary in session.roster:
				if entry.slot == player.slot:
					player_labels[player.slot].text = entry.name
	if state.countdown > 0.0:
		state_label.text = "Preparados… %d" % ceili(state.countdown)
	elif notification_time > 0.0:
		notification_time -= delta
		state_label.text = last_announcement
	elif state.summit_slot >= 0:
		state_label.text = "J%d controla la cima · %.1f / %g s" % [int(state.summit_slot) + 1, state.summit_time, rules.summit_seconds]
	else:
		state_label.text = "Inclina para moverte · Recoge cajas" if session.mode == "maze" else "Empuja a tus rivales · Evita las explosiones"

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		if event is InputEventKey and event.physical_keycode == KEY_SPACE:
			session.use_item()
		elif event is InputEventKey and event.physical_keycode == KEY_C:
			tilt.calibrate()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(tilt):
		tilt.touch_direction = Vector2.ZERO
		tilt.direction = Vector2.ZERO

func _panel(rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(color))
	screen.add_child(panel)
	return panel

func _label(text: String, point: Vector2, font_size: int = 20, color: Color = WHITE, dimensions: Vector2 = Vector2(0, 0), alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.size = dimensions
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dimensions.x > 0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screen.add_child(label)
	return label

func _button(text: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_stylebox_override("normal", _style(MINT if primary else Color("29424e"), 10))
	button.add_theme_stylebox_override("hover", _style(Color("96f2d4") if primary else Color("385664"), 10))
	button.add_theme_stylebox_override("pressed", _style(Color("4ab38f") if primary else Color("1d3542"), 10))
	button.add_theme_stylebox_override("disabled", _style(Color("263740"), 10))
	button.add_theme_color_override("font_color", Color("112d32") if primary else WHITE)
	button.add_theme_color_override("font_hover_color", Color("112d32") if primary else WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.pressed.connect(callback)
	screen.add_child(button)
	return button

func _field(value: String, rect: Rect2) -> LineEdit:
	var field := LineEdit.new()
	field.text = value
	field.position = rect.position
	field.size = rect.size
	field.add_theme_stylebox_override("normal", _style(Color("0e202d"), 8))
	field.add_theme_stylebox_override("focus", _style(Color("223f4b"), 8))
	field.add_theme_color_override("font_color", WHITE)
	screen.add_child(field)
	return field

func _style(color: Color, radius: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style
