extends RigidBody2D
## Cuerpo físico de un jugador (solo en el anfitrión). La inclinación aplica fuerza; nunca se asigna posición.

signal hit(strength: float)
signal fell

enum State { ALIVE, FALLING }

const PlayerView = preload("res://scripts/players/player_view.gd")
const LAYER_WALLS := 1
const LAYER_PLAYERS := 2
const LAYER_GHOST := 4

var slot := 0
var radius := 20.0
var tilt := Vector2.ZERO        ## Input procesado [-1, 1], humano o bot.
var state := State.ALIVE
var clock := 0.0                ## Tiempo del modo, actualizado en cada paso.
var dash_ready_at := 0.0
var boost_until := 0.0
var invuln_until := 0.0
var fall_until := 0.0
var respawn_at := Vector2.ZERO
var ghost := false
var view: PlayerView

var _shape := CircleShape2D.new()
var _teleport := false
var _teleport_to := Vector2.ZERO
var _hold := false
var _dashed := false
var _speed_cap := 0.0
var _last_velocity := Vector2.ZERO


## Llamar antes de añadir al árbol.
func setup(slot_value: int, color: Color, local: bool) -> void:
	slot = slot_value
	name = "Player%d" % slot
	gravity_scale = 0.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	lock_rotation = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	physics_material_override = PhysicsMaterial.new()
	radius = Config.value("player_radius")
	_shape.radius = radius
	var collider := CollisionShape2D.new()
	collider.shape = _shape
	add_child(collider)
	view = PlayerView.new()
	view.color = color
	view.radius = radius
	view.is_local = local
	add_child(view)
	_set_layers(false)
	_apply_config("")
	Config.changed.connect(_apply_config)


func _apply_config(_key: String) -> void:
	linear_damp = Config.value("damping")
	physics_material_override.friction = Config.value("friction")
	physics_material_override.bounce = Config.value("player_bounce")


## Paso de reglas comunes; lo llama GameMode.physics_step antes del paso físico.
func step(time: float) -> void:
	clock = time
	if state == State.FALLING and time >= fall_until:
		state = State.ALIVE
		_hold = false
		teleport(respawn_at)
		invuln_until = time + Config.value("invuln_time")
		_set_layers(true)
	var max_speed := Config.value("max_speed")
	var boost := 0.0
	if time < boost_until:
		boost = Config.value("dash_speed") * (boost_until - time) / Config.value("dash_boost_time")
	_speed_cap = max_speed + boost
	if state == State.ALIVE:
		apply_central_force(tilt * Config.value("tilt_accel") * mass)
	_update_view()


func dash(time: float) -> bool:
	if state != State.ALIVE or time < dash_ready_at:
		return false
	var direction := tilt if tilt.length() > 0.15 else linear_velocity
	if direction.length() < 0.001:
		return false
	apply_central_impulse(direction.normalized() * Config.value("dash_speed") * mass)
	dash_ready_at = time + Config.value("dash_cooldown")
	boost_until = time + Config.value("dash_boost_time")
	_dashed = true
	return true


func start_fall(time: float, respawn: Vector2) -> void:
	if state == State.FALLING:
		return
	state = State.FALLING
	fall_until = time + Config.value("fall_time")
	respawn_at = respawn
	_hold = true
	collision_layer = 0
	collision_mask = 0
	fell.emit()


func is_invulnerable() -> bool:
	return clock < invuln_until


## Teletransporte seguro: se aplica en _integrate_forces.
func teleport(target: Vector2) -> void:
	_teleport = true
	_teleport_to = target


## Fantasma: sin choques con otros jugadores mientras dura la invulnerabilidad.
func _set_layers(as_ghost: bool) -> void:
	ghost = as_ghost
	collision_layer = LAYER_GHOST if as_ghost else LAYER_PLAYERS
	collision_mask = LAYER_WALLS if as_ghost else LAYER_WALLS | LAYER_PLAYERS


## Termina el modo fantasma solo cuando ya no se solapa con nadie.
func try_solidify(others: Array) -> void:
	if not ghost or state != State.ALIVE or is_invulnerable():
		return
	for other in others:
		if other != self and other.position.distance_to(position) < radius + other.radius:
			return
	_set_layers(false)


func _integrate_forces(body: PhysicsDirectBodyState2D) -> void:
	if _teleport:
		body.transform = Transform2D(0.0, _teleport_to)
		body.linear_velocity = Vector2.ZERO
		_teleport = false
		_last_velocity = Vector2.ZERO
		reset_physics_interpolation.call_deferred()
		return
	if _hold:
		body.linear_velocity = Vector2.ZERO
	if _speed_cap > 0.0 and body.linear_velocity.length() > _speed_cap:
		body.linear_velocity = body.linear_velocity.limit_length(_speed_cap)
	var change := (body.linear_velocity - _last_velocity).length()
	if not _dashed and body.get_contact_count() > 0 and change > Config.value("hit_vibe_dv"):
		hit.emit(change)
	_dashed = false
	_last_velocity = body.linear_velocity


func _update_view() -> void:
	view.falling = 0.0 if state != State.FALLING else clampf(1.0 - (fall_until - clock) / Config.value("fall_time"), 0.0, 1.0)
	view.invulnerable = ghost or is_invulnerable()
	var cooldown := Config.value("dash_cooldown")
	view.dash_ready = clampf(1.0 - (dash_ready_at - clock) / cooldown, 0.0, 1.0)
	if linear_velocity.length() > 20.0:
		view.heading = linear_velocity.normalized()
	elif tilt.length() > 0.1:
		view.heading = tilt.normalized()
