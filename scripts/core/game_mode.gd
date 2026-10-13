extends Node2D
## Base de los modos. Cada modo es una escena cuyo script extiende este archivo
## y se registra en Game.MODE_SCENES; el núcleo no conoce sus reglas.

const Player = preload("res://scripts/players/player.gd")

var seed_value := 0
var time := 0.0
var players: Array[Player] = []


## Genera el mapa de forma determinista y construye lo visual (todos los peers).
func setup(_seed_value: int) -> void:
	seed_value = _seed_value


## Colisiones y estado de reglas (solo anfitrión).
func build_physics() -> void:
	pass


func title() -> String:
	return ""


func spawn_points() -> Array[Vector2]:
	return []


## Rectángulo del mapa en coordenadas del modo, para encuadrar la cámara.
func map_rect() -> Rect2:
	return Rect2()


func uses_bots() -> bool:
	return true


func add_player(player: Player) -> void:
	players.append(player)
	add_child(player)


## Reglas por paso físico (solo anfitrión). Los modos llaman a super primero.
func physics_step(delta: float) -> void:
	time += delta
	for player in players:
		player.step(time)
	for player in players:
		player.try_solidify(players)


## Ranura del ganador o -1.
func get_winner() -> int:
	return -1


## Ranuras ordenadas del primero al último (puntos 3/2/1/0).
func ranking() -> Array[int]:
	var result: Array[int] = []
	for player in players:
		result.append(player.slot)
	return result


## Velocidad deseada para un bot; el bot la convierte en inclinación.
func bot_desired_velocity(_player: Player) -> Vector2:
	return Vector2.ZERO


func bot_wants_dash(_player: Player) -> bool:
	return false
