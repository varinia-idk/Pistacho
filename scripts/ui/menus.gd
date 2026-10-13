extends CanvasLayer
## Pantallas fuera de la partida: inicio, unirse, sala, ajustes y cómo jugar.

const Style = preload("res://scripts/ui/style.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const Backdrop = preload("res://scripts/ui/backdrop.gd")
const SENSITIVITY_DEG := Vector2(30.0, 8.0)  ## Saturación para sensibilidad 1 y 10.
const DIFFICULTY: Array[float] = [0.4, 0.75, 1.0]
const ROUNDS: Array[int] = [3, 5, 7]

var root := Control.new()
var screens: Dictionary[String, Control] = {}
var screen := "main"
var ip_edit := LineEdit.new()
var join_status := Style.label("", "Muted")
var main_status := Style.label("", "Muted")
var lobby_info := Style.label("", "Accent")
var lobby_hint := Style.label("", "Muted")
var lobby_rows: Array[Label] = []
var lobby_tags: Array[Label] = []
var start_button: Button
var leave_button: Button
var sensitivity := HSlider.new()
var sensitivity_value := Style.label("", "Accent")
var difficulty_buttons: Array[Button] = []
var round_buttons: Array[Button] = []
var vibration := CheckButton.new()
var invert_x := CheckButton.new()
var invert_y := CheckButton.new()


func _init(theme: Theme) -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.theme = theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(Backdrop.new())
	screens["main"] = _build_main()
	screens["join"] = _build_join()
	screens["lobby"] = _build_lobby()
	screens["settings"] = _build_settings()
	screens["howto"] = _build_howto()
	var version := Style.label(Style.VERSION, "Muted", HORIZONTAL_ALIGNMENT_RIGHT)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -200.0
	version.offset_top = -60.0
	version.offset_right = -28.0
	version.offset_bottom = -20.0
	root.add_child(version)


func show_screen(name_value: String) -> void:
	screen = name_value
	if screen == "settings":
		_load_settings()


## Atrás de Android: vuelve al inicio o sale de la sala. Devuelve false si ya está en el inicio.
func back() -> bool:
	if Game.phase == Game.Phase.LOBBY:
		_leave()
		return true
	if screen != "main":
		_close_screen()
		return true
	return false


func _process(_delta: float) -> void:
	var outside := Game.phase == Game.Phase.MENU or Game.phase == Game.Phase.LOBBY
	visible = outside
	if not outside:
		return
	var active := "lobby" if Game.phase == Game.Phase.LOBBY else screen
	if Game.phase == Game.Phase.MENU and screen == "lobby":
		active = "main"
		screen = "main"
	for key: String in screens:
		screens[key].visible = key == active
	main_status.text = Net.status if screen == "main" else ""
	join_status.text = Net.status
	if active == "lobby":
		_update_lobby()


# --- Construcción ---

func _page() -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)
	return column


func _card(title: String) -> VBoxContainer:
	var column := _page()
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 900.0
	column.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 22)
	card.add_child(inner)
	inner.add_child(Style.label(title, "Heading"))
	return inner


func _row(children: Array, separation := 24) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", separation)
	for child: Control in children:
		row.add_child(child)
	return row


func _build_main() -> Control:
	var column := _page()
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/pistacho.svg")
	logo.custom_minimum_size = Vector2(190.0, 190.0)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_row([logo]))
	column.add_child(Style.label("Pistacho", "Title"))
	column.add_child(Style.label("Inclina el teléfono. Domina la inercia. Llega primero.", "Muted"))
	var play := Style.button("Jugar contra bots", true, 620.0)
	play.pressed.connect(_play_bots)
	var host := Style.button("Crear sala", false, 300.0)
	host.pressed.connect(_create_room)
	var join := Style.button("Unirse", false, 300.0)
	join.pressed.connect(show_screen.bind("join"))
	var settings := Style.button("Ajustes", false, 300.0)
	settings.pressed.connect(show_screen.bind("settings"))
	var howto := Style.button("Cómo jugar", false, 300.0)
	howto.pressed.connect(show_screen.bind("howto"))
	column.add_child(_row([play]))
	column.add_child(_row([host, join], 20))
	column.add_child(_row([settings, howto], 20))
	column.add_child(main_status)
	return column.get_parent()


