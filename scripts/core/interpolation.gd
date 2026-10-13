extends RefCounted
## Interpolación por instantáneas para los clientes (sin autoloads, se prueba en headless).
## Se dibuja ligeramente en el pasado, entre dos estados conocidos del anfitrión. Perseguir el último
## estado recibido convierte cada irregularidad de llegada de la Wi-Fi en un tirón visible.

const OFFSET_RELAX := 0.0005   ## Deriva lenta del desfase hacia muestras más tardías (por paquete).
const JITTER_DECAY := 0.99     ## Olvido del jitter máximo reciente (por paquete; ~1 s a 60 Hz).
const LEAD_RATE := 0.1         ## El reloj de dibujo se corrige ≤ 0.1 s por s: nunca salta, solo cambia de ritmo ≤ 10 %.
const MAX_EXTRAPOLATION := 0.1 ## Si faltan datos, prolongar con la velocidad como mucho esto.
const KEEP := 1.0              ## Segundos de historial por pista.


## Relación entre el reloj de simulación del anfitrión y el reloj local, y retardo de dibujo adaptativo.
class Clock:
	var offset := 0.0          ## reloj del anfitrión − reloj local, en el paquete más rápido visto.
	var jitter := 0.0          ## Retraso extra reciente respecto a ese mejor caso.
	var delay := 0.0           ## Retardo objetivo: un intervalo y medio + jitter reciente.
	var lead := 0.0            ## offset − delay aplicado de verdad (corregido con ritmo limitado).
	var synced := false

	func reset() -> void:
		synced = false
		jitter = 0.0

	func observe(server_time: float, local_time: float, interval: float, min_delay: float, max_delay: float) -> void:
		var sample := server_time - local_time
		if not synced:
			offset = sample
		elif sample > offset:
			offset = sample
		else:
			offset = lerpf(offset, sample, OFFSET_RELAX)
		jitter = maxf(offset - sample, jitter * JITTER_DECAY)
		delay = clampf(interval * 1.5 + jitter, min_delay, max_delay)
		if not synced:
			lead = offset - delay
			synced = true

	func render_time(local_time: float, delta: float) -> float:
		lead = move_toward(lead, offset - delay, LEAD_RATE * delta)
		return local_time + lead


## Historial de un valor vectorial (campos de un jugador, o el tiempo del modo).
class Track:
	var times := PackedFloat64Array()
	var frames: Array[PackedFloat32Array] = []
	## Si los dos primeros campos son una posición y saltan más que esto, no se interpola (teletransporte).
	var snap_distance := INF

	func push(time: float, fields: PackedFloat32Array) -> void:
		if not times.is_empty() and time <= times[times.size() - 1]:
			return
		times.append(time)
		frames.append(fields)
		while times.size() > 2 and times[0] < time - KEEP:
			times.remove_at(0)
			frames.pop_front()

	func is_empty() -> bool:
		return times.is_empty()

	## Campos en el instante t. Campos 4 y 5 (si existen) son la velocidad usada para extrapolar.
	func sample(time: float) -> PackedFloat32Array:
		var last := times.size() - 1
		if time <= times[0]:
			return frames[0]
		if time >= times[last]:
			var ahead := minf(time - times[last], MAX_EXTRAPOLATION)
			var projected := frames[last].duplicate()
			if projected.size() > 5:
				projected[0] += projected[4] * ahead
				projected[1] += projected[5] * ahead
			return projected
		var i := last - 1
		while times[i] > time:
			i -= 1
		var a := frames[i]
		var b := frames[i + 1]
		var t := (time - times[i]) / (times[i + 1] - times[i])
		if a.size() > 1 and Vector2(a[0], a[1]).distance_to(Vector2(b[0], b[1])) > snap_distance:
			return b if t >= 0.5 else a
		var result := PackedFloat32Array()
		result.resize(a.size())
		for k in a.size():
			result[k] = lerpf(a[k], b[k], t)
		return result
