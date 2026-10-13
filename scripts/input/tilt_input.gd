extends Node
const Filter = preload("res://scripts/input/tilt_filter.gd")
var filter := Filter.new()
var direction := Vector2.ZERO
var touch_direction := Vector2.ZERO
var sensitivity: float = 1.5
var source: String = "Teclado"
var manual_touch := false
var automatic_touch := false
var focused := true
var use_touch: bool:
	get:
		return manual_touch or automatic_touch
	set(value):
		manual_touch = value
		automatic_touch = false
		touch_direction = Vector2.ZERO
		direction = Vector2.ZERO

func _ready() -> void:
	# Read sensors before Session consumes input in the same physics tick.
	process_physics_priority = -100
	var config := ConfigFile.new()
	if config.load("user://controls.cfg") == OK:
		var saved := float(config.get_value("controls", "sensitivity", 1.5))
		sensitivity = clampf(saved, 0.6, 3.0) if is_finite(saved) else 1.5
	calibrate()

func _physics_process(delta: float) -> void:
	if not focused:
		direction = Vector2.ZERO
		return
	if OS.has_feature("mobile"):
		update_sensors(Input.get_gravity(), Input.get_accelerometer(), Input.get_gyroscope(), delta)
	else:
		direction = Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))).limit_length()
		source = "Teclado"
	if use_touch:
		direction = touch_direction.limit_length()
		source = "Táctil" if manual_touch else "Sin sensores · táctil"

func update_sensors(gravity: Vector3, acceleration: Vector3, gyro: Vector3, delta: float) -> void:
	if not focused:
		direction = Vector2.ZERO
		return
	direction = filter.sample(gravity, acceleration, gyro, delta, sensitivity)
	# Recovery must not overwrite a deliberate choice of touch controls.
	automatic_touch = filter.missing_seconds >= 1.0
	source = filter.sensor_name
	if use_touch:
		direction = touch_direction.limit_length()
		source = "Táctil" if manual_touch else "Sin sensores · táctil"

func calibrate() -> void:
	filter.calibrate()
	direction = Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		focused = false
		direction = Vector2.ZERO
		touch_direction = Vector2.ZERO
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		focused = true
		filter.resume()
		automatic_touch = false

func save_sensitivity(value: float) -> void:
	sensitivity = clampf(value, 0.6, 3.0) if is_finite(value) else 1.5
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", sensitivity)
	config.save("user://controls.cfg")
