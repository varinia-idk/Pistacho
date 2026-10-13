extends RefCounted
## Datos puros del laberinto. Misma semilla + mismos parámetros = mismo laberinto en todos los peers.
## Celda = bitmask de paredes (1 = pared presente).

const N := 1
const E := 2
const S := 4
const W := 8
const ALL := 15
const BITS: Array[int] = [N, E, S, W]
const OPPOSITE: Array[int] = [S, W, N, E]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const MAX_ATTEMPTS := 64
const AREA := Vector2(1608.0, 968.0)  ## Zona jugable en la resolución base 1920×1080, sin el HUD.


class Data:
	var cols := 0
	var rows := 0
	var seed_used := 0
	var valid := false
	var walls := PackedByteArray()
	## Índice de celda -> lado del agujero (+1/-1) respecto al eje del pasillo.
	var holes: Dictionary[int, int] = {}
	var start := Vector2i.ZERO
	var goal := Vector2i.ZERO
	var path: Array[Vector2i] = []

	func index(cell: Vector2i) -> int:
		return cell.y * cols + cell.x

	func cell_of(i: int) -> Vector2i:
		@warning_ignore("integer_division")
		return Vector2i(i % cols, i / cols)

	func inside(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows

	func is_open(cell: Vector2i, dir: int) -> bool:
		return walls[index(cell)] & BITS[dir] == 0

	## Pasillo recto: exactamente dos aberturas opuestas. Devuelve 0 (vertical), 1 (horizontal) o -1.
	func straight_axis(cell: Vector2i) -> int:
		var mask := walls[index(cell)]
		if mask == E | W:
			return 0
		if mask == N | S:
			return 1
		return -1


static func wall_thickness(cfg: Dictionary[String, float]) -> float:
	return maxf(0.3, cfg["maze_wall"]) * cfg["player_radius"]


## El pasillo libre (celda menos pared) mide al menos maze_corridor diámetros.
static func cell_size(cfg: Dictionary[String, float]) -> float:
	return ceilf(cfg["maze_corridor"] * 2.0 * cfg["player_radius"] + wall_thickness(cfg))


## Depende solo de la configuración, nunca de la pantalla: igual en todos los peers.
static func grid_size(cfg: Dictionary[String, float]) -> Vector2i:
	var size := cell_size(cfg)
	return Vector2i(maxi(6, floori(AREA.x / size)), maxi(5, floori(AREA.y / size)))


## cfg: valores de Config (o Config.defaults() en tests).
static func generate(seed_value: int, cols: int, rows: int, cfg: Dictionary[String, float]) -> Data:
	var data: Data
	for attempt in MAX_ATTEMPTS:
		data = _carve(seed_value + attempt, cols, rows, cfg)
		if validate(data, cfg):
			_place_holes(data, cfg)
			return data
	push_warning("Laberinto sin validar tras %d intentos (semilla %d)" % [MAX_ATTEMPTS, seed_value])
	return data


static func _carve(seed_value: int, cols: int, rows: int, cfg: Dictionary[String, float]) -> Data:
	var data := Data.new()
	data.cols = cols
	data.rows = rows
	data.seed_used = seed_value
	data.start = Vector2i(0, 0)
	data.goal = Vector2i(cols - 1, rows - 1)
	data.walls.resize(cols * rows)
	data.walls.fill(ALL)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var visited := PackedByteArray()
	visited.resize(cols * rows)
	var came := PackedInt32Array()
	came.resize(cols * rows)
	came.fill(-1)
	# Growing tree: mezcla de "más nuevo" (pasillos largos) y "aleatorio" (más ramas).
	var active: Array[Vector2i] = [data.start]
	visited[data.index(data.start)] = 1
	var options: Array[int] = []
	while not active.is_empty():
		var pick := active.size() - 1 if rng.randf() < cfg["maze_newest"] else rng.randi_range(0, active.size() - 1)
		var cell := active[pick]
		options.clear()
		for dir in 4:
			var neighbor := cell + DIRS[dir]
			if data.inside(neighbor) and visited[data.index(neighbor)] == 0:
				options.append(dir)
		if options.is_empty():
			active.remove_at(pick)
			continue
		var dir: int = options[rng.randi_range(0, options.size() - 1)]
		var previous := came[data.index(cell)]
		if options.has(previous) and rng.randf() < cfg["maze_straight"]:
			dir = previous
		var next := cell + DIRS[dir]
		_open(data, cell, dir)
		visited[data.index(next)] = 1
		came[data.index(next)] = dir
		active.append(next)
	_open_room(data, data.start)
	_open_room(data, data.goal - Vector2i.ONE)
	_braid(data, rng, cfg["maze_braid"])
	return data


static func _open(data: Data, cell: Vector2i, dir: int) -> void:
	var next := cell + DIRS[dir]
	data.walls[data.index(cell)] &= ~BITS[dir]
	data.walls[data.index(next)] &= ~OPPOSITE[dir]


## Sala de 2×2 sin paredes internas (salida y meta).
static func _open_room(data: Data, corner: Vector2i) -> void:
	_open(data, corner, 1)
	_open(data, corner, 2)
	_open(data, corner + Vector2i(1, 1), 0)
	_open(data, corner + Vector2i(1, 1), 3)


## Elimina una fracción de callejones sin salida abriendo una pared, preferentemente hacia otro callejón.
static func _braid(data: Data, rng: RandomNumberGenerator, ratio: float) -> void:
	for i in data.walls.size():
		if _wall_count(data.walls[i]) != 3 or rng.randf() >= ratio:
			continue
		var cell := data.cell_of(i)
		var candidates: Array[int] = []
		var dead_ends: Array[int] = []
		for dir in 4:
			var next := cell + DIRS[dir]
			if data.inside(next) and not data.is_open(cell, dir):
				candidates.append(dir)
				if _wall_count(data.walls[data.index(next)]) == 3:
					dead_ends.append(dir)
		var pool := dead_ends if not dead_ends.is_empty() else candidates
		if not pool.is_empty():
			_open(data, cell, pool[rng.randi_range(0, pool.size() - 1)])


static func _wall_count(mask: int) -> int:
	return (mask & 1) + (mask >> 1 & 1) + (mask >> 2 & 1) + (mask >> 3 & 1)


## P1 ≥ mínimo; bloqueando su celda central existe P2 ≤ alt_ratio·P1; bloqueando también la central de P2 existe P3.
static func validate(data: Data, cfg: Dictionary[String, float]) -> bool:
	var blocked := PackedByteArray()
	blocked.resize(data.walls.size())
	var p1 := shortest_path(data, data.start, data.goal, blocked)
	var manhattan := data.cols + data.rows - 2
	if p1.is_empty() or p1.size() - 1 < ceili(manhattan * cfg["maze_min_path"]):
		return false
	blocked[data.index(p1[p1.size() >> 1])] = 1
	var p2 := shortest_path(data, data.start, data.goal, blocked)
	if p2.is_empty() or p2.size() - 1 > (p1.size() - 1) * cfg["maze_alt_ratio"]:
		return false
	blocked[data.index(p2[p2.size() >> 1])] = 1
	if shortest_path(data, data.start, data.goal, blocked).is_empty():
		return false
	data.path = p1
	data.valid = true
	return true


static func shortest_path(data: Data, from: Vector2i, to: Vector2i, blocked: PackedByteArray) -> Array[Vector2i]:
	var previous := PackedInt32Array()
	previous.resize(data.walls.size())
	previous.fill(-1)
	var origin := data.index(from)
	var target := data.index(to)
	previous[origin] = origin
	var queue := PackedInt32Array([origin])
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		if current == target:
			break
		var cell := data.cell_of(current)
		for dir in 4:
			if not data.is_open(cell, dir):
				continue
			var next := data.index(cell + DIRS[dir])
			if previous[next] == -1 and blocked[next] == 0:
				previous[next] = current
				queue.append(next)
	var result: Array[Vector2i] = []
	if previous[target] == -1:
		return result
	var cursor := target
	while cursor != origin:
		result.append(data.cell_of(cursor))
		cursor = previous[cursor]
	result.append(from)
	result.reverse()
	return result


## Distancia en pasos desde una celda a todas las demás (-1 = inalcanzable).
static func distances(data: Data, from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(data.walls.size())
	dist.fill(-1)
	dist[data.index(from)] = 0
	var queue := PackedInt32Array([data.index(from)])
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		var cell := data.cell_of(current)
		for dir in 4:
			if data.is_open(cell, dir):
				var next := data.index(cell + DIRS[dir])
				if dist[next] == -1:
					dist[next] = dist[current] + 1
					queue.append(next)
	return dist


## Agujeros en rectas (con paso angosto al lado), primero sobre la ruta principal, separados entre sí.
static func _place_holes(data: Data, cfg: Dictionary[String, float]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed_used * 7919 + 13
	var on_path: Array[int] = []
	var others: Array[int] = []
	var path_set: Dictionary[int, bool] = {}
	for cell in data.path:
		path_set[data.index(cell)] = true
	for i in data.walls.size():
		var cell := data.cell_of(i)
		if data.straight_axis(cell) == -1 or _near_room(data, cell):
			continue
		if path_set.has(i):
			on_path.append(i)
		else:
			others.append(i)
	_shuffle(on_path, rng)
	_shuffle(others, rng)
	var wanted := roundi(cfg["maze_holes"])
	for i in on_path + others:
		if data.holes.size() >= wanted:
			break
		var cell := data.cell_of(i)
		var spaced := true
		for other: int in data.holes:
			var delta := data.cell_of(other) - cell
			if absi(delta.x) + absi(delta.y) < 4:
				spaced = false
				break
		if spaced:
			data.holes[i] = 1 if rng.randf() < 0.5 else -1


static func _near_room(data: Data, cell: Vector2i) -> bool:
	return (cell.x <= 2 and cell.y <= 2) or (cell.x >= data.cols - 3 and cell.y >= data.rows - 3)


static func _shuffle(items: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := items[i]
		items[i] = items[j]
		items[j] = swap
