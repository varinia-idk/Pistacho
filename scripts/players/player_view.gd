extends Node2D
## Representación de un jugador. En el anfitrión es hija del cuerpo físico;
## en los clientes es independiente y Game la coloca con la interpolación por instantáneas.

## Campos por jugador en el paquete de estado, tras la ranura (ver Game._pack_state).
const STATE_FIELDS := 10
const FLAG_SHIELD := 1

var color := Color.WHITE
var radius := 20.0
var is_local := false
var falling := 0.0          ## 0..1 progreso de la caída
var invulnerable := false
var dash_ready := 1.0       ## 0..1 recarga del dash
var boost := 0.0            ## 1 al iniciar el dash, 0 al terminar
var heading := Vector2.RIGHT


## Cliente: se coloca en _process, fuera de la interpolación física.
func make_remote(start: Vector2) -> void:
	position = start
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## fields: x, y, radio, flags, vx, vy, caída, recarga dash, impulso dash, último input aplicado.
func apply_fields(fields: PackedFloat32Array) -> void:
	position = Vector2(fields[0], fields[1])
	radius = fields[2]
	invulnerable = int(fields[3]) & FLAG_SHIELD != 0
	var velocity := Vector2(fields[4], fields[5])
	if velocity.length() > 20.0:
		heading = velocity.normalized()
	falling = fields[6]
	dash_ready = fields[7]
	boost = fields[8]


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var size := radius * (1.0 - ease(falling, 2.0))
	if size < 0.5:
		return
	var body := color.darkened(falling * 0.6)
	if invulnerable:
		body.a = 0.5
	if boost > 0.0:
		# Estela detrás y onda expansiva al arrancar el dash.
		for k in range(4, 0, -1):
			draw_circle(-heading * size * 0.6 * k, size * (1.0 - 0.14 * k), Color(color, 0.5 * boost * (1.0 - k / 5.0)), true, -1.0, true)
		draw_arc(Vector2.ZERO, size + 8.0 + 40.0 * (1.0 - boost), 0.0, TAU, 48, Color(1, 1, 1, boost * boost), 4.0, true)
	draw_circle(Vector2(0.0, size * 0.22), size, Color(0, 0, 0, 0.35 * body.a), true, -1.0, true)
	draw_circle(Vector2.ZERO, size, body, true, -1.0, true)
	draw_circle(Vector2(-0.3, -0.35) * size, size * 0.28, Color(1, 1, 1, 0.35 * body.a), true, -1.0, true)
	# Ojos hacia la dirección de movimiento.
	var side := heading.orthogonal() * size * 0.32
	var front := heading * size * 0.38
	for eye in [front + side, front - side]:
		draw_circle(eye, size * 0.2, Color(1, 1, 1, body.a), true, -1.0, true)
		draw_circle(eye + heading * size * 0.07, size * 0.1, Color(0.05, 0.05, 0.08, body.a), true, -1.0, true)
	if is_local:
		draw_arc(Vector2.ZERO, size + 5.0, 0.0, TAU, 48, Color.WHITE, 3.0, true)
		if dash_ready < 1.0:
			draw_arc(Vector2.ZERO, size + 11.0, -PI / 2.0, -PI / 2.0 + TAU * dash_ready, 48, Color(1, 1, 1, 0.8), 4.0, true)
	if invulnerable:
		# Ícono de escudo: anillo discontinuo.
		for i in 8:
			var a := TAU * i / 8.0 + Time.get_ticks_msec() * 0.003
			draw_arc(Vector2.ZERO, size + 16.0, a, a + TAU / 16.0, 6, Color(0.7, 0.95, 1.0, 0.9), 3.0, true)
