extends RefCounted
## Espiral del Rey de la montaña como polilínea: r(θ) = r_ext − k·θ + ruido(θ).
## Índice 0 = base (afuera); el índice crece hacia la cima. El punto i + per_turn está una vuelta más adentro.

const MAX_ATTEMPTS := 64
const NOISE_FREQUENCY := 0.35


class Data:
	var seed_used := 0
	var valid := false
	var per_turn := 0
	var summit_radius := 0.0
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()  ## Ancho total del camino en cada punto.


static func generate(seed_value: int, cfg: Dictionary[String, float]) -> Data:
	var data: Data
	for attempt in MAX_ATTEMPTS:
		data = _build(seed_value + attempt, cfg)
		if validate(data):
			data.valid = true
			return data
	push_warning("Espiral sin validar tras %d intentos (semilla %d)" % [MAX_ATTEMPTS, seed_value])
	return data


static func _build(seed_value: int, cfg: Dictionary[String, float]) -> Data:
	var data := Data.new()
	data.seed_used = seed_value
	var diameter := 2.0 * cfg["player_radius"]
	var count := roundi(cfg["spiral_points"])
	var w_min := cfg["spiral_width_min"] * diameter
	var w_max := maxf(cfg["spiral_width_max"], cfg["spiral_width_min"]) * diameter
	var amplitude := cfg["spiral_noise"] * diameter
	# Separación nominal entre vueltas: ancho máximo + margen para el ruido.
	var pitch := w_max + 1.5 * amplitude
	data.per_turn = maxi(8, roundi(count / cfg["spiral_turns"]))
	data.summit_radius = 1.5 * diameter
	var turns := float(count - 1) / data.per_turn
	var r_ext := data.summit_radius + w_max * 0.5 + turns * pitch
	var radius_noise := FastNoiseLite.new()
	radius_noise.seed = seed_value
	radius_noise.frequency = NOISE_FREQUENCY
	var width_noise := FastNoiseLite.new()
	width_noise.seed = seed_value + 1
	width_noise.frequency = NOISE_FREQUENCY
	for i in count:
		var theta := TAU * i / data.per_turn
		var r := r_ext - pitch / TAU * theta + amplitude * radius_noise.get_noise_1d(theta)
		data.points.append(Vector2.from_angle(theta) * r)
		data.widths.append(lerpf(w_min, w_max, 0.5 + 0.5 * width_noise.get_noise_1d(theta)))
	return data


## Cada punto y el de la vuelta interior deben separarse al menos la suma de sus semianchos.
static func validate(data: Data) -> bool:
	for i in data.points.size() - data.per_turn:
		var j := i + data.per_turn
		if data.points[i].distance_to(data.points[j]) < (data.widths[i] + data.widths[j]) * 0.5:
			return false
	var last := data.points.size() - 1
	return data.points[last].length() >= data.summit_radius
