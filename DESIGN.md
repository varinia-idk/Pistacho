# Pistacho — diseño (fases 1–2)

## Supuestos
- Ejes: Godot reorienta los sensores a la pantalla (x derecha, y arriba) → `invert_y = 1` por defecto.
- Inclinación = (g − g0) proyectada en el plano tangente a g0; las XY crudas pierden sensibilidad por cos(sujeción). Curva radial 1.5° / 15° / 1.25 (la spec pedía 2° / 25° / 1.6: tosco en móvil).
- Rebote: Godot suma el de ambos cuerpos; `wall_bounce` (0.3) y `player_bounce` (0.6) son el resultado real (la pared resta con absorbent).
- Control: fuerza 2400 + amortiguación 3 (con 1.0 toda inclinación acababa en velocidad máxima: se sentía acelerar solo) y `turn_boost` al inclinar contra la velocidad. Sigue siendo fuerza, nunca velocidad.
- Dash: anula la velocidad en contra, 550 px/s, sin amortiguación 0.45 s; el gesto congela la inclinación previa.
- `maze_min_path` relativo a la distancia Manhattan. Geometría = f(cfg de la ronda), nunca de la pantalla.
- Única asignación de posición: al crear el cuerpo, antes de entrar al árbol; después solo `teleport()`.
- Bots: si llevan `bot_patience` s bloqueados, retroceden un tiempo aleatorio; ante humanos siempre, entre bots el que va detrás.
- `user://config.json` guarda solo valores cambiados + versión. `addons/godot_mcp` es solo de editor (`dev_bridge.gd` lo excluye del APK).

## Red (fase 2)
- ENet en 7777, 3 clientes. Canales: 0 eventos/acciones fiables, 1 input, 2 estado: ENet retiene un canal tras un fiable perdido.
- Estado a 60 Hz (~13 KB/s por cliente) con el reloj de simulación del anfitrión. Sin throttle de ENet (descarta no fiables si sube la latencia).
- ROUND lleva modo + semilla + cfg completa del anfitrión: con otra cfg, la misma semilla da otro mapa.
- Clientes: interpolación por instantáneas, no el lerp de la spec (`test_interp`: tirón p95 77–94 % → 10 %). Retardo = 1.5 intervalos + jitter recordado 10 s (40–250 ms); sin datos, el dibujo va al 60 % en vez de congelarse; saltos > 4 radios no se interpolan.
- Input remoto sin llegar 0.3 s → cero. Peer caído (≤ 8 s) o que sale → su ranura pasa a bot sin parar la ronda.
- Durante la partida la sala rechaza conexiones; `PROTOCOL` distinto → el cliente vuelve al menú.

## Dudas
- Rondas de laberinto con bots ~20 s (objetivo 60–120 s): ¿mapa mayor con cámara que sigue o rutas más largas?
- Sin predicción, la bola propia de un cliente responde con ida y vuelta + retardo de dibujo (≈ 60–170 ms); el anfitrión juega con ventaja.
- Espiral con personajes de 40 px no cabe en 1080 → cámara que sigue (fase 4).
- Mac como cliente: AWDL (AirDrop/Handoff) pausa la Wi-Fi periódicamente; el overlay muestra "hueco máx" y "sin datos".

## Android y pruebas
- Permisos del preset: `INTERNET` y `VIBRATE` (hoy solo INTERNET: no vibra).
- `-s res://tests/test_maze.gd | test_spiral.gd | test_tilt.gd | test_interp.gd`; `res://tests/sim_bots.tscn -- 15` (con `--fixed-fps 60`); `sh tests/run_lan.sh` (LAN real en localhost).
