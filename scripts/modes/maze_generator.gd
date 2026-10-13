extends RefCounted
const WIDTH := 25
const HEIGHT := 15
const CELL := 36.0
const ORIGIN := Vector2(190, 108)
const DIRECTIONS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static func index(cell: Vector2i) -> int:
	return cell.y * WIDTH + cell.x

static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i((point - ORIGIN) / CELL)

static func center(cell: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL

static func spawn_points() -> Array[Vector2]:
	return [center(Vector2i(1, 1)), center(Vector2i(23, 1)), center(Vector2i(1, 13)), center(Vector2i(23, 13))]

static func generate(seed_value: int, preserved: Array = [], clearance: float = 15.5) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cells: Array[int] = []
	cells.resize(WIDTH * HEIGHT)
	cells.fill(0)
	var stack: Array[Vector2i] = [Vector2i(1, 1)]
	cells[index(stack[0])] = 1
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var choices: Array[Vector2i] = []
		for step in DIRECTIONS:
			var next: Vector2i = current + step * 2
			if next.x > 0 and next.x < WIDTH - 1 and next.y > 0 and next.y < HEIGHT - 1 and cells[index(next)] == 0:
				choices.append(next)
		if choices.is_empty():
			stack.pop_back()
		else:
			var next: Vector2i = choices[rng.randi_range(0, choices.size() - 1)]
			cells[index(current + (next - current).sign())] = 1
			cells[index(next)] = 1
			stack.append(next)
	var goal := Vector2i(12, 7)
	cells[index(goal)] = 1
	cells[index(Vector2i(11, 7))] = 1
	# Clear every cell intersecting the player's disk, then join it to the goal.
	for point: Vector2 in preserved:
		var cell := cell_at(point)
		var lo := cell_at(point - Vector2.ONE * clearance)
		var hi := cell_at(point + Vector2.ONE * clearance)
		for y in range(maxi(1, lo.y), mini(HEIGHT - 2, hi.y) + 1):
			for x in range(maxi(1, lo.x), mini(WIDTH - 2, hi.x) + 1):
				cells[index(Vector2i(x, y))] = 1
		while cell != goal:
			cells[index(cell)] = 1
			if cell.x != goal.x:
				cell.x += signi(goal.x - cell.x)
			else:
				cell.y += signi(goal.y - cell.y)
	return {"kind": "maze", "cells": cells, "seed": seed_value}

static func route(cells: Array, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var previous := {start: start}
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		if here == goal:
			var result: Array[Vector2i] = [goal]
			while result.back() != start:
				result.append(previous[result.back()])
			result.reverse()
			return result
		for direction in DIRECTIONS:
			var next: Vector2i = here + direction
			if next.x < 0 or next.y < 0 or next.x >= WIDTH or next.y >= HEIGHT:
				continue
			if cells[index(next)] == 1 and not previous.has(next):
				previous[next] = here
				queue.append(next)
	return []
