extends SceneTree
const Filter = preload("res://scripts/input/tilt_filter.gd")
const Tilt = preload("res://scripts/input/tilt_input.gd")
const FLAT := Vector3(0, 0, -9.81)
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TILT FAIL: " + label)

func settle(filter, gravity: Vector3, seconds: float = 0.6, hz: int = 60, acceleration_only: bool = false) -> Vector2:
	for i in range(ceili(seconds * hz)):
		filter.sample(Vector3.ZERO if acceleration_only else gravity, gravity, Vector3.ZERO, 1.0 / hz, 1.5)
	return filter.direction

func _initialize() -> void:
	# Known physical poses: lower right edge => +X, lower bottom edge => +Y.
	for hz in [30, 60, 120]:
		for pitch in [0.0, 45.0, 75.0]:
			var filter = Filter.new()
			var neutral := FLAT.rotated(Vector3.RIGHT, -deg_to_rad(pitch))
			settle(filter, neutral, 0.6, hz)
			check(not filter.calibrating and filter.direction == Vector2.ZERO, "calibrated neutral %sHz/%sdeg" % [hz, pitch])
			# Rotate about world-up projected along the phone (its top-to-bottom axis when flat).
			var right_tilt := neutral.rotated(Vector3.RIGHT.cross(neutral).normalized(), -deg_to_rad(6.0))
			var value := settle(filter, right_tilt, 0.15, hz)
			check(value.x > 0.24 and absf(value.y) < 0.01, "6deg right responds within150ms %s/%s: %s" % [hz, pitch, value])
			value = settle(filter, neutral.rotated(Vector3.RIGHT, -deg_to_rad(6.0)), 0.5, hz)
			check(value.y > 0.27 and absf(value.x) < 0.01, "6deg down at pitched neutral")
			value = settle(filter, neutral.rotated(Vector3.RIGHT, deg_to_rad(6.0)), 0.5, hz)
			check(value.y < -0.27, "6deg up")
			value = settle(filter, neutral.rotated(Vector3.RIGHT.cross(neutral).normalized(), deg_to_rad(18.0)), 0.6, hz)
			check(value.x < -0.99, "18deg reaches full left speed")
			check(settle(filter, neutral, 0.5, hz).length() == 0.0, "return to neutral stops")
	var noisy = Filter.new()
	settle(noisy, FLAT)
	var maximum_noise := 0.0
	for i in range(240):
		var reading := FLAT + Vector3(sin(i * 0.7), cos(i * 1.3), 0) * 0.09
		maximum_noise = maxf(maximum_noise, noisy.sample(reading, reading, Vector3.ZERO, 1.0 / 60, 1.5).length())
	check(maximum_noise == 0.0, "stationary sensor noise does not move player")
	var accel = Filter.new()
	settle(accel, FLAT, 0.6, 60, true)
	check(settle(accel, FLAT.rotated(Vector3.UP, -deg_to_rad(6)), 0.15, 60, true).x > 0.19, "accelerometer-only response within150ms")
	var gyro_filter = Filter.new()
	settle(gyro_filter, FLAT)
	# Fast 12deg turn in100ms: delayed gravity, immediate gyro prediction.
	for i in range(6):
		gyro_filter.sample(FLAT, FLAT, Vector3(0, deg_to_rad(120), 0), 1.0 / 60, 1.5)
	check(gyro_filter.direction.x > 0.4, "gyro anticipates delayed gravity during turn")
	var held := FLAT.rotated(Vector3.UP, -deg_to_rad(12))
	var held_value := settle(gyro_filter, held, 2.0)
	check(held_value.x > 0.63 and held_value.x < 0.66, "held tilt remains stable after gyro stops")
	for i in range(60):
		gyro_filter.sample(held, held, Vector3(0, 0.008, 0), 1.0 / 60, 1.5)
	check(absf(gyro_filter.direction.x - held_value.x) < 0.02, "gravity corrects gyro bias")
	# Adapter regressions: delayed sensor startup, explicit touch, focus, corruption.
	var tilt = Tilt.new()
	for i in range(120):
		tilt.update_sensors(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0 / 60)
	check(tilt.use_touch and tilt.filter.calibrating, "late startup uses temporary fallback without zero calibration")
	for i in range(40):
		tilt.update_sensors(FLAT, FLAT, Vector3.ZERO, 1.0 / 60)
	check(not tilt.use_touch and not tilt.filter.calibrating, "late sensors automatically recover")
	for i in range(30):
		tilt.update_sensors(held, held, Vector3.ZERO, 1.0 / 60)
	check(tilt.direction.x > 0.6, "input moves after late recovery")
	for i in range(15):
		tilt.update_sensors(Vector3(NAN, 0, 0), Vector3.ZERO, Vector3(INF, 0, 0), 1.0 / 60)
	check(tilt.direction == Vector2.ZERO, "invalid/missing data stops movement")
	tilt.update_sensors(held, held, Vector3.ZERO, 1.0 / 60)
	check(tilt.direction.x > 0.6, "dropout recovery retains original calibration")
	tilt.use_touch = true
	tilt.touch_direction = Vector2.LEFT
	tilt.update_sensors(held, held, Vector3.ZERO, 1.0 / 60)
	check(tilt.use_touch and tilt.direction == Vector2.LEFT, "sensor recovery preserves explicit touch choice")
	tilt.use_touch = false
	tilt._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	tilt.update_sensors(held, held, Vector3.ZERO, 1.0 / 60)
	check(tilt.direction == Vector2.ZERO, "background sensor calls cannot restore movement")
	tilt._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	tilt.update_sensors(FLAT, FLAT, Vector3.ZERO, 1.0 / 60)
	check(tilt.direction == Vector2.ZERO and tilt.focused, "focus recovery drops stale movement")
	tilt.calibrate()
	for i in range(35):
		tilt.update_sensors(held, held, Vector3.ZERO, 1.0 / 60)
	check(not tilt.filter.calibrating and tilt.direction == Vector2.ZERO, "manual recalibration averages a new neutral pose")
	tilt.sensitivity = NAN
	tilt.update_sensors(FLAT, FLAT, Vector3.ZERO, 1.0 / 60)
	check(tilt.direction.is_finite(), "invalid sensitivity cannot poison input")
	tilt.free()
	print("TILT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
