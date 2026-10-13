extends RefCounted
## Bot: convierte la velocidad deseada por el modo en inclinación + eventos, igual que un humano.

var slot := 0
var tilt := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _noise := Vector2.ZERO
var _noise_left := 0.0


func _init(slot_value: int, seed_value: int) -> void:
	slot = slot_value
	_rng.seed = seed_value


func think(mode: Node, player: RigidBody2D, delta: float) -> void:
	var skill := Config.value("bot_skill")
	var desired: Vector2 = mode.bot_desired_velocity(player)
	# Inclinación necesaria para corregir la velocidad en ~0.25 s.
	var target := ((desired - player.linear_velocity) / (Config.value("tilt_accel") * 0.25)).limit_length(1.0)
	_noise_left -= delta
	if _noise_left <= 0.0:
		_noise = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * (1.0 - skill) * 0.8
		_noise_left = _rng.randf_range(0.25, 0.6)
	target = (target + _noise).limit_length(1.0)
	var reaction := 0.05 + (1.0 - skill) * 0.2
	tilt = tilt.lerp(target, 1.0 - exp(-delta / reaction))
	Game.set_input(slot, tilt)
	if mode.bot_wants_dash(player) and _rng.randf() < skill * delta * 3.0:
		Game.action(slot, Game.Action.DASH)
