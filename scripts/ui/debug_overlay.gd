extends CanvasLayer
## Overlay de debug: un HSlider por clave de Config, generado automáticamente, y lecturas en vivo.

var root := Control.new()
var panel := PanelContainer.new()
var readout := Label.new()
var sliders: Dictionary[String, HSlider] = {}
var value_labels: Dictionary[String, Label] = {}


func _init(theme: Theme) -> void:
	layer = 10
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var toggle := Button.new()
	toggle.text = "DBG"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.position = Vector2(12.0, 12.0)
	toggle.custom_minimum_size = Vector2(84.0, 60.0)
	toggle.add_theme_font_size_override("font_size", 22)
	toggle.pressed.connect(_toggle)
	root.add_child(toggle)
	panel.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 12.0
	panel.offset_top = 84.0
	panel.offset_right = 860.0
	panel.offset_bottom = -12.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.09, 0.92)
	style.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	readout.add_theme_font_size_override("font_size", 22)
	box.add_child(readout)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	for entry: Array in [["Guardar", Config.save_file], ["Restablecer", Config.reset]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(220.0, 64.0)
		button.pressed.connect(entry[1])
		buttons.add_child(button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for key: String in Config.DEFAULTS:
		list.add_child(_row(key))
	Config.changed.connect(_sync)


func _row(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = key
	name_label.custom_minimum_size.x = 290.0
	name_label.add_theme_font_size_override("font_size", 22)
	row.add_child(name_label)
	var limits := Config.range_of(key)
	var slider := HSlider.new()
	slider.min_value = limits.x
	slider.max_value = limits.y
	slider.step = 1.0 if Config.is_integer(key) else (limits.y - limits.x) / 200.0
	slider.value = Config.value(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 56.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void: Config.set_value(key, v))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 110.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 22)
	row.add_child(value_label)
	sliders[key] = slider
	value_labels[key] = value_label
	_sync(key)
	return row


func _sync(key: String) -> void:
	for k: String in ([key] if key else sliders.keys()):
		var current := Config.value(k)
		sliders[k].set_value_no_signal(current)
		value_labels[k].text = str(int(current)) if Config.is_integer(k) else "%.2f" % current


func _toggle() -> void:
	panel.visible = not panel.visible
	if not panel.visible:
		Config.save_file()


func _process(_delta: float) -> void:
	if not panel.visible:
		return
	var g := Game.tilt.raw_gravity
	var w := Game.tilt.raw_gyro
	var t := Game.tilt.value
	var net := get_node_or_null("/root/Net")
	var ping := "%d ms" % net.get("ping_ms") if net else "—"
	readout.text = "gravedad cruda  (%.2f, %.2f, %.2f)  |g| %.2f\ngiroscopio  (%.2f, %.2f, %.2f) rad/s\ninclinación  (%.2f, %.2f)  %s\nFPS %d · ping %s  %s" % [
		g.x, g.y, g.z, g.length(), w.x, w.y, w.z, t.x, t.y,
		"calibrando" if Game.tilt.calibrating else "", Engine.get_frames_per_second(), ping, Game.net_stats()]
