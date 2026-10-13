extends CanvasLayer
## HUD de partida: pausa, ronda y tiempo, marcador, dash, cuenta atrás, avisos, resultados y ganador.

const Style = preload("res://scripts/ui/style.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")

var root := Control.new()
var top := Control.new()
var round_label := Style.label("", "")
var banner := PanelContainer.new()
var banner_label := Style.label("", "")
var board := PanelContainer.new()
var score_names: Array[Label] = []
var score_points: Array[Label] = []
var gauge := Widgets.DashGauge.new()
var countdown := Style.label("", "Title")
var hint := Style.label("", "Muted")
var results := CenterContainer.new()
var results_body := VBoxContainer.new()
var results_footer := Style.label("", "Muted")
var pause_panel := CenterContainer.new()
var pause_note := Style.label("", "Muted")


func _init(theme: Theme) -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_top()
	_build_board()
	gauge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	gauge.offset_left = -210.0
	gauge.offset_top = -210.0
	gauge.offset_right = -40.0
	gauge.offset_bottom = -40.0
	root.add_child(gauge)
	for label: Label in [countdown, hint]:
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_outline_color", Color(Style.INK, 0.9))
		label.add_theme_constant_override("outline_size", 18)
		root.add_child(label)
	countdown.add_theme_font_size_override("font_size", 240)
	hint.offset_top = 300.0
	hint.add_theme_font_size_override("font_size", 34)
	_build_results()
	_build_pause()
	Game.phase_changed.connect(_on_phase)


func _build_top() -> void:
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 120.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var pause := Style.button("II", false, 88.0)
	pause.custom_minimum_size = Vector2(88.0, 88.0)
	pause.position = Vector2(24.0, 18.0)
	pause.pressed.connect(toggle_pause)
	top.add_child(pause)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	var pill := PanelContainer.new()
	pill.theme_type_variation = "Pill"
	pill.add_child(round_label)
	column.add_child(pill)
	banner.theme_type_variation = "Pill"
	banner.add_theme_stylebox_override("panel", _pill_box(Color(Style.WARN, 0.92)))
	banner_label.add_theme_color_override("font_color", Style.INK)
	banner.add_child(banner_label)
	column.add_child(banner)


func _build_board() -> void:
	board.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	board.offset_left = -330.0
	board.offset_top = 20.0
	board.offset_right = -24.0
	var box := Style.card_box(Color(Style.PANEL, 0.85))
	box.content_margin_left = 22.0
	box.content_margin_right = 22.0
	box.content_margin_top = 16.0
	box.content_margin_bottom = 16.0
	board.add_theme_stylebox_override("panel", box)
	root.add_child(board)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	board.add_child(rows)
	for slot in Game.SLOTS:
		var name_label := Style.label("", "", HORIZONTAL_ALIGNMENT_LEFT)
		name_label.custom_minimum_size.x = 150.0
		name_label.add_theme_font_size_override("font_size", 26)
		var points := Style.label("", "Accent", HORIZONTAL_ALIGNMENT_RIGHT)
		points.custom_minimum_size.x = 50.0
		score_names.append(name_label)
		score_points.append(points)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(Widgets.Ball.new(Game.COLORS[slot], 40.0))
		row.add_child(name_label)
		row.add_child(points)
		rows.add_child(row)


func _build_results() -> void:
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(results)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 860.0
	results.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	card.add_child(column)
	results_body.add_theme_constant_override("separation", 14)
	column.add_child(results_body)
	column.add_child(results_footer)


func _build_pause() -> void:
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	dim.visible = false
	pause_panel.set_meta("dim", dim)
	root.add_child(pause_panel)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 760.0
	pause_panel.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	card.add_child(column)
	column.add_child(Style.label("Pausa", "Heading"))
	column.add_child(pause_note)
	var leave := Style.button("Salir de la partida", false, 340.0)
	leave.pressed.connect(_leave_match)
	var resume := Style.button("Continuar", true, 340.0)
	resume.pressed.connect(toggle_pause)
	column.add_child(_row([leave, resume]))


func _row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	for child: Control in children:
		row.add_child(child)
	return row


func _pill_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(999)
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


## Pausa: offline detiene el juego; en red solo muestra opciones (la partida sigue para los demás).
func toggle_pause() -> void:
	var opening := not pause_panel.visible
	pause_panel.visible = opening
	(pause_panel.get_meta("dim") as Control).visible = opening
	pause_note.text = "La partida sigue en marcha para los demás." if Net.online else "El juego está detenido."
	get_tree().paused = opening and not Net.online


func is_paused() -> bool:
	return pause_panel.visible


func _leave_match() -> void:
	pause_panel.visible = false
	(pause_panel.get_meta("dim") as Control).visible = false
	get_tree().paused = false
	Net.leave()
	Game.to_menu()


