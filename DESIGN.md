# Pistacho — diseño (fases 1–2)

## Supuestos
- Ejes: Godot reorienta los sensores a la pantalla (x derecha, y arriba) → `invert_y = 1` por defecto.
- Inclinación = (g − g0) proyectada en el plano tangente a g0; las XY crudas pierden sensibilidad por cos(sujeción). Curva radial 1.5° / 15° / 1.25 (la spec pedía 2° / 25° / 1.6: tosco en móvil).
- Rebote: Godot suma el de ambos cuerpos; `wall_bounce` (0.3) y `player_bounce` (0.6) son el resultado real (la pared resta con absorbent).
- Dash: anula la velocidad en contra, 550 px/s, sin amortiguación 0.45 s; el gesto congela la inclinación previa.
- `maze_min_path` relativo a la distancia Manhattan. Geometría = f(cfg de la ronda), nunca de la pantalla.
- Única asignación de posición: al crear el cuerpo, antes de entrar al árbol; después solo `teleport()`.
- Bots: si llevan `bot_patience` s bloqueados, retroceden un tiempo aleatorio; ante humanos siempre, entre bots el que va detrás.
- `user://config.json` guarda solo valores cambiados + versión.
- `addons/godot_mcp` es herramienta de editor; `dev_bridge.gd` lo excluye del APK.

## Red (fase 2)
- ENet en 7777, 3 clientes. Canales: 0 eventos/acciones fiables, 1 input, 2 estado: ENet retiene un canal tras un fiable perdido.
- Sin throttle de ENet (descarta no fiables si sube la latencia); el estado pesa ~5 KB/s por cliente.
- ROUND lleva modo + semilla + cfg completa del anfitrión: con otra cfg, la misma semilla da otro mapa.
- Clientes: vistas interpolan (k = 15); saltan si el objetivo está a > 4 radios (reapariciones).
- Input remoto sin llegar 0.3 s → cero. Peer caído (≤ 8 s) o que sale → su ranura pasa a bot sin parar la ronda.
- Durante la partida la sala rechaza conexiones; `PROTOCOL` distinto → el cliente vuelve al menú.

## Dudas
- Rondas de laberinto con bots ~18 s (objetivo 60–120 s): ¿mapa mayor con cámara que sigue o rutas más largas?
- Sin predicción, los clientes sienten ida y vuelta + 33 ms + suavizado; el anfitrión juega con ventaja.
- Espiral con personajes de 40 px no cabe en 1080 → cámara que sigue (fase 4).

## Android y pruebas
- Permisos del preset: `INTERNET` y `VIBRATE` (hoy solo INTERNET: no vibra).
- `-s res://tests/test_maze.gd | test_spiral.gd | test_tilt.gd`; `res://tests/sim_bots.tscn -- 15` (con `--fixed-fps 60`); `sh tests/run_lan.sh` (LAN real en localhost).
