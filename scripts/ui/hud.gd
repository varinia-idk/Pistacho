extends CanvasLayer
## Menú, HUD y resultados. Lee el estado de Game en cada frame.

var root := Control.new()
var menu := VBoxContainer.new()
var top_label := Label.new()
var banner_label := Label.new()
var score_labels: Array[Label] = []
var center_label := Label.new()
var message_label := Label.new()
var item_button := Button.new()
var status := StatusIcons.new()
var results := PanelContainer.new()
var results_label := Label.new()
var rematch_button := Button.new()
var menu_button := Button.new()


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
	item_button.pressed.connect(func() -> void: Game.action(Game.local_slot, Game.Action.ITEM))
	root.add_child(item_button)
	_build_results()


func _build_menu() -> void:
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 28)
	root.add_child(menu)
	var title := Label.new()
	title.text = "Pistacho"
	title.add_theme_font_size_override("font_size", 120)
	var subtitle := Label.new()
	subtitle.text = "Inclina el teléfono. Domina la inercia."
	var play := Button.new()
	play.text = "Jugar contra bots"
	play.custom_minimum_size = Vector2(560.0, 130.0)
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(Game.start_match)
	var hint := Label.new()
	hint.text = "Escritorio: flechas = inclinar · Espacio = dash · E = ítem"
	hint.modulate = Color(1, 1, 1, 0.6)
	for item: Control in [title, subtitle, play, hint]:
		item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if item is Label:
			(item as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		menu.add_child(item)


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
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	box.add_child(buttons)
	rematch_button.text = "Revancha"
	menu_button.text = "Menú"
	for button: Button in [rematch_button, menu_button]:
		button.custom_minimum_size = Vector2(300.0, 110.0)
		button.focus_mode = Control.FOCUS_NONE
		buttons.add_child(button)
	rematch_button.pressed.connect(Game.start_match)
	menu_button.pressed.connect(Game.to_menu)
	root.add_child(results)


func _process(_delta: float) -> void:
	var phase := Game.phase
	var in_match := phase != Game.Phase.MENU
	menu.visible = not in_match
	for node: CanvasItem in [top_label, item_button, status, score_labels[0].get_parent()]:
		node.visible = in_match
	results.visible = phase == Game.Phase.ROUND_END or phase == Game.Phase.MATCH_END
	rematch_button.get_parent().visible = phase == Game.Phase.MATCH_END
	center_label.text = ""
	message_label.text = ""
	banner_label.text = ""
	if not in_match or Game.mode == null:
		return
	for slot in Game.SLOTS:
		score_labels[slot].text = "● %s  %d" % [Game.player_name(slot), Game.scores[slot]]
	var clock := maxf(0.0, Config.value("round_time") - Game.mode.time)
	top_label.text = "Ronda %d/%d · %s · %d:%02d" % [Game.round_index + 1, Game.rounds_total, Game.mode.title(), floori(clock / 60.0), int(clock) % 60]
	match phase:
		Game.Phase.COUNTDOWN:
			center_label.text = str(ceili(Game.phase_left))
			message_label.text = "Calibrando: sostén el teléfono cómodo y quieto" if Game.tilt.calibrating else "Prepárate"
		Game.Phase.PLAYING:
			if Game.mode.time < 1.0:
				center_label.text = "¡YA!"
			var collapse := Config.value("collapse_start") - Game.mode.time
			if collapse > 0.0 and collapse < 5.0:
				banner_label.text = "El suelo colapsa en %d…" % ceili(collapse)
			elif collapse <= 0.0 and collapse > -3.0:
				banner_label.text = "¡El suelo colapsa desde la salida!"
		Game.Phase.ROUND_END:
			results_label.text = _round_text()
		Game.Phase.MATCH_END:
			results_label.text = _match_text()
	var me := Game.local_player()
	if me:
		status.dash_ready = me.view.dash_ready
		status.shielded = me.view.invulnerable
		status.falling = me.view.falling > 0.0
		status.queue_redraw()


func _round_text() -> String:
	var lines: Array[String] = ["Ronda %d" % (Game.round_index + 1), ""]
	for place in Game.last_ranking.size():
		var slot := Game.last_ranking[place]
		lines.append("%d. %s   +%d   (%d)" % [place + 1, Game.player_name(slot), Game.POINTS[place], Game.scores[slot]])
	lines.append("")
	lines.append("Siguiente en %d…" % ceili(Game.phase_left))
	return "\n".join(lines)


func _match_text() -> String:
	var lines: Array[String] = ["Fin de la partida", ""]
	var order := Game.match_ranking()
	for place in order.size():
		lines.append("%d. %s   %d pts" % [place + 1, Game.player_name(order[place]), Game.scores[order[place]]])
	return "\n".join(lines)
