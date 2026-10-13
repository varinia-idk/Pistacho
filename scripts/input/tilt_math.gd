extends RefCounted
## Matemática pura de la inclinación (sin autoloads, para probarla en headless).


## Ejes del plano tangente a g0, alineados con la pantalla (x derecha, y arriba en coordenadas del sensor).
## Proyectar sobre ellos da |v| = sin(ángulo respecto a g0) sin importar cómo se sostenga el teléfono;
## las componentes XY crudas de (g − g0) se reducen por cos(inclinación de sujeción).
static func basis(g0: Vector3) -> Array[Vector3]:
	var right := Vector3.RIGHT - g0 * g0.dot(Vector3.RIGHT)
	if right.length() < 0.1:
		return [Vector3.RIGHT, Vector3.UP]
	right = right.normalized()
	return [right, right.cross(g0).normalized()]


static func project(gravity_unit: Vector3, axes: Array[Vector3]) -> Vector2:
	return Vector2(gravity_unit.dot(axes[0]), gravity_unit.dot(axes[1]))


## Zona muerta y saturación como sin(ángulo); curva radial pow(t, exponente).
static func shape(v: Vector2, dead: float, full: float, exponent: float) -> Vector2:
	var magnitude := v.length()
	if magnitude <= dead or full <= dead:
		return Vector2.ZERO
	var t := clampf((magnitude - dead) / (full - dead), 0.0, 1.0)
	return v / magnitude * pow(t, exponent)
