extends Node
## Short original synth effects, generated in memory; no imported audio needed.
var effects: Dictionary = {}
var muted: bool = false

func _ready() -> void:
	for kind: String in ["pickup", "item", "blast", "respawn", "win"]:
		var frequency: float = {"pickup": 880.0, "item": 560.0, "blast": 90.0, "respawn": 220.0, "win": 660.0}[kind]
		var duration := 0.5 if kind == "win" else 0.16
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		var bytes := PackedByteArray()
		bytes.resize(int(duration * 22050) * 2)
		for i in range(int(duration * 22050)):
			var t := float(i) / 22050.0
			var sample := sin(TAU * frequency * t * (1.0 + t * (2.0 if kind == "win" else -0.6))) * exp(-t * 14.0) * 0.24
			bytes.encode_s16(i * 2, int(sample * 32767))
		stream.data = bytes
		effects[kind] = stream

func play(kind: String) -> void:
	if muted or not effects.has(kind):
		return
	var player := AudioStreamPlayer.new()
	player.stream = effects[kind]
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
