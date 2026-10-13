extends Node
## Escena principal: mundo, cámara, HUD y overlay de debug.

const Hud = preload("res://scripts/ui/hud.gd")
const DebugOverlay = preload("res://scripts/ui/debug_overlay.gd")
const HUD_TOP := 80.0
const HUD_RIGHT := 280.0

var world := Node2D.new()
var camera := Camera2D.new()


func _ready() -> void:
	world.name = "World"
	add_child(world)
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS  # Requerido por la interpolación física.
	add_child(camera)
	Game.world = world
	var theme := Theme.new()
	theme.default_font_size = 30
	add_child(Hud.new(theme))
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
