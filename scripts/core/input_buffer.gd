extends RefCounted
## Un comando por paso físico, aunque varios paquetes lleguen juntos o se pierdan.
## Las copias de comandos recientes recuperan pérdidas sin ejecutar dos veces un dash.

const START_BUFFER := 3
const REDUNDANCY := 16
const MAX_AHEAD := 256

var sequence := 0
var latest := 0
var first := 0
var started := false
var _pending: Dictionary[int, Vector3] = {}
var _held := Vector3.ZERO

func push(first_sequence: int, commands: PackedVector3Array) -> void:
	if first_sequence < 1 or commands.is_empty() or commands.size() > REDUNDANCY:
		return
	for i in commands.size():
		var seq := first_sequence + i
		var command := commands[i]
		if seq <= sequence or seq > sequence + MAX_AHEAD or not command.is_finite():
			continue
		_pending[seq] = command
		latest = maxi(latest, seq)
		first = seq if first == 0 else mini(first, seq)

func advance() -> Vector3:
	if not started:
		if first == 0 or latest - first < START_BUFFER:
			return Vector3.ZERO
		sequence = first - 1
		started = true
	sequence += 1
	# Si falta un comando, mantener la inclinación, pero nunca repetir la acción.
	var command: Vector3 = _pending.get(sequence, _held)
	_pending.erase(sequence)
	_held = Vector3(command.x, command.y, 0.0)
	return command
