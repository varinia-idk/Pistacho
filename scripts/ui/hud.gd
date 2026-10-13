extends CanvasLayer
## Menú, sala, HUD y resultados. Lee el estado de Game y Net en cada frame.

var root := Control.new()
var menu := VBoxContainer.new()
var ip_edit := LineEdit.new()
var menu_status := Label.new()
var lobby := VBoxContainer.new()
var lobby_info := Label.new()
var lobby_roster: Array[Label] = []
var start_button: Button
var lobby_leave: Button
var lobby_wait := Label.new()
var top_label := Label.new()
var banner_label := Label.new()
var score_labels: Array[Label] = []
var center_label := Label.new()
var message_label := Label.new()
var item_button := Button.new()
var status := StatusIcons.new()
var results := PanelContainer.new()
var results_label := Label.new()
var results_buttons := HBoxContainer.new()
var rematch_button: Button
var back_button: Button


## Íconos del jugador local: recarga del dash y efectos activos.
class StatusIcons extends Control:
	var dash_ready := 1.0
	var shielded := false
	var falling := false

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var c := Vector2(44.0, 44.0)
		draw_circle(c, 40.0, Color(1, 1, 1, 0.12), true, -1.0, true)
		var sector := PackedVector2Array([c])
		for k in 33:
			sector.append(c + Vector2.from_angle(-PI / 2.0 + TAU * dash_ready * k / 32.0) * 40.0)
		if dash_ready > 0.01:
			draw_colored_polygon(sector, Color(1, 1, 1, 0.85 if dash_ready >= 1.0 else 0.35))
		draw_string(font, c + Vector2(-34.0, 8.0), "DASH", HORIZONTAL_ALIGNMENT_CENTER, 68.0, 20, Color(0.05, 0.08, 0.12))
		var x := 120.0
		if shielded:
			var shield := PackedVector2Array([Vector2(x, 10), Vector2(x + 30, 20), Vector2(x + 26, 56), Vector2(x, 76), Vector2(x - 26, 56), Vector2(x - 30, 20)])
			draw_colored_polygon(shield, Color(0.7, 0.95, 1.0, 0.9))
			x += 76.0
		if falling:
			draw_colored_polygon(PackedVector2Array([Vector2(x - 26, 30), Vector2(x + 26, 30), Vector2(x, 70)]), Color(1.0, 0.5, 0.12))
			draw_rect(Rect2(x - 9, 8, 18, 24), Color(1.0, 0.5, 0.12))


func _init(theme: Theme) -> void:
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_menu()
	_build_lobby()
	top_label.position = Vector2(110.0, 16.0)
	root.add_child(top_label)
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner_label.offset_top = 16.0
	banner_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	root.add_child(banner_label)
	var scores := VBoxContainer.new()
	scores.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scores.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	scores.offset_left = -260.0
	scores.offset_top = 16.0
	scores.offset_right = -20.0
	root.add_child(scores)
	for slot in Game.SLOTS:
		var label := Label.new()
		label.add_theme_color_override("font_color", Game.COLORS[slot])
		scores.add_child(label)
		score_labels.append(label)
	for label: Label in [center_label, message_label]:
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 12)
		root.add_child(label)
	center_label.add_theme_font_size_override("font_size", 160)
	message_label.offset_top = 260.0
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	status.offset_left = -250.0
	status.offset_top = -380.0
	status.offset_right = -20.0
	status.offset_bottom = -290.0
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)
	item_button.text = "Sin ítem"
	item_button.disabled = true
	item_button.focus_mode = Control.FOCUS_NONE
	item_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	item_button.offset_left = -250.0
	item_button.offset_top = -250.0
	item_button.offset_right = -30.0
	item_button.offset_bottom = -30.0
	item_button.pressed.connect(Game.request_action.bind(Game.Action.ITEM))
	root.add_child(item_button)
	_build_results()


func _button(text: String, width: float, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 110.0)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _centered_column(box: VBoxContainer) -> void:
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	root.add_child(box)


func _add_centered(box: VBoxContainer, item: Control) -> void:
	item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if item is Label:
		(item as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(item)


func _build_menu() -> void:
	_centered_column(menu)
	var title := Label.new()
	title.text = "Pistacho"
	title.add_theme_font_size_override("font_size", 110)
	var subtitle := Label.new()
	subtitle.text = "Inclina el teléfono. Domina la inercia."
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 16)
	ip_edit.placeholder_text = "IP del anfitrión"
	ip_edit.text = Net.last_ip
	ip_edit.custom_minimum_size = Vector2(380.0, 110.0)
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_row.add_child(ip_edit)
	join_row.add_child(_button("Unirse", 220.0, _on_join))
	var hint := Label.new()
	hint.text = "Escritorio: flechas = inclinar · Espacio = dash · E = ítem"
	hint.modulate = Color(1, 1, 1, 0.6)
	menu_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	for item: Control in [title, subtitle, _button("Jugar contra bots", 620.0, _on_play_bots),
			_button("Crear sala", 620.0, _on_create), join_row, menu_status, hint]:
		_add_centered(menu, item)


