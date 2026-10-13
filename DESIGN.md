# Pistacho — diseño (fase 1)

## Supuestos
- Ejes: Godot reorienta los sensores a la pantalla (x derecha, y arriba), por eso `invert_y = 1` por defecto. Confirmar en el teléfono con el overlay.
- Curva radial: dirección × pow(t, 1.6), no por eje, para no deformar las diagonales.
- Dash: durante el giro brusco la inclinación se congela en la de hace `dash_lookback` s; el gesto no desvía el impulso.
- `maze_min_path` es relativo a la distancia Manhattan (P1 ≥ 1.3×), así sigue siendo alcanzable si cambia el radio.
- Geometría del mapa = f(Config) sobre la base 1920×1080 menos HUD; nunca depende de la pantalla del dispositivo.
- Ranking de ronda: llegada a la meta; el resto por distancia BFS restante (3/2/1/0).
- Única asignación de posición: al crear el cuerpo, antes de entrar al árbol. Después solo `teleport()` en `_integrate_forces`.
- Tras caer: fantasma (sin choques entre jugadores) mientras dura la invulnerabilidad.
- Bots: constantes internas (horizonte 0.25 s, ruido, reacción) escaladas por `bot_skill`.
- Tests: generadores puros sin autoloads (con `-s` los autoloads no existen al compilar; si un script falla, Godot no sale).
- `addons/godot_mcp` queda como herramienta de editor; `dev_bridge.gd` lo excluye del APK.

## Dudas
- Con bots, una ronda de laberinto dura ~20 s (objetivo 60–120 s). ¿Mapa mayor con cámara que sigue al jugador, o rutas más largas?
- Inclinación = XY de (g − g0): con el teléfono muy inclinado hacia ti, el eje Y pierde sensibilidad (factor cos del ángulo).
- Fase 2: los valores de Config del anfitrión deben viajar con el inicio de ronda o los mapas diferirán entre peers.
- Espiral con personajes de 40 px: ~1200 px de diámetro, no cabe en 1080 → cámara que sigue (fase 4).

## Android
- Permisos a marcar en el preset: `INTERNET` y `VIBRATE` (hoy el preset solo tiene INTERNET).

## Tests
- `godot --headless --path . -s res://tests/test_maze.gd` (500 semillas) y `test_spiral.gd` (200 semillas).
