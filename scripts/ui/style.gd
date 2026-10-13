extends RefCounted
## Identidad visual: paleta tomada del icono y tema de la interfaz construido por código.

const BG := Color("0b1c24")
const BG_2 := Color("102630")
const PANEL := Color("14303a")
const PANEL_2 := Color("1c404c")
const LINE := Color("284a54")
const MINT := Color("67e4bc")
const MINT_LIGHT := Color("96f2d4")
const GOLD := Color("fbd88c")
const SILVER := Color("c9d6df")
const BRONZE := Color("e3a573")
const TEXT := Color("e8f6f3")
const MUTED := Color("8fb3b5")
const INK := Color("0b1c24")
const WARN := Color("ff9a5c")
const VERSION := "v0.1"


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 30
	theme.default_font = font(0.45)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_constant("outline_size", "Label", 0)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "Button", _button_box(state, PANEL_2))
		theme.set_stylebox(state, "PrimaryButton", _button_box(state, MINT))
	theme.set_type_variation("PrimaryButton", "Button")
	for kind: String in ["Button", "PrimaryButton"]:
		var ink := INK if kind == "PrimaryButton" else TEXT
		for slot: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			theme.set_color(slot, kind, ink)
		theme.set_color("font_disabled_color", kind, Color(ink, 0.4))
	theme.set_stylebox("panel", "PanelContainer", card_box(PANEL))
	theme.set_type_variation("Pill", "PanelContainer")
	theme.set_stylebox("panel", "Pill", _box(Color(PANEL, 0.88), 999, 22, 10))
	theme.set_stylebox("normal", "LineEdit", _box(BG_2, 20, 24, 18, LINE))
	theme.set_stylebox("focus", "LineEdit", _box(BG_2, 20, 24, 18, MINT))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", MINT)
	theme.set_stylebox("slider", "HSlider", _box(BG_2, 999, 0, 8))
	theme.set_stylebox("grabber_area", "HSlider", _box(MINT, 999, 0, 8))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(MINT_LIGHT, 999, 0, 8))
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", TEXT)
	theme.set_color("font_pressed_color", "CheckButton", TEXT)
	theme.set_color("font_hover_pressed_color", "CheckButton", TEXT)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	_label(theme, "Title", 140, TEXT, font(1.2))
	_label(theme, "Heading", 56, TEXT, font(0.9))
	_label(theme, "Muted", 26, MUTED, null)
	_label(theme, "Accent", 34, MINT, font(0.7))
	return theme


## Fuente por defecto de Godot engrosada: sin archivos de fuente externos.
static func font(embolden: float) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = embolden
	return variation


static func card_box(color: Color) -> StyleBoxFlat:
	var box := _box(color, 34, 40, 34)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 24
	box.shadow_offset = Vector2(0, 10)
	box.border_color = Color(MINT, 0.12)
	box.set_border_width_all(2)
	return box


static func _box(color: Color, radius: int, margin_x: float, margin_y: float, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	box.anti_aliasing = true
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(3)
	return box


static func _button_box(state: String, color: Color) -> StyleBox:
	if state == "focus":
		return StyleBoxEmpty.new()
	var tint := color
	match state:
		"hover":
			tint = color.lightened(0.12)
		"pressed":
			tint = color.darkened(0.18)
		"disabled":
			tint = Color(color.darkened(0.3), 0.5)
	var box := _box(tint, 30, 34, 22)
	# Borde inferior más oscuro: botón con volumen; al pulsar se "hunde".
	box.border_color = color.darkened(0.35)
	box.border_width_bottom = 0 if state == "pressed" else 6
	return box


static func _label(theme: Theme, kind: String, size: int, color: Color, face: Font) -> void:
	theme.set_type_variation(kind, "Label")
	theme.set_font_size("font_size", kind, size)
	theme.set_color("font_color", kind, color)
	if face:
		theme.set_font("font", kind, face)


static func button(text: String, primary := false, width := 520.0) -> Button:
	var node := Button.new()
	node.text = text
	node.theme_type_variation = "PrimaryButton" if primary else ""
	node.custom_minimum_size = Vector2(width, 104.0)
	node.focus_mode = Control.FOCUS_NONE
	return node


static func label(text: String, kind := "", align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var node := Label.new()
	node.text = text
	node.theme_type_variation = kind
	node.horizontal_alignment = align
	return node
