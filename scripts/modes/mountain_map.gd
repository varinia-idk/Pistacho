extends RefCounted
const CENTER := Vector2(640, 378)
const HALF_WIDTH := 19.0
const SUMMIT_RADIUS := 28.0

static func generate() -> Dictionary:
	var spiral: Array[Vector2] = []
	for i in range(321):
		var t := float(i) / 320.0
		var angle := PI * 0.5 + TAU * 2.0 * t
		var radius := lerpf(228.0, 0.0, t)
		spiral.append(CENTER + Vector2(cos(angle), sin(angle)) * radius)
	var spawns: Array[Vector2] = [Vector2(226, 144), Vector2(1054, 144), Vector2(226, 612), Vector2(1054, 612)]
	# Outer lanes merge below the mountain before the single spiral entrance.
	var lanes: Array = []
	for i in range(4):
		var side := 180.0 if i % 2 == 0 else 1100.0
		lanes.append([spawns[i], Vector2(side, spawns[i].y), Vector2(side, 648), Vector2(640, 648), spiral[0]])
	return {"kind": "mountain", "spiral": spiral, "lanes": lanes, "spawns": spawns}

static func on_path(point: Vector2, map: Dictionary, margin: float = 0.0) -> bool:
	if point.distance_to(CENTER) < SUMMIT_RADIUS - margin:
		return true
	if near_line(point, map.spiral, HALF_WIDTH - margin):
		return true
	for lane: Array in map.lanes:
		if near_line(point, lane, HALF_WIDTH - margin):
			return true
	return false

static func near_line(point: Vector2, points: Array, width: float) -> bool:
	for i in range(points.size() - 1):
		if Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1]).distance_squared_to(point) <= width * width:
			return true
	return false
