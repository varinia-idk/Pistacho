extends RefCounted
## Godot Android remaps sensors to screen axes: gravity +X right, +Y up, -Z in.
## Gyroscope is angular velocity in rad/s; no second landscape rotation is needed.
const CALIBRATION_SECONDS := 0.35
const DEAD_ANGLE := deg_to_rad(1.2)
const FULL_ANGLE := deg_to_rad(18.0)
var direction := Vector2.ZERO
var gravity_estimate := Vector3.ZERO
var neutral := Vector3.ZERO
var right_axis := Vector3.RIGHT
var down_axis := Vector3.DOWN
var calibrating := true
var missing_seconds := 0.0
var sensor_name := "Preparando sensores"
var _sample_sum := Vector3.ZERO
var _stable_seconds := 0.0
var _gyro_seen := false

func calibrate() -> void:
	calibrating = true
	_sample_sum = Vector3.ZERO
	_stable_seconds = 0.0
	direction = Vector2.ZERO

func resume() -> void:
	# Keep the neutral pose; discard stale estimates after suspension.
	gravity_estimate = Vector3.ZERO
	missing_seconds = 0.0
	direction = Vector2.ZERO
	_gyro_seen = false
	if calibrating:
		calibrate()

func sample(gravity: Vector3, acceleration: Vector3, gyro: Vector3, delta: float, sensitivity: float) -> Vector2:
	if not is_finite(delta) or delta <= 0.0:
		return direction
	var dt := minf(delta, 0.05)
	var has_gravity := _valid_gravity(gravity)
	var measured := gravity if has_gravity else acceleration
	if not _valid_gravity(measured):
		missing_seconds += delta
		sensor_name = "Esperando sensores"
		if calibrating:
			_sample_sum = Vector3.ZERO
			_stable_seconds = 0.0
		if missing_seconds >= 0.15:
			direction = Vector2.ZERO
			gravity_estimate = Vector3.ZERO
		return direction
	missing_seconds = 0.0
	sensor_name = "Inclinación" if has_gravity else "Inclinación · acelerómetro"
	measured = measured.normalized()
	var valid_gyro := gyro.is_finite() and gyro.length() < 20.0
	if valid_gyro and gyro.length() > 0.001:
		_gyro_seen = true
	if gravity_estimate == Vector3.ZERO:
		gravity_estimate = measured
	else:
		# World-fixed gravity rotates opposite to the phone's angular velocity.
		if valid_gyro and gyro.length() > 0.001:
			gravity_estimate = gravity_estimate.rotated(gyro.normalized(), -gyro.length() * dt)
		var correction_rate := 18.0 if has_gravity else 10.0
		if _gyro_seen and valid_gyro:
			correction_rate = 6.0 if has_gravity else 2.5
		gravity_estimate = gravity_estimate.slerp(measured, 1.0 - exp(-correction_rate * dt)).normalized()
	if calibrating:
		# Average a stable interval, never calibrate against missing/zero data.
		if (_sample_sum != Vector3.ZERO and _sample_sum.normalized().angle_to(measured) > deg_to_rad(2.0)) or (valid_gyro and gyro.length() > 0.2):
			_sample_sum = Vector3.ZERO
			_stable_seconds = 0.0
		_sample_sum += measured * dt
		_stable_seconds += dt
		sensor_name = "Calibrando · mantén quieto"
		if _stable_seconds >= CALIBRATION_SECONDS:
			neutral = _sample_sum.normalized()
			right_axis = Vector3.RIGHT - neutral * neutral.x
			if right_axis.length() < 0.15:
				calibrate()
				sensor_name = "Coloca el móvil horizontal"
				return Vector2.ZERO
			right_axis = right_axis.normalized()
			down_axis = neutral.cross(right_axis).normalized()
			gravity_estimate = neutral
			calibrating = false
		return Vector2.ZERO
	# Tangent axes retain sensitivity when held at a comfortable pitched angle.
	var forward := gravity_estimate.dot(neutral)
	var angles := Vector2(atan2(gravity_estimate.dot(right_axis), forward), atan2(gravity_estimate.dot(down_axis), forward))
	var magnitude := angles.length()
	var gain := clampf(sensitivity, 0.6, 3.0) / 1.5 if is_finite(sensitivity) else 1.0
	var amount := clampf((magnitude - DEAD_ANGLE) / (FULL_ANGLE - DEAD_ANGLE) * gain, 0.0, 1.0)
	direction = angles.normalized() * amount if magnitude > DEAD_ANGLE else Vector2.ZERO
	return direction

func _valid_gravity(value: Vector3) -> bool:
	# Reject free fall, absent sensors, NaNs and violent acceleration spikes.
	return value.is_finite() and value.length() >= 6.0 and value.length() <= 14.0