func _build_join() -> Control:
	var card := _card("Unirse a una sala")
	card.add_child(Style.label("Conéctate a la misma Wi-Fi que el anfitrión (o a su punto de acceso)\ny escribe la IP que ves en su pantalla.", "Muted"))
	ip_edit.placeholder_text = "Ej. 192.168.1.20"
	ip_edit.text = Net.last_ip
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_edit.custom_minimum_size = Vector2(560.0, 104.0)
	ip_edit.add_theme_font_size_override("font_size", 40)
	ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	ip_edit.text_submitted.connect(func(_text: String) -> void: _connect())
	card.add_child(_row([ip_edit]))
	var connect_button := Style.button("Conectar", true, 340.0)
	connect_button.pressed.connect(_connect)
	var back_button := Style.button("Volver", false, 340.0)
	back_button.pressed.connect(_close_screen)
	card.add_child(_row([back_button, connect_button]))
	card.add_child(join_status)
	return _owner(card)


func _build_lobby() -> Control:
	var card := _card("Sala")
	card.add_child(lobby_info)
	card.add_child(lobby_hint)
	for slot in Game.SLOTS:
		var name_label := Style.label("", "", HORIZONTAL_ALIGNMENT_LEFT)
		name_label.custom_minimum_size.x = 420.0
		var tag := Style.label("", "Muted", HORIZONTAL_ALIGNMENT_RIGHT)
		tag.custom_minimum_size.x = 220.0
		lobby_rows.append(name_label)
		lobby_tags.append(tag)
		card.add_child(_row([Widgets.Ball.new(Game.COLORS[slot], 56.0), name_label, tag]))
	start_button = Style.button("Comenzar", true, 340.0)
	start_button.pressed.connect(Game.start_match)
	leave_button = Style.button("Salir", false, 340.0)
	leave_button.pressed.connect(_leave)
	card.add_child(_row([leave_button, start_button]))
	return _owner(card)


func _build_settings() -> Control:
	var card := _card("Ajustes")
	sensitivity.min_value = 1
	sensitivity.max_value = 10
	sensitivity.step = 1
	sensitivity.custom_minimum_size = Vector2(480.0, 48.0)
	sensitivity.focus_mode = Control.FOCUS_NONE
	sensitivity.value_changed.connect(_on_sensitivity)
	sensitivity_value.custom_minimum_size.x = 60.0
	card.add_child(_setting("Sensibilidad", _row([sensitivity, sensitivity_value], 16)))
	var difficulty_row := _row([], 12)
	for i in DIFFICULTY.size():
		var button := _toggle(["Fácil", "Normal", "Difícil"][i], difficulty_buttons, difficulty_row)
		button.pressed.connect(_on_difficulty.bind(i))
	card.add_child(_setting("Bots", difficulty_row))
	var rounds_row := _row([], 12)
	for i in ROUNDS.size():
		var button := _toggle(str(ROUNDS[i]), round_buttons, rounds_row)
		button.pressed.connect(_on_rounds.bind(i))
	card.add_child(_setting("Rondas", rounds_row))
	for entry: Array in [[vibration, "Vibración"], [invert_x, "Invertir izquierda/derecha"], [invert_y, "Invertir adelante/atrás"]]:
		var check: CheckButton = entry[0]
		check.focus_mode = Control.FOCUS_NONE
		check.text = entry[1]
		check.toggled.connect(_on_check)
		card.add_child(_row([check]))
	var reset := Style.button("Restablecer", false, 340.0)
	reset.pressed.connect(func() -> void:
		Config.reset()
		_load_settings())
	var done := Style.button("Listo", true, 340.0)
	done.pressed.connect(_close_screen)
	card.add_child(_row([reset, done]))
	return _owner(card)


