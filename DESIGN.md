# Pistacho — diseño v0.1.0

## Alcance de esta versión
- Laberinto es el único modo registrado en `Game.MODE_SCENES`. El generador de Espiral tiene tests, pero su modo jugable queda pendiente.
- Inicio, Unirse, Sala, Ajustes y Cómo jugar usan un tema común con la paleta del icono y gráficos dibujados en Godot. El HUD incluye cuenta atrás, marcador, tiempo, dash, pausa, resultados y ganador.
- Ajustes expone sensibilidad (1–10), bots (fácil/normal/difícil), rondas (3/5/7), vibración e inversión de ejes. La sensibilidad cambia el ángulo de saturación entre 30° y 8°.
- Atrás/Escape retrocede en menús, sale desde el inicio y abre la pausa durante la partida. Solo la partida local se detiene; en LAN los demás siguen jugando.
- El overlay DBG depende de la característica `editor`; las plantillas exportadas, incluso las de depuración, no lo muestran.
- La rama `legacy` y la etiqueta `v0.1.2-legacy` conservan la versión anterior a la reescritura. La línea actual comienza en v0.1.0.

## Supuestos
- Ejes: Godot reorienta los sensores a la pantalla (x derecha, y arriba) → `invert_y = 1` por defecto.
- Inclinación = (g − g0) proyectada en el plano tangente a g0; las XY crudas pierden sensibilidad por cos(sujeción). Curva radial 1.5° / 15° / 1.25 (la spec pedía 2° / 25° / 1.6: tosco en móvil).
- Rebote: Godot suma el de ambos cuerpos; `wall_bounce` (0.3) y `player_bounce` (0.6) son el resultado real (la pared resta con absorbent).
- Control: fuerza 2400 + amortiguación 3 (con 1.0 toda inclinación acababa en velocidad máxima: se sentía acelerar solo) y `turn_boost` al inclinar contra la velocidad. Sigue siendo fuerza, nunca velocidad.
- Dash: anula la velocidad en contra, 550 px/s, sin amortiguación 0.45 s; el gesto congela la inclinación previa.
- `maze_min_path` relativo a la distancia Manhattan. Geometría = f(cfg de la ronda), nunca de la pantalla.
- Única asignación de posición: al crear el cuerpo, antes de entrar al árbol; después solo `teleport()`.
- Bots: si llevan `bot_patience` s bloqueados, retroceden un tiempo aleatorio; ante humanos siempre, entre bots el que va detrás.
- `user://config.json` guarda solo valores cambiados + versión. `addons/godot_mcp/` es opcional y local: se ignora en git, se eliminó del historial publicado y el preset lo excluye del APK. `dev_bridge.gd` solo lo carga si existe, con el binario del editor y fuera de headless.

## Red (fase 2)
- ENet en 7777, 3 clientes. Canales: 0 eventos/acciones fiables, 1 input, 2 estado: ENet retiene un canal tras un fiable perdido.
- Estado a 60 Hz (~13 KB/s por cliente) con el reloj de simulación del anfitrión. Sin throttle de ENet (descarta no fiables si sube la latencia).
- ROUND lleva modo + semilla + cfg completa del anfitrión: con otra cfg, la misma semilla da otro mapa.
- Clientes: interpolación por instantáneas, no el lerp de la spec (`test_interp`: tirón p95 77–94 % → 10 %). Retardo = 1.5 intervalos + jitter recordado 10 s (40–250 ms); sin datos, el dibujo va al 60 % en vez de congelarse; saltos > 4 radios no se interpolan.
- Predicción (`net_predict`, desvío de la spec): el cliente simula su bola con la cfg de la ronda y paredes locales; el anfitrión devuelve el último input aplicado y el cliente corrige (física al instante, vista suave). Caídas, metas y choques entre jugadores siguen siendo del anfitrión. Respuesta en localhost: 111 → ~50 ms.
- Input remoto sin llegar 0.3 s → cero. Peer caído (≤ 8 s) o que sale → bot sin parar la ronda. En partida la sala rechaza conexiones; `PROTOCOL` distinto → menú.

## Limitaciones y trabajo futuro
- Rondas de laberinto con bots ~20 s (objetivo 60–120 s): ¿mapa mayor con cámara que sigue o rutas más largas?
- Los choques con otros jugadores se ven en el cliente con ida y vuelta de retraso (no se predicen).
- Espiral con personajes de 40 px no cabe en 1080 → cámara que sigue (fase 4).
- Mac como cliente: AWDL (AirDrop/Handoff) pausa la Wi-Fi periódicamente; el overlay muestra "hueco máx" y "sin datos".

## Android y pruebas
- Preset Android: paquete `com.fabricio.pistacho`, versión `0.1.0`, código `4`; arquitecturas `arm64-v8a` y `x86_64`; permisos `INTERNET` y `VIBRATE`. Vibración activable desde Ajustes.
- Exportación de prueba: `godot --headless --path . --export-debug Android build/pistacho-v0.1.0-debug.apk`. Firma de depuración, sin credenciales de distribución en git.
- `-s res://tests/test_maze.gd | test_spiral.gd | test_tilt.gd | test_interp.gd`; `res://tests/sim_bots.tscn -- 15` (con `--fixed-fps 60`); `sh tests/run_lan.sh` (LAN real en localhost).

### Validación de cierre (2026-10-13, Godot 4.7.2)
- Laberinto: 500 semillas, cuadrícula 22×13, 1872 reintentos del generador y 0 fallos. Espiral: 200 semillas, 0 reintentos y 0 fallos.
- Inclinación: 0 fallos. Interpolación: 0 fallos en los tres perfiles de red a 60 y 120 FPS; como máximo un frame detenido en el perfil de pausas periódicas.
- Bots: 15 rondas, media 20.8 s, máximo 25.6 s; tres parones mayores a 3 s, ninguno mayor a 6 s y ninguno sin resolver. La simulación usa semillas aleatorias; sus tiempos no son una garantía para todas las partidas.
- LAN: anfitrión y dos clientes locales, mismo mapa, estados a 60 Hz, respuesta de 46 ms, corrección máxima de 11.7 px ante el empujón del anfitrión y diferencia final de 0.0 px. Se comprobaron sustitución por bot, fin de partida y regreso al menú al cerrar la sala, sin errores.
- Revisión visual de Inicio, Ajustes, Cómo jugar y Unirse mediante capturas; sin recortes ni solapamientos observados.
- Copia limpia de los archivos versionados: importación y arranque headless sin errores ni addon MCP.
- APK de depuración exportado y firma verificada (esquemas v2/v3). Manifiesto comprobado: versión 0.1.0, código 4, Android mínimo 7.0/API 24, ambas arquitecturas y permisos esperados. El paquete no contiene el addon, tests ni capturas de revisión.
- Estas comprobaciones de escritorio no sustituyen una prueba física de sensores, vibración, Atrás y Wi-Fi entre teléfonos Android.
