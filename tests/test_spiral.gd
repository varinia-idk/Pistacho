extends SceneTree
## godot --headless --path . -s res://tests/test_spiral.gd

const ConfigScript = preload("res://scripts/autoload/config.gd")
const SpiralGen = preload("res://scripts/modes/mountain/spiral_generator.gd")
const SEEDS := 200


func _init() -> void:
	var cfg := ConfigScript.defaults()
	var failures := 0
	var retries := 0
	for seed_value in SEEDS:
		var data := SpiralGen.generate(seed_value, cfg)
		var again := SpiralGen.generate(seed_value, cfg)
		retries += data.seed_used - seed_value
		var problem := ""
		if not data.valid:
			problem = "no valida"
		elif data.points != again.points or data.widths != again.widths:
			problem = "no determinista"
		elif data.points.size() != int(cfg["spiral_points"]):
			problem = "puntos: %d" % data.points.size()
		else:
			problem = _overlap(data)
		if problem:
			failures += 1
			printerr("semilla %d: %s" % [seed_value, problem])
	print("test_spiral: %d semillas, %d reintentos, %d fallos" % [SEEDS, retries, failures])
	quit(1 if failures else 0)


## Verificación independiente: ninguna vuelta toca a la interior en ningún ángulo (por distancia mínima a la polilínea).
func _overlap(data: SpiralGen.Data) -> String:
	var n := data.per_turn
	for i in data.points.size() - n:
		var best := INF
		for j in range(i + n - 2, mini(i + n + 3, data.points.size())):
			best = minf(best, data.points[i].distance_to(data.points[j]))
		if best < (data.widths[i] + data.widths[i + n]) * 0.5 - 0.001:
			return "vueltas solapadas en el punto %d" % i
	return ""
