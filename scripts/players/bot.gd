extends RefCounted
## Bot: convierte la velocidad deseada por el modo en inclinación + eventos, igual que un humano.

var slot := 0
var tilt := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _noise := Vector2.ZERO
var _noise_left := 0.0
var _blocked_for := 0.0
var _backoff_left := 0.0
var _backoff_dir := Vector2.ZERO


func _init(slot_value: int, seed_value: int) -> void:
	slot = slot_value
	_rng.seed = seed_value


func think(mode: Node, player: RigidBody2D, delta: float) -> void:
	var skill := Config.value("bot_skill")
	var desired: Vector2 = mode.bot_desired_velocity(player)
	desired = _unstick(mode, player, desired, delta)
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
	if _backoff_left <= 0.0 and mode.bot_wants_dash(player) and _rng.randf() < skill * delta * 3.0:
		Game.action(slot, Game.Action.DASH)


## Ceder el paso: si quiere avanzar pero lleva bot_patience s casi quieto (atasco con otro jugador
## o contra una esquina), retrocede un tiempo aleatorio alejándose de quien lo bloquea y reintenta.
## Ante un humano siempre cede; entre bots cede solo el que va detrás, así nunca ceden ambos a la vez.
func _unstick(mode: Node, player: RigidBody2D, desired: Vector2, delta: float) -> Vector2:
	if player.state != player.State.ALIVE:
		_blocked_for = 0.0
		_backoff_left = 0.0
		return desired
	if _backoff_left > 0.0:
		_backoff_left -= delta
		return _backoff_dir * Config.value("max_speed") * 0.5
	if desired.length() < 80.0 or player.linear_velocity.length() > 30.0:
		_blocked_for = 0.0
		return desired
	_blocked_for += delta
	var patience := Config.value("bot_patience")
	if _blocked_for < patience:
		return desired
	_blocked_for = 0.0
	var blocker: RigidBody2D = null
	var nearest: float = 3.0 * player.radius
	for other in mode.players:
		var gap: float = other.position.distance_to(player.position)
		if other != player and gap < nearest:
			nearest = gap
			blocker = other
	if blocker and blocker.is_bot and _goes_first(mode, player, blocker):
		return desired
	var away := -desired.normalized() if blocker == null else (player.position - blocker.position).normalized()
	_backoff_left = _rng.randf_range(patience, patience * 2.5)
	_backoff_dir = away.rotated(_rng.randf_range(-0.6, 0.6))
	return _backoff_dir * Config.value("max_speed") * 0.5


func _goes_first(mode: Node, player: RigidBody2D, other: RigidBody2D) -> bool:
	var mine: float = mode.progress_left(player)
	var theirs: float = mode.progress_left(other)
	return mine < theirs or (mine == theirs and player.slot < other.slot)
