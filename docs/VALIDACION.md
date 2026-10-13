# Evidencia de validación

Entorno: macOS Apple Silicon, Godot `4.7.2.stable.official.ed1daf0bf`. No se instalaron dependencias. El directorio del proyecto no tenía repositorio Git.

## Pruebas automatizadas

### Fluidez de presentación (0.1.2)

`godot --headless --path . --script tests/test_presentation.gd`

Resultado: **22 comprobaciones, cero fallos**. Un movimiento uniforme recibido a 20 Hz conserva desplazamiento uniforme por fotograma a 30/60/90/120 FPS, con llegadas variables y un paquete perdido. Comprueba historial acotado, parada ante falta de datos sin extrapolar paredes, recuperación tras corte prolongado, rechazo de muestras antiguas y reapariciones cortas. La integración real con `Session` y `Arena` verifica una actualización de presentación por tick físico en práctica, en vez de solo 20 Hz, y la selección de interpolación local/remota.

Se repitieron las 69 comprobaciones del control, las 5.594 de reglas y las cinco pruebas ENet: aprobadas. Revisión MCP sin errores de ejecución durante la sesión observada.

Medición MCP del mismo lobby, viewport 1939 × 1080: al agrupar los puntos decorativos, las llamadas de dibujo bajaron de **992 a 50** y las primitivas de **62.870 a 4.404**. Ambas capturas tuvieron 43 nodos y cero nodos huérfanos. Son medidas del editor en macOS; no constituyen una medición de FPS ni de batería en Android. No se modificó la resolución para obtener esa reducción.

### Corrección del control móvil (0.1.1)

`godot --headless --path . --script tests/test_tilt.gd`

Resultado: **69 comprobaciones, cero fallos**, con lecturas sintéticas reproducibles. Incluye sensibilidad a 6° en menos de 150 ms, velocidad máxima a 18°, cuatro direcciones, neutral a 0°/45°/75°, frecuencias 30/60/120 Hz, ruido en reposo, acelerómetro sin giroscopio, respuesta del giroscopio ante gravedad demorada, corrección de deriva, arranque tardío, recuperación de sensores, valores inválidos, elección manual de táctil, suspensión/reanudación y recalibración. Estos tiempos corresponden a la salida del filtro; no miden latencia física del teléfono ni del renderizado.

El usuario reportó sensibilidad insuficiente y movimiento tosco en práctica individual con Android 12. Se corrigieron el umbral excesivo, la proyección dependiente de la postura, el filtrado doble, los signos de los ejes y la activación permanente de táctil después de un arranque tardío. La validación en ese teléfono sigue pendiente.

### Reglas y red

`godot --headless --path . --script tests/test_suite.gd`

Resultado: **5.594 comprobaciones, cero fallos**. Incluye 80 semillas reproducibles, conectividad de las cuatro esquinas, regeneración con espacio para personajes, objetos, peligros, protección, crecimiento, contador exclusivo de cima, victoria única, colisiones con paredes y entre jugadores, entrada caducada, validación de vectores, orden de snapshots y compresión reversible.

`python3 tests/run_network.py`

Resultados finales, con procesos reales y sockets ENet:

- Laberinto: 2 peers, estado final idéntico y regreso a sala.
- Laberinto: 4 peers, estado final idéntico y regreso a sala.
- Montaña: 4 peers, estado final idéntico y regreso a sala.
- Desconexiones: 4 peers, actualización de roster, continuación con 3/2 jugadores y cancelación con 1.
- Salida de anfitrión: cliente vuelve al menú con aviso.

La batería exige recepción continua de snapshots, coincidencia de sus hashes finales, ausencia de errores de ejecución y ausencia de avisos de fragmentación por MTU. Los registros finales están en `tests/output/`, ignorados por Git. Las victorias de integración se fuerzan para verificar el transporte del resultado; las condiciones reales de victoria se comprueban en la batería de reglas.

El sandbox bloquea puertos locales, por lo que las pruebas ENet se ejecutaron con permiso fuera del sandbox. Los tests headless dentro del sandbox pueden mostrar un error de certificados de macOS ajeno al juego; los procesos de red fuera del sandbox no lo presentan.

## Editor y paquete

- Conexión MCP con el editor operativa.
- Menú, sala y ambos modos ejecutados y revisados mediante MCP; sin errores de ejecución del juego.
- Capturas de referencia: `build/menu.png`, `build/maze.png`, `build/mountain.png`.
- Ajuste de resolución: base 1920 × 1080, ventana de escritorio maximizada y pantalla completa para móviles. Verificado mediante MCP: ventana real de 3456 × 1924, modo maximizado, interfaz completa y cero errores de ejecución. Captura: `build/menu-hd.png`.
- Exportación Android de depuración completada, firmada y verificada por Godot.
- Contenido del APK revisado: escenas presentes; sin archivos del complemento MCP ni pruebas.

## Pendiente en hardware

ADB no detectó dispositivos conectados. No se verificaron sensores, rendimiento, batería ni conexión Wi-Fi entre teléfonos físicos. La matriz para completar esas pruebas está en [ANDROID.md](ANDROID.md).
