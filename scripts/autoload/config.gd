extends Node
## Todos los números de jugabilidad: {clave: [valor, min, max]}.
## Un valor por defecto entero define un slider de paso 1 (0/1 = interruptor).

signal changed(key: String)

const PATH := "user://config.json"
## Subir al cambiar el significado de una clave: los ajustes guardados con otra versión se descartan.
const VERSION := 2
const DEFAULTS := {
	# Control
	"swap_xy": [0, 0, 1],
	"invert_x": [0, 0, 1],
	"invert_y": [1, 0, 1],
	"dead_zone_deg": [1.5, 0.0, 10.0],
	"saturation_deg": [15.0, 5.0, 60.0],
	"response_exp": [1.25, 1.0, 3.0],
	"tilt_smooth_ms": [50.0, 0.0, 200.0],
	"dash_gyro": [4.0, 1.5, 12.0],
	"dash_lookback": [0.1, 0.0, 0.3],
	"dash_hold": [0.15, 0.0, 0.5],
	"dash_cooldown": [1.5, 0.3, 5.0],
	"dash_speed": [550.0, 50.0, 1000.0],
	"dash_boost_time": [0.45, 0.05, 1.0],
	"vibration": [1, 0, 1],
	"hit_vibe_dv": [140.0, 20.0, 600.0],
	# Física
	"player_radius": [20.0, 14.0, 32.0],
	"tilt_accel": [1100.0, 200.0, 3000.0],
	"max_speed": [380.0, 120.0, 900.0],
	"damping": [1.0, 0.0, 6.0],
	"friction": [0.1, 0.0, 1.0],
	"player_bounce": [0.6, 0.0, 1.0],   # Rebote resultante entre jugadores.
	"wall_bounce": [0.3, 0.0, 1.0],     # Rebote resultante contra paredes.
	# Partida
	"rounds": [5, 1, 15],
	"round_time": [120.0, 30.0, 300.0],
	"fall_time": [1.0, 0.3, 3.0],
	"invuln_time": [1.0, 0.0, 3.0],
	"bot_skill": [0.75, 0.1, 1.0],
	"bot_corner": [0.35, 0.1, 1.0],
	# Laberinto
	"maze_corridor": [1.6, 1.6, 3.0],
	"maze_wall": [0.3, 0.3, 1.0],
	"maze_newest": [0.85, 0.0, 1.0],
	"maze_straight": [0.4, 0.0, 0.95],
	"maze_braid": [0.35, 0.0, 1.0],
	"maze_min_path": [1.3, 1.0, 3.0],
	"maze_alt_ratio": [1.3, 1.0, 2.0],
	"maze_holes": [5, 0, 12],
	"hole_radius": [1.5, 1.0, 2.5],
	"hole_pass": [14.0, 4.0, 40.0],
	"respawn_back": [3, 0, 10],
	"collapse_start": [60.0, 10.0, 180.0],
	"collapse_rate": [1.2, 0.2, 5.0],
	"warn_time": [1.2, 1.0, 1.5],
	# Espiral
	"spiral_points": [400, 200, 800],
	"spiral_turns": [3.5, 3.0, 4.0],
	"spiral_noise": [0.35, 0.0, 1.0],
	"spiral_width_min": [2.0, 2.0, 3.0],
	"spiral_width_max": [3.0, 2.0, 3.0],
}

var _values: Dictionary[String, float] = {}


## Valores por defecto sin depender del autoload (útil en tests headless).
static func defaults() -> Dictionary[String, float]:
	var result: Dictionary[String, float] = {}
	for key: String in DEFAULTS:
		result[key] = float(DEFAULTS[key][0])
	return result


func _ready() -> void:
	_values = defaults()
	load_file()


func value(key: String) -> float:
	return _values[key]


func flag(key: String) -> bool:
	return _values[key] >= 0.5


func count(key: String) -> int:
	return roundi(_values[key])


func is_integer(key: String) -> bool:
	return typeof(DEFAULTS[key][0]) == TYPE_INT


func range_of(key: String) -> Vector2:
	return Vector2(DEFAULTS[key][1], DEFAULTS[key][2])


func snapshot() -> Dictionary[String, float]:
	return _values.duplicate()


func set_value(key: String, new_value: float) -> void:
	if not DEFAULTS.has(key) or not is_finite(new_value):
		return
	var limits := range_of(key)
	var clamped := clampf(new_value, limits.x, limits.y)
	if is_integer(key):
		clamped = roundf(clamped)
	if _values[key] == clamped:
		return
	_values[key] = clamped
	changed.emit(key)


func reset() -> void:
	_values = defaults()
	changed.emit("")


## Solo guarda lo que difiere del valor por defecto: los cambios de defaults llegan a quien no tocó esa clave.
func save_file() -> void:
	var overrides := {"_version": VERSION}
	var base := defaults()
	for key: String in _values:
		if _values[key] != base[key]:
			overrides[key] = _values[key]
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("No se pudo guardar %s: %s" % [PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(overrides, "\t", true))


func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_warning("Ignorando %s: JSON inválido" % PATH)
		return
	if parsed.get("_version", 0) != VERSION:
		push_warning("Ignorando %s: guardado con otra versión de Config" % PATH)
		return
	for key: Variant in parsed:
		var stored: Variant = parsed[key]
		if key is String and (stored is float or stored is int):
			set_value(key, float(stored))
