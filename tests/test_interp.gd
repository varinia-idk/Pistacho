extends SceneTree
## godot --headless --path . -s res://tests/test_interp.gd
## Bola a velocidad constante, estados a 60 Hz, red con jitter tipo Wi-Fi móvil (ráfagas retrasadas).
## Mide los tirones como desviación del avance por frame respecto al real, con el lerp de la spec
## y con la interpolación por instantáneas.

const Interp = preload("res://scripts/core/interpolation.gd")
const SPEED := 380.0
const SEND_HZ := 60.0
const DURATION := 6.0


func _init() -> void:
	var failures := 0
	# [nombre, probabilidad de ráfaga, retraso extra mín, máx]
	for net: Array in [["wifi normal", 0.05, 0.01, 0.04], ["wifi móvil con ahorro", 0.15, 0.04, 0.12]]:
		for fps in [60.0, 120.0]:
			var packets := _network(1234, net[1], net[2], net[3])
			var chase := _render_chase(packets, fps)
			var snapshots := _render_snapshots(packets, fps)
			print("test_interp %s %d fps | lerp spec: tirón p95 %.0f %%, máx %.0f %% | instantáneas: p95 %.0f %%, máx %.0f %%, retardo %.0f ms" % [
				net[0], fps, chase[0] * 100.0, chase[1] * 100.0, snapshots[0] * 100.0, snapshots[1] * 100.0, snapshots[2] * 1000.0])
			if snapshots[0] > 0.15 or snapshots[1] > 0.5 or snapshots[2] > 0.2:
				failures += 1
				printerr("instantáneas (%s, %d fps): demasiado irregular o retrasado" % [net[0], fps])
	failures += _check_teleport()
	print("test_interp: %d fallos" % failures)
	quit(1 if failures else 0)


## [tiempo de llegada, tiempo del anfitrión, x]; FIFO como un canal ordenado.
func _network(seed_value: int, burst_chance: float, burst_min: float, burst_max: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var packets := []
	var arrival := 0.0
	for k in int(DURATION * SEND_HZ):
		var sent := k / SEND_HZ
		var latency := 0.02 + rng.randf_range(0.0, 0.015)
		if rng.randf() < burst_chance:
			latency += rng.randf_range(burst_min, burst_max)  # Ráfagas tardías (ahorro de energía de la Wi-Fi).
		arrival = maxf(arrival, sent + latency)
		packets.append([arrival, sent, sent * SPEED])
	return packets


## Lerp exponencial hacia el último estado (spec §6).
func _render_chase(packets: Array, fps: float) -> Array:
	var x := 0.0
	var target := 0.0
	var next := 0
	var steps: Array[float] = []
	for frame in int(DURATION * fps):
		var now := frame / fps
		while next < packets.size() and packets[next][0] <= now:
			target = packets[next][2]
			next += 1
		var before := x
		x = lerpf(x, target, 1.0 - exp(-15.0 / fps))
		if now > 1.0:
			steps.append(x - before)
	return _jerk(steps, SPEED / fps) + [0.0]


func _render_snapshots(packets: Array, fps: float) -> Array:
	var clock := Interp.Clock.new()
	var track := Interp.Track.new()
	var next := 0
	var x := 0.0
	var steps: Array[float] = []
	var lag := 0.0
	var lag_samples := 0
	for frame in int(DURATION * fps):
		var now := frame / fps
		while next < packets.size() and packets[next][0] <= now:
			clock.observe(packets[next][1], packets[next][0], 1.0 / SEND_HZ, 0.04, 0.25)
			# Mismos campos que el juego: x, y, radio, flags, vx, vy (la velocidad permite extrapolar).
			track.push(packets[next][1], PackedFloat32Array([packets[next][2], 0.0, 20.0, 0.0, SPEED, 0.0]))
			next += 1
		if track.is_empty():
			continue
		var before := x
		var rendered := clock.render_time(now, 1.0 / fps)
		x = track.sample(rendered)[0]
		if now > 1.0:
			steps.append(x - before)
			lag += now - rendered
			lag_samples += 1
	var result := _jerk(steps, SPEED / fps)
	result.append(lag / lag_samples)
	return result


## [p95, máx] de |avance del frame / avance real − 1|.
func _jerk(steps: Array[float], expected: float) -> Array:
	var errors: Array[float] = []
	for step in steps:
		errors.append(absf(step / expected - 1.0))
	errors.sort()
	return [errors[int(errors.size() * 0.95)], errors[errors.size() - 1]]


## Una reaparición (salto grande) no debe dibujarse cruzando el mapa.
func _check_teleport() -> int:
	var track := Interp.Track.new()
	track.snap_distance = 80.0
	track.push(0.0, PackedFloat32Array([0.0, 0.0]))
	track.push(0.1, PackedFloat32Array([500.0, 0.0]))
	var middle := track.sample(0.04)[0]
	if middle != 0.0:
		printerr("teletransporte interpolado: x=%.0f" % middle)
		return 1
	return 0
