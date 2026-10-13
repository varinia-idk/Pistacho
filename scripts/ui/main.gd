extends Node
## Escena principal: mundo, cámara, menús, HUD y (solo en el editor) el overlay de ajustes finos.

const Style = preload("res://scripts/ui/style.gd")
const Menus = preload("res://scripts/ui/menus.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const DebugOverlay = preload("res://scripts/ui/debug_overlay.gd")
const HUD_TOP := 110.0
const HUD_RIGHT := 340.0

var world := Node2D.new()
var camera := Camera2D.new()
var menus: Menus
var hud: Hud


func _ready() -> void:
	RenderingServer.set_default_clear_color(Style.BG)
	world.name = "World"
	add_child(world)
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS  # Requerido por la interpolación física.
	add_child(camera)
	Game.world = world
	var theme := Style.build_theme()
	menus = Menus.new(theme)
	hud = Hud.new(theme)
	add_child(menus)
	add_child(hud)
	# Herramienta de desarrollo: no existe en el juego exportado.
	if OS.has_feature("editor"):
		add_child(DebugOverlay.new(theme))
	Game.round_started.connect(_frame_camera)
	get_viewport().size_changed.connect(_frame_camera)


## Centra el mapa en la zona libre del HUD; la geometría no depende de la pantalla.
func _frame_camera() -> void:
	if Game.mode == null:
		return
	var view := get_viewport().get_visible_rect().size
	var play := Rect2(0.0, HUD_TOP, view.x - HUD_RIGHT, view.y - HUD_TOP)
	camera.position = Game.mode.map_rect().get_center() - (play.get_center() - view * 0.5)
	camera.reset_physics_interpolation()


## Atrás de Android (y Escape en escritorio): pausa en partida, retrocede en menús, sale en el inicio.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		_back()


func _back() -> void:
	if Game.phase == Game.Phase.MENU or Game.phase == Game.Phase.LOBBY:
		if not menus.back():
			get_tree().quit()
	else:
		hud.toggle_pause()
