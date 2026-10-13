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
	var alpha := 0.5 if invulnerable else 1.0
	if boost > 0.0:
		# Estela detrás y onda expansiva al arrancar el dash.
		for k in range(4, 0, -1):
			draw_circle(-heading * size * 0.6 * k, size * (1.0 - 0.14 * k), Color(color, 0.5 * boost * (1.0 - k / 5.0)), true, -1.0, true)
		draw_arc(Vector2.ZERO, size + 8.0 + 40.0 * (1.0 - boost), 0.0, TAU, 48, Color(1, 1, 1, boost * boost), 4.0, true)
	draw_ball(self, Vector2.ZERO, size, body, heading, alpha)
	if is_local:
		# Marcador "tú": anillo menta, flecha que flota encima y recarga del dash alrededor.
		var mint := Color("67e4bc")
		draw_arc(Vector2.ZERO, size + 6.0, 0.0, TAU, 48, mint, 3.0, true)
		var bob := sin(Time.get_ticks_msec() * 0.006) * 3.0
		var tip := Vector2(0.0, -size - 14.0 + bob)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9.0, -12.0), tip + Vector2(9.0, -12.0)]), mint)
		if dash_ready < 1.0:
			draw_arc(Vector2.ZERO, size + 12.0, -PI / 2.0, -PI / 2.0 + TAU * dash_ready, 48, Color(mint, 0.8), 4.0, true)
	if invulnerable:
		# Escudo: anillo discontinuo que gira.
		for i in 8:
			var a := TAU * i / 8.0 + Time.get_ticks_msec() * 0.003
			draw_arc(Vector2.ZERO, size + 18.0, a, a + TAU / 16.0, 6, Color(0.7, 0.95, 1.0, 0.9), 3.0, true)


## Bola con sombra, contorno, brillo y ojos; la usan el juego y la interfaz.
static func draw_ball(canvas: CanvasItem, center: Vector2, size: float, body: Color, look: Vector2, alpha := 1.0) -> void:
	canvas.draw_circle(center + Vector2(0.0, size * 0.25), size, Color(0, 0, 0, 0.35 * alpha), true, -1.0, true)
	canvas.draw_circle(center, size, Color(body.darkened(0.35), alpha), true, -1.0, true)
	canvas.draw_circle(center, size * 0.9, Color(body, alpha), true, -1.0, true)
	canvas.draw_circle(center + Vector2(-0.3, -0.35) * size, size * 0.3, Color(1, 1, 1, 0.38 * alpha), true, -1.0, true)
	var side := look.orthogonal() * size * 0.32
	var front := look * size * 0.36
	for eye: Vector2 in [front + side, front - side]:
		canvas.draw_circle(center + eye, size * 0.21, Color(1, 1, 1, alpha), true, -1.0, true)
		canvas.draw_circle(center + eye + look * size * 0.07, size * 0.11, Color(0.04, 0.09, 0.11, alpha), true, -1.0, true)
