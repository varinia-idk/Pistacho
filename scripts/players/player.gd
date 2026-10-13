extends RigidBody2D
## Cuerpo físico de un jugador. Autoritativo en el anfitrión; en un cliente, solo la predicción de su propia bola.
## La inclinación aplica fuerza; nunca se asigna posición.

signal hit(strength: float)
signal fell
signal dashed

enum State { ALIVE, FALLING }

const PlayerView = preload("res://scripts/players/player_view.gd")
const LAYER_WALLS := 1
const LAYER_PLAYERS := 2
const LAYER_GHOST := 4

var slot := 0
var is_bot := false
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
## Parámetros de física: Config en vivo (anfitrión) o la cfg de la ronda (predicción en cliente).
var params: Dictionary[String, float]

var _shape := CircleShape2D.new()
var _teleport := false
var _teleport_to := Vector2.ZERO
var _hold := false
var _dashed := false
var _speed_cap := 0.0
var _last_velocity := Vector2.ZERO
var _correction := Vector2.ZERO
var _velocity_correction := Vector2.ZERO


## Llamar antes de añadir al árbol.
func setup(slot_value: int, color: Color, local: bool, physics_params: Dictionary[String, float]) -> void:
	slot = slot_value
	params = physics_params
	name = "Player%d" % slot
	gravity_scale = 0.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	lock_rotation = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	physics_material_override = PhysicsMaterial.new()
	radius = params["player_radius"]
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


## Godot suma los rebotes de ambos cuerpos (y la fricción usa el mínimo). Cada jugador aporta la mitad
## de player_bounce; la pared aporta la diferencia hasta wall_bounce, restándola (absorbent) si es negativa.
func _apply_config(_key: String) -> void:
	linear_damp = params["damping"]
	physics_material_override.friction = params["friction"]
	physics_material_override.bounce = params["player_bounce"] * 0.5


static func configure_wall_material(wall: PhysicsMaterial, physics_params: Dictionary[String, float]) -> void:
	var contribution := physics_params["wall_bounce"] - physics_params["player_bounce"] * 0.5
	wall.absorbent = contribution < 0.0
	wall.bounce = absf(contribution)
	wall.friction = physics_params["friction"]


## Paso de reglas comunes; lo llama GameMode.physics_step antes del paso físico.
func step(time: float) -> void:
	clock = time
	if state == State.FALLING and time >= fall_until:
		state = State.ALIVE
		_hold = false
		teleport(respawn_at)
		invuln_until = time + params["invuln_time"]
		_set_layers(true)
	# Durante el dash: sin amortiguación y con un tope de velocidad que cae al final (1 − p²).
	var boosting := time < boost_until
	var progress := 1.0 - (boost_until - time) / params["dash_boost_time"] if boosting else 1.0
	linear_damp = 0.0 if boosting else params["damping"]
	_speed_cap = params["max_speed"] + params["dash_speed"] * (1.0 - progress * progress)
	if state == State.ALIVE:
		# Fuerza, nunca velocidad. Contra la velocidad actual empuja más (giros y frenadas más vivos).
		var force := tilt * params["tilt_accel"] * mass
		var speed := linear_velocity.length()
		if speed > 30.0 and tilt.length() > 0.01:
			var align := tilt.normalized().dot(linear_velocity / speed)
			force *= 1.0 + params["turn_boost"] * (1.0 - align) * 0.5
		apply_central_force(force)
	_update_view()


func dash(time: float) -> bool:
	if state != State.ALIVE or time < dash_ready_at:
		return false
	var direction := tilt if tilt.length() > 0.15 else linear_velocity
	if direction.length() < 0.001:
		return false
	direction = direction.normalized()
	# Anula la velocidad en contra antes del impulso: el dash también sirve para girar en seco.
	var against := minf(linear_velocity.dot(direction), 0.0)
	apply_central_impulse(direction * (params["dash_speed"] - against) * mass)
	dash_ready_at = time + params["dash_cooldown"]
	boost_until = time + params["dash_boost_time"]
	_dashed = true
	dashed.emit()
	return true


func start_fall(time: float, respawn: Vector2) -> void:
	if state == State.FALLING:
		return
	state = State.FALLING
	fall_until = time + params["fall_time"]
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


## Predicción: desplaza posición y velocidad hacia el estado del anfitrión (se aplica en _integrate_forces).
func correct(offset: Vector2, velocity_offset: Vector2) -> void:
	_correction += offset
	_velocity_correction += velocity_offset


## Predicción: congelar mientras el anfitrión dice que está cayendo.
func hold(on: bool) -> void:
	_hold = on


## Posición y velocidad tras aplicar las correcciones pendientes.
func predicted_position() -> Vector2:
	return position + _correction


func predicted_velocity() -> Vector2:
	return linear_velocity + _velocity_correction


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
	if _correction != Vector2.ZERO or _velocity_correction != Vector2.ZERO:
		body.transform = Transform2D(0.0, body.transform.origin + _correction)
		body.linear_velocity += _velocity_correction
		_correction = Vector2.ZERO
		_velocity_correction = Vector2.ZERO
	if _hold:
		body.linear_velocity = Vector2.ZERO
	if _speed_cap > 0.0 and body.linear_velocity.length() > _speed_cap:
		body.linear_velocity = body.linear_velocity.limit_length(_speed_cap)
	var change := (body.linear_velocity - _last_velocity).length()
	if not _dashed and body.get_contact_count() > 0 and change > params["hit_vibe_dv"]:
		hit.emit(change)
	_dashed = false
	_last_velocity = body.linear_velocity


func _update_view() -> void:
	view.falling = 0.0 if state != State.FALLING else clampf(1.0 - (fall_until - clock) / params["fall_time"], 0.0, 1.0)
	view.invulnerable = ghost or is_invulnerable()
	var cooldown := params["dash_cooldown"]
	view.dash_ready = clampf(1.0 - (dash_ready_at - clock) / cooldown, 0.0, 1.0)
	view.boost = clampf((boost_until - clock) / params["dash_boost_time"], 0.0, 1.0)
	if linear_velocity.length() > 20.0:
		view.heading = linear_velocity.normalized()
	elif tilt.length() > 0.1:
		view.heading = tilt.normalized()