func _build_howto() -> Control:
	var card := _card("Cómo jugar")
	for line: String in [
			"Sostén el teléfono cómodo durante la cuenta 3-2-1: esa es tu posición neutra.",
			"Inclínalo para empujar tu bola. Tiene inercia: frena inclinando al revés.",
			"Gira la muñeca de golpe para hacer un dash (en PC: Espacio).",
			"Evita los agujeros: el borde se puede rozar, el centro negro te hace caer.",
			"Llega primero a la estrella. A los 60 s el suelo empieza a hundirse desde la salida.",
			"Puntos por ronda: 3, 2, 1 y 0. Juega solo contra bots o con amigos en la misma Wi-Fi."]:
		var text := Style.label("•  " + line, "", HORIZONTAL_ALIGNMENT_LEFT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 820.0
		card.add_child(text)
	var done := Style.button("Entendido", true, 340.0)
	done.pressed.connect(_close_screen)
	card.add_child(_row([done]))
	return _owner(card)


func _setting(title: String, control: Control) -> HBoxContainer:
	var name_label := Style.label(title, "", HORIZONTAL_ALIGNMENT_LEFT)
	name_label.custom_minimum_size.x = 260.0
	return _row([name_label, control])


func _toggle(text: String, group: Array[Button], row: HBoxContainer) -> Button:
	var button := Style.button(text, false, 170.0)
	button.custom_minimum_size.y = 84.0
	group.append(button)
	row.add_child(button)
	return button


## Raíz a mostrar u ocultar de una tarjeta (su CenterContainer).
func _owner(card: VBoxContainer) -> Control:
	return card.get_parent().get_parent().get_parent()


# --- Acciones ---

func _play_bots() -> void:
	Net.leave()
	Net.status = ""
	Game.start_match()


func _create_room() -> void:
	if Net.host() == OK:
		Game.to_lobby()


func _connect() -> void:
	Net.join(ip_edit.text)


func _leave() -> void:
	Net.leave()
	Net.status = ""
	Game.to_menu()
	screen = "main"


func _close_screen() -> void:
	if screen == "settings":
		Config.save_file()
	if screen == "join" and Net.online and not Net.is_host():
		Net.leave()
	Net.status = ""
	screen = "main"


func _update_lobby() -> void:
	var host := Net.is_host()
	if host:
		var ips := Net.private_ipv4()
		lobby_info.text = "IP de la sala: %s" % " / ".join(ips) if not ips.is_empty() else "Sin red local"
		lobby_hint.text = "Los demás pulsan Unirse y escriben esta IP. Los huecos libres los ocupan bots." if not ips.is_empty() \
			else "Conéctate a una Wi-Fi o activa el punto de acceso del teléfono."
	else:
		lobby_info.text = "Conectado"
		lobby_hint.text = "Esperando a que el anfitrión comience…"
	var mine := Net.my_slot()
	for slot in Game.SLOTS:
		var peer := Net.slot_peers[slot]
		lobby_rows[slot].text = "Bot" if peer == 0 else ("Anfitrión" if slot == 0 else "Jugador %d" % (slot + 1))
		lobby_tags[slot].text = "tú" if slot == mine and peer != 0 else ("listo" if peer != 0 else "")
	start_button.visible = host
	leave_button.text = "Cerrar sala" if host else "Salir"


# --- Ajustes ---

func _load_settings() -> void:
	var saturation := Config.value("saturation_deg")
	var level := remap(saturation, SENSITIVITY_DEG.x, SENSITIVITY_DEG.y, 1.0, 10.0)
	sensitivity.set_value_no_signal(clampf(roundf(level), 1.0, 10.0))
	sensitivity_value.text = str(int(sensitivity.value))
	var skill := Config.value("bot_skill")
	var nearest := 0
	for i in DIFFICULTY.size():
		if absf(DIFFICULTY[i] - skill) < absf(DIFFICULTY[nearest] - skill):
			nearest = i
	_select(difficulty_buttons, nearest)
	_select(round_buttons, maxi(0, ROUNDS.find(Config.count("rounds"))))
	vibration.set_pressed_no_signal(Config.flag("vibration"))
	# Relativo al valor por defecto: los ejes por defecto ya siguen la convención de Godot.
	invert_x.set_pressed_no_signal(Config.value("invert_x") != Config.DEFAULTS["invert_x"][0])
	invert_y.set_pressed_no_signal(Config.value("invert_y") != Config.DEFAULTS["invert_y"][0])


func _select(group: Array[Button], index: int) -> void:
	for i in group.size():
		group[i].theme_type_variation = "PrimaryButton" if i == index else ""


func _on_sensitivity(level: float) -> void:
	Config.set_value("saturation_deg", remap(level, 1.0, 10.0, SENSITIVITY_DEG.x, SENSITIVITY_DEG.y))
	sensitivity_value.text = str(int(level))


func _on_difficulty(index: int) -> void:
	Config.set_value("bot_skill", DIFFICULTY[index])
	_select(difficulty_buttons, index)


func _on_rounds(index: int) -> void:
	Config.set_value("rounds", ROUNDS[index])
	_select(round_buttons, index)


func _on_check(_on: bool) -> void:
	Config.set_value("vibration", 1.0 if vibration.button_pressed else 0.0)
	var base_x: float = Config.DEFAULTS["invert_x"][0]
	var base_y: float = Config.DEFAULTS["invert_y"][0]
	Config.set_value("invert_x", 1.0 - base_x if invert_x.button_pressed else base_x)
	Config.set_value("invert_y", 1.0 - base_y if invert_y.button_pressed else base_y)
