extends SceneTree

const Buffer = preload("res://scripts/core/input_buffer.gd")
var failures := 0

func _init() -> void:
	var buffer := Buffer.new()
	var commands := PackedVector3Array([
		Vector3(1, 0, 0), Vector3(0, 1, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0)])
	buffer.push(1, commands.slice(0, 2))
	check(buffer.advance() == Vector3.ZERO and buffer.sequence == 0, "esperar margen inicial")
	# Otro paquete trae copias redundantes de los comandos cuyo primer envío se perdió.
	buffer.push(1, commands)
	for i in commands.size():
		check(buffer.advance() == commands[i] and buffer.sequence == i + 1, "un comando por tick %d" % i)
		buffer.push(1, commands)  # Retransmitir no debe repetir ni la inclinación ni el dash.
	check(buffer.advance() == Vector3(0, -1, 0) and buffer.sequence == 5, "pérdida: mantener inclinación sin acción")
	buffer.push(5, PackedVector3Array([Vector3(1, 1, 1)]))
	check(buffer.advance() == Vector3(0, -1, 0), "descartar comando tardío ya simulado")
	buffer.push(7, PackedVector3Array([Vector3(0.5, 0, 0)]))
	check(buffer.advance() == Vector3(0.5, 0, 0), "recuperar tras pérdida")
	buffer.push(10000, commands)
	check(buffer.latest == 7, "limitar horizonte de cola")
	print("test_input_buffer: %d fallos" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)
