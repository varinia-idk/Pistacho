extends SceneTree
## godot --headless --path . -s res://tests/test_maze.gd

const ConfigScript = preload("res://scripts/autoload/config.gd")
const MazeGen = preload("res://scripts/modes/maze/maze_generator.gd")
const SEEDS := 500


func _init() -> void:
	var cfg := ConfigScript.defaults()
	var size := MazeGen.grid_size(cfg)
	var failures := 0
	var retries := 0
	for seed_value in SEEDS:
		var data := MazeGen.generate(seed_value, size.x, size.y, cfg)
		var again := MazeGen.generate(seed_value, size.x, size.y, cfg)
		retries += data.seed_used - seed_value
		var problem := ""
		if not data.valid:
			problem = "no valida"
		elif data.walls != again.walls or data.holes != again.holes or data.seed_used != again.seed_used:
			problem = "no determinista"
		elif not _symmetric(data):
			problem = "paredes asimétricas"
		elif not _independent_check(data, cfg):
			problem = "falla la verificación independiente"
		elif data.holes.size() != int(cfg["maze_holes"]):
			problem = "agujeros: %d" % data.holes.size()
		if problem:
			failures += 1
			printerr("semilla %d: %s" % [seed_value, problem])
	print("test_maze: %d semillas, %dx%d, %d reintentos, %d fallos" % [SEEDS, size.x, size.y, retries, failures])
	quit(1 if failures else 0)


func _symmetric(data: MazeGen.Data) -> bool:
	for i in data.walls.size():
		var cell := data.cell_of(i)
		for dir in 4:
			var next := cell + MazeGen.DIRS[dir]
			var closed := not data.is_open(cell, dir)
			if not data.inside(next):
				if not closed:
					return false
			elif closed != (data.walls[data.index(next)] & MazeGen.OPPOSITE[dir] != 0):
				return false
	return true


## Repite la validación P1/P2/P3 con BFS por distancias, sin reutilizar shortest_path.
func _independent_check(data: MazeGen.Data, cfg: Dictionary[String, float]) -> bool:
	var dist := MazeGen.distances(data, data.start)
	var p1 := dist[data.index(data.goal)]
	if p1 < ceili((data.cols + data.rows - 2) * cfg["maze_min_path"]):
		return false
	if data.path.size() - 1 != p1:
		return false
	var blocked := PackedByteArray()
	blocked.resize(data.walls.size())
	blocked[data.index(data.path[data.path.size() >> 1])] = 1
	var p2 := MazeGen.shortest_path(data, data.start, data.goal, blocked)
	if p2.is_empty() or p2.size() - 1 > p1 * cfg["maze_alt_ratio"]:
		return false
	for cell in p2:
		if blocked[data.index(cell)] == 1:
			return false
	blocked[data.index(p2[p2.size() >> 1])] = 1
	return not MazeGen.shortest_path(data, data.start, data.goal, blocked).is_empty()
