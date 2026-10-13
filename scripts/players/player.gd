extends CharacterBody2D
var slot: int = 0
var peer_id: int = 1
var mass: float = 1.0
var radius: float = 10.0
var item: String = ""
var inverted_until: float = 0.0
var grown_until: float = 0.0
var protected_until: float = 0.0
var input_direction := Vector2.ZERO
var input_age: float = 0.0
var impulse := Vector2.ZERO
var spawn := Vector2.ZERO
var collider: CollisionShape2D
var respawn_serial: int = 0

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 0
	collision_mask = 1
	collider = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collider.shape = shape
	add_child(collider)

func set_radius(value: float) -> void:
	radius = value
	if collider:
		collider.shape.radius = radius

func step(delta: float, time: float, rules: Resource) -> void:
	input_age += delta
	var direction := input_direction if input_age <= 0.25 else Vector2.ZERO
	if time < inverted_until:
		direction = -direction
	var target: Vector2 = direction * rules.player_speed
	velocity = velocity.move_toward(target, (rules.friction if direction == Vector2.ZERO else rules.acceleration) * delta)
	velocity += impulse
	impulse = Vector2.ZERO
	move_and_slide()

func respawn(time: float, rules: Resource) -> void:
	respawn_serial += 1
	position = spawn
	velocity = Vector2.ZERO
	impulse = Vector2.ZERO
	item = ""
	inverted_until = 0.0
	grown_until = 0.0
	protected_until = time + rules.respawn_protection
	mass = 1.0
	set_radius(rules.player_radius)

func state() -> Dictionary:
	return {"id": peer_id, "slot": slot, "position": position, "velocity": velocity, "radius": radius, "item": item, "inverted_until": inverted_until, "grown_until": grown_until, "protected_until": protected_until, "respawn_serial": respawn_serial}