func _in_match() -> bool:
	return Game.phase != Game.Phase.MENU and Game.phase != Game.Phase.LOBBY


func _process(_delta: float) -> void:
	visible = _in_match() and Game.mode != null
	if not visible:
		if pause_panel.visible:
			toggle_pause()
		return
	var cfg := Game.mode.cfg
	var clock := maxf(0.0, cfg["round_time"] - Game.mode.time)
	round_label.text = "RONDA %d/%d  ·  %s  ·  %d:%02d" % [Game.round_index + 1, Game.rounds_total, Game.mode.title().to_upper(),
		floori(clock / 60.0), int(clock) % 60]
	for slot in Game.SLOTS:
		score_names[slot].text = Game.player_name(slot)
		score_points[slot].text = str(Game.scores[slot])
	var me := Game.local_view()
	gauge.visible = me != null
	if me:
		gauge.charge = me.dash_ready
		gauge.shielded = me.invulnerable
		gauge.queue_redraw()
	_update_center(cfg)
	results.visible = Game.phase == Game.Phase.ROUND_END or Game.phase == Game.Phase.MATCH_END
	if Game.phase == Game.Phase.ROUND_END:
		results_footer.text = "Siguiente ronda en %d…" % maxi(1, ceili(Game.phase_left))


func _update_center(cfg: Dictionary[String, float]) -> void:
	var text := ""
	hint.text = ""
	match Game.phase:
		Game.Phase.COUNTDOWN:
			text = str(maxi(1, ceili(Game.phase_left)))
			hint.text = "Sostén el teléfono cómodo y quieto" if Game.tilt.calibrating else "Prepárate"
		Game.Phase.PLAYING:
			if Game.mode.time < 0.8:
				text = "¡YA!"
	if text != countdown.text:
		countdown.text = text
		if text != "":
			# Cada número aparece con un pequeño rebote.
			countdown.pivot_offset = countdown.size * 0.5
			countdown.scale = Vector2.ONE * 1.5
			create_tween().tween_property(countdown, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var collapse: float = cfg["collapse_start"] - Game.mode.time
	banner_label.text = ""
	if Game.phase == Game.Phase.PLAYING:
		if collapse > 0.0 and collapse < 5.0:
			banner_label.text = "El suelo se hunde en %d…" % ceili(collapse)
		elif collapse <= 0.0 and collapse > -3.0:
			banner_label.text = "¡El suelo se hunde desde la salida!"
	banner.visible = banner_label.text != ""


func _on_phase(phase: Game.Phase) -> void:
	if phase == Game.Phase.ROUND_END:
		_fill_round()
	elif phase == Game.Phase.MATCH_END:
		_fill_match()


func _clear_results() -> void:
	for child in results_body.get_children():
		child.queue_free()


func _fill_round() -> void:
	_clear_results()
	results_body.add_child(Style.label("Ronda %d" % (Game.round_index + 1), "Heading"))
	for place in Game.last_ranking.size():
		var slot := Game.last_ranking[place]
		results_body.add_child(_result_row(place + 1, slot, "+%d" % Game.POINTS[place], "%d pts" % Game.scores[slot]))


func _fill_match() -> void:
	_clear_results()
	var order := Game.match_ranking()
	results_body.add_child(_row([Widgets.Crown.new()]))
	results_body.add_child(Style.label("¡Gana %s!" % Game.player_name(order[0]), "Heading"))
	for place in order.size():
		results_body.add_child(_result_row(place + 1, order[place], "", "%d pts" % Game.scores[order[place]]))
	var host := Net.is_host()
	results_footer.text = "" if host else "El anfitrión decide si hay revancha."
	var back := Style.button("Sala" if Net.online and host else ("Salir" if Net.online else "Menú"), false, 300.0)
	back.pressed.connect(_after_match)
	var buttons: Array = [back]
	if host:
		var again := Style.button("Revancha", true, 300.0)
		again.pressed.connect(Game.start_match)
		buttons.append(again)
	results_body.add_child(_row(buttons))


func _after_match() -> void:
	if Net.online and Net.is_host():
		Game.to_lobby()
	else:
		Net.leave()
		Game.to_menu()


func _result_row(place: int, slot: int, gained: String, total: String) -> HBoxContainer:
	var name_label := Style.label(Game.player_name(slot), "", HORIZONTAL_ALIGNMENT_LEFT)
	name_label.custom_minimum_size.x = 300.0
	var gained_label := Style.label(gained, "Accent", HORIZONTAL_ALIGNMENT_RIGHT)
	gained_label.custom_minimum_size.x = 90.0
	var total_label := Style.label(total, "Muted", HORIZONTAL_ALIGNMENT_RIGHT)
	total_label.custom_minimum_size.x = 130.0
	return _row([Widgets.Medal.new(place), Widgets.Ball.new(Game.COLORS[slot], 52.0), name_label, gained_label, total_label])
