extends RefCounted
## Inclinación local: Input.get_gravity() en móvil, flechas en escritorio.
## Nunca integra el giroscopio; solo lo usa para detectar el gesto de dash.

const TiltMath = preload("res://scripts/input/tilt_math.gd")

var raw_gravity := Vector3.ZERO
var raw_gyro := Vector3.ZERO
var value := Vector2.ZERO        ## Salida procesada y suavizada [-1, 1].
var g0 := Vector3(0.0, 0.0, -1.0)
var calibrating := false
var use_sensors := OS.has_feature("mobile")

var _axes: Array[Vector3] = TiltMath.basis(Vector3(0.0, 0.0, -1.0))
var _calibration_sum := Vector3.ZERO
var _dash_pending := false
var _armed := true
var _hold_left := 0.0
var _held := Vector2.ZERO
var _clock := 0.0
var _history: Array[Vector3] = []  ## (tiempo, x, y) de la salida reciente.


func update(delta: float) -> void:
	_clock += delta
	raw_gravity = Input.get_gravity()
	raw_gyro = Input.get_gyroscope()
	var target := _from_gravity() if use_sensors else _from_keys()
	if calibrating:
		if raw_gravity.length() > 1.0:
			_calibration_sum += raw_gravity.normalized()
		target = Vector2.ZERO
	_detect_dash(delta)
	if not _armed:
		# Durante el giro brusco, mantener la inclinación previa: el gesto no desvía la dirección.
		value = _held
	else:
		var tau := Config.value("tilt_smooth_ms") / 1000.0
		value = target if tau <= 0.0 else value.lerp(target, 1.0 - exp(-delta / tau))
	_history.append(Vector3(_clock, value.x, value.y))
	while _history.size() > 2 and _history[0].x < _clock - 0.5:
		_history.pop_front()


func begin_calibration() -> void:
	calibrating = true
	_calibration_sum = Vector3.ZERO


func end_calibration() -> void:
	calibrating = false
	if _calibration_sum.length() > 0.5:
		g0 = _calibration_sum.normalized()
		_axes = TiltMath.basis(g0)
	value = Vector2.ZERO


## Devuelve true una vez por gesto de dash detectado.
func consume_dash() -> bool:
	var pending := _dash_pending
	_dash_pending = false
	return pending


func reset() -> void:
	value = Vector2.ZERO
	_dash_pending = false
	_armed = true


func _from_gravity() -> Vector2:
	if raw_gravity.length() < 1.0:
		return Vector2.ZERO
	# Componentes de (g − g0) en el plano tangente a g0 (ver tilt_math.gd).
	var v := TiltMath.project(raw_gravity.normalized(), _axes)
	if Config.flag("swap_xy"):
		v = Vector2(v.y, v.x)
	if Config.flag("invert_x"):
		v.x = -v.x
	if Config.flag("invert_y"):
		v.y = -v.y
	return TiltMath.shape(v, sin(deg_to_rad(Config.value("dead_zone_deg"))), sin(deg_to_rad(Config.value("saturation_deg"))), Config.value("response_exp"))


func _from_keys() -> Vector2:
	return Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))).limit_length(1.0)


func _detect_dash(delta: float) -> void:
	if not use_sensors or calibrating:
		return
	var threshold := Config.value("dash_gyro")
	var spin := raw_gyro.length()
	if _armed:
		if spin > threshold:
			_dash_pending = true
			_armed = false
			_held = _value_at(_clock - Config.value("dash_lookback"))
			_hold_left = Config.value("dash_hold")
	elif spin < threshold * 0.5:
		_hold_left -= delta
		if _hold_left <= 0.0:
			_armed = true


func _value_at(moment: float) -> Vector2:
	for k in range(_history.size() - 1, -1, -1):
		if _history[k].x <= moment:
			return Vector2(_history[k].y, _history[k].z)
	return Vector2(_history[0].y, _history[0].z) if not _history.is_empty() else value