func _build_lobby() -> void:
	_centered_column(lobby)
	var title := Label.new()
	title.text = "Sala"
	title.add_theme_font_size_override("font_size", 90)
	_add_centered(lobby, title)
	_add_centered(lobby, lobby_info)
	for slot in Game.SLOTS:
		var label := Label.new()
		label.add_theme_color_override("font_color", Game.COLORS[slot])
		lobby_roster.append(label)
		_add_centered(lobby, label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	start_button = _button("Comenzar", 360.0, Game.start_match)
	lobby_leave = _button("Salir", 360.0, _on_leave)
	row.add_child(start_button)
	row.add_child(lobby_leave)
	_add_centered(lobby, row)
	lobby_wait.text = "Esperando a que el anfitrión comience…"
	lobby_wait.modulate = Color(1, 1, 1, 0.7)
	_add_centered(lobby, lobby_wait)


func _build_results() -> void:
	results.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	results.offset_left = -420.0
	results.offset_right = 420.0
	results.offset_top = -300.0
	results.offset_bottom = 300.0
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	results.add_child(box)
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(results_label)
	results_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	results_buttons.add_theme_constant_override("separation", 30)
	box.add_child(results_buttons)
	rematch_button = _button("Revancha", 300.0, Game.start_match)
	back_button = _button("Menú", 300.0, _on_back)
	results_buttons.add_child(rematch_button)
	results_buttons.add_child(back_button)
	root.add_child(results)


func _on_play_bots() -> void:
	Net.leave()
	Game.start_match()


func _on_create() -> void:
	if Net.host() == OK:
		Game.to_lobby()


func _on_join() -> void:
	Net.join(ip_edit.text)


func _on_leave() -> void:
	Net.leave()
	Game.to_menu()


## Fin de partida: el anfitrión vuelve a la sala con todos; offline, al menú; un cliente sale.
func _on_back() -> void:
	if Net.online and Net.is_host():
		Game.to_lobby()
	else:
		_on_leave()


func _process(_delta: float) -> void:
	var phase := Game.phase
	var host := Net.is_host()
	var in_match := phase != Game.Phase.MENU and phase != Game.Phase.LOBBY
	menu.visible = phase == Game.Phase.MENU
	lobby.visible = phase == Game.Phase.LOBBY
	for node: CanvasItem in [top_label, item_button, status, score_labels[0].get_parent()]:
		node.visible = in_match
	results.visible = phase == Game.Phase.ROUND_END or phase == Game.Phase.MATCH_END
	results_buttons.visible = phase == Game.Phase.MATCH_END
	rematch_button.visible = host
	back_button.text = "Sala" if Net.online and host else ("Salir" if Net.online else "Menú")
	center_label.text = ""
	message_label.text = ""
	banner_label.text = ""
	match phase:
		Game.Phase.MENU:
			menu_status.text = Net.status
			return
		Game.Phase.LOBBY:
			_update_lobby(host)
			return
	if Game.mode == null:
		return
	for slot in Game.SLOTS:
		score_labels[slot].text = "● %s  %d" % [Game.player_name(slot), Game.scores[slot]]
	var cfg := Game.mode.cfg
	var clock := maxf(0.0, cfg["round_time"] - Game.mode.time)
	top_label.text = "Ronda %d/%d · %s · %d:%02d" % [Game.round_index + 1, Game.rounds_total, Game.mode.title(), floori(clock / 60.0), int(clock) % 60]
	match phase:
		Game.Phase.COUNTDOWN:
			center_label.text = str(maxi(1, ceili(Game.phase_left)))
			message_label.text = "Calibrando: sostén el teléfono cómodo y quieto" if Game.tilt.calibrating else "Prepárate"
		Game.Phase.PLAYING:
			if Game.mode.time < 1.0:
				center_label.text = "¡YA!"
			var collapse: float = cfg["collapse_start"] - Game.mode.time
			if collapse > 0.0 and collapse < 5.0:
				banner_label.text = "El suelo colapsa en %d…" % ceili(collapse)
			elif collapse <= 0.0 and collapse > -3.0:
				banner_label.text = "¡El suelo colapsa desde la salida!"
		Game.Phase.ROUND_END:
			results_label.text = _round_text()
		Game.Phase.MATCH_END:
			results_label.text = _match_text() + ("" if host else "\n\nEl anfitrión decide la revancha")
	var me := Game.local_view()
	if me:
		status.dash_ready = me.dash_ready
		status.shielded = me.invulnerable
		status.falling = me.falling > 0.0
		status.queue_redraw()


func _update_lobby(host: bool) -> void:
	var ips := Net.private_ipv4()
	if host:
		lobby_info.text = ("Tu IP: %s · puerto %d" % [" / ".join(ips), Net.PORT]) if not ips.is_empty() \
			else "Sin IP de red local: conéctate a una Wi-Fi o activa el punto de acceso"
	else:
		lobby_info.text = "Conectado a la sala · ping %s" % ("%d ms" % Net.ping_ms if Net.ping_ms >= 0.0 else "—")
	var mine := Net.my_slot()
	for slot in Game.SLOTS:
		var peer := Net.slot_peers[slot]
		var who := "Bot" if peer == 0 else ("Anfitrión" if slot == 0 else "Jugador %d" % (slot + 1))
		lobby_roster[slot].text = "● %d. %s%s" % [slot + 1, who, " (tú)" if slot == mine and peer != 0 else ""]
	start_button.visible = host
	lobby_wait.visible = not host
	lobby_leave.text = "Cerrar sala" if host else "Salir"


func _round_text() -> String:
	var lines: Array[String] = ["Ronda %d" % (Game.round_index + 1), ""]
	for place in Game.last_ranking.size():
		var slot := Game.last_ranking[place]
		lines.append("%d. %s   +%d   (%d)" % [place + 1, Game.player_name(slot), Game.POINTS[place], Game.scores[slot]])
	lines.append("")
	lines.append("Siguiente en %d…" % maxi(1, ceili(Game.phase_left)))
	return "\n".join(lines)


func _match_text() -> String:
	var lines: Array[String] = ["Fin de la partida", ""]
	var order := Game.match_ranking()
	for place in order.size():
		lines.append("%d. %s   %d pts" % [place + 1, Game.player_name(order[place]), Game.scores[order[place]]])
	return "\n".join(lines)
