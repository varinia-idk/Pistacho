extends RefCounted
## Render a continuous timeline between authoritative network samples.
## Three snapshot intervals cover LAN jitter and one dropped packet without wall prediction.
const BUFFER_SECONDS := 0.15
const MAX_SAMPLES := 16
var samples: Array[Dictionary] = []
var cursor := 0.0

func push(point: Vector2, stamp: float, teleport: bool = false) -> void:
	if not point.is_finite() or not is_finite(stamp):
		return
	if samples.is_empty() or teleport:
		samples = [{"point": point, "time": stamp}]
		cursor = stamp - BUFFER_SECONDS
		return
	var last: Dictionary = samples.back()
	if stamp < float(last.time):
		return
	if absf(stamp - float(last.time)) < 0.000001:
		samples[-1].point = point
		return
	# Refill after a long stall without spending seconds catching up.
	if stamp - float(last.time) > 0.25:
		cursor = stamp - BUFFER_SECONDS
	samples.append({"point": point, "time": stamp})
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()

func advance(delta: float) -> Vector2:
	if samples.is_empty():
		return Vector2.ZERO
	var newest: float = samples.back().time
	cursor = minf(cursor + maxf(delta, 0.0), newest)
	while samples.size() > 2 and float(samples[1].time) <= cursor:
		samples.pop_front()
	if samples.size() == 1:
		return samples[0].point
	var a: Dictionary = samples[0]
	var b: Dictionary = samples[1]
	var weight := clampf((cursor - float(a.time)) / (float(b.time) - float(a.time)), 0.0, 1.0)
	return (a.point as Vector2).lerp(b.point, weight)
