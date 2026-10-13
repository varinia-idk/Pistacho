extends SceneTree
## godot --headless --path . -s res://tests/test_tilt.gd

const TiltMath = preload("res://scripts/input/tilt_math.gd")
const TILT_DEG := 10.0


func _init() -> void:
	var failures := 0
	# Sostenido plano o inclinado hacia el jugador: inclinar 10° debe medir sin(10°) en las 4 direcciones.
	for hold in [0.0, 30.0, 45.0, 60.0]:
		var g0 := Vector3(0.0, 0.0, -1.0).rotated(Vector3.RIGHT, deg_to_rad(hold))
		var axes := TiltMath.basis(g0)
		# Girar el teléfono un ángulo sobre un eje perpendicular a g0 (cabeceo: eje X de la pantalla;
		# alabeo: eje horizontal hacia delante) gira la gravedad medida ese mismo ángulo.
		# Un giro positivo sobre axes[1] lleva la gravedad hacia −x; sobre axes[0], hacia +y.
		for turn: Array in [[axes[1], -1.0, Vector2.RIGHT], [axes[1], 1.0, Vector2.LEFT], [axes[0], 1.0, Vector2.DOWN], [axes[0], -1.0, Vector2.UP]]:
			var direction: Vector2 = turn[2]
			var g := g0.rotated(turn[0], deg_to_rad(TILT_DEG) * turn[1])
			var v := TiltMath.project(g, axes)
			if absf(v.length() - sin(deg_to_rad(TILT_DEG))) > 1e-4 or v.normalized().dot(direction) < 0.9999:
				failures += 1
				printerr("sujeción %.0f°, dirección %s: %s" % [hold, direction, v])
	# Curva: cero dentro de la zona muerta, 1 en saturación, monótona en medio.
	var dead := sin(deg_to_rad(1.5))
	var full := sin(deg_to_rad(15.0))
	if TiltMath.shape(Vector2(dead * 0.9, 0.0), dead, full, 1.25) != Vector2.ZERO:
		failures += 1
		printerr("zona muerta")
	if not is_equal_approx(TiltMath.shape(Vector2(0.0, full), dead, full, 1.25).length(), 1.0):
		failures += 1
		printerr("saturación")
	var previous := 0.0
	for k in range(1, 40):
		var out := TiltMath.shape(Vector2(full * k / 30.0, 0.0), dead, full, 1.25).length()
		if out < previous:
			failures += 1
			printerr("curva no monótona en %d" % k)
		previous = out
	print("test_tilt: %d fallos" % failures)
	quit(1 if failures else 0)
