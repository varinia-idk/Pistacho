# Arquitectura

## Simulación y presentación

`Session` es el autoload de sesión y conserva la conexión al pasar de menú a sala y partida. Solo el anfitrión crea `MatchSimulation`, que avanza a 60 Hz y decide movimiento, colisiones, recogidas, peligros y victoria. La práctica usa la misma simulación con un peer offline.

Cada personaje físico es un `CharacterBody2D`. Las paredes del laberinto son un `StaticBody2D` con formas rectangulares. El empuje entre personajes se resuelve explícitamente por pares para aplicar la masa y evitar que cada cliente produzca resultados distintos. La montaña usa la distancia al camino espiral para detectar caídas, con una tolerancia basada en el radio del personaje.

`Arena`, `Avatar` y `ObjectVisual` representan estados; no deciden física. En práctica y en el anfitrión reciben cada paso físico (60 Hz). `MotionVisual` asigna esas posiciones en el tick y Godot interpola entre ellas según el refresco de pantalla. Los clientes usan `MotionTrack`: interpolación lineal por tiempo entre snapshots de 20 Hz, con 150 ms de margen para variaciones de llegada y un paquete perdido. No se aplica el antiguo seguimiento exponencial, que aceleraba/frenaba cada 50 ms, ni doble interpolación en clientes. El contador `respawn_serial` reinicia la interpolación incluso en reapariciones cercanas.

VSync y frame pacing de Android se mantienen habilitados, con FPS sin un límite artificial y física a 60 Hz. Se habilita interpolación física y se desactiva `physics_jitter_fix` para evitar correcciones de reloj sobre la interpolación. La interfaz opta fuera de interpolación y conserva posiciones fraccionarias. Referencia: [interpolación de Godot](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html).

Los fondos del laberinto y montaña se dibujan al cambiar el mapa; el progreso de cima tiene un nodo de dibujo separado. Mover un personaje reutiliza su dibujo, excepto durante efectos animados. Se precargan las escenas de personajes/objetos y se reutiliza el estilo de cajas. Los puntos decorativos del fondo se dibujan en lote. Los sonidos se sintetizan en memoria.

## Control por inclinación

`TiltInput` lee los sensores en el tick físico con prioridad -100, antes de `Session`. El anfitrión y la práctica consumen la entrada cada tick (60 Hz); los clientes mantienen 30 Hz por red. `TiltFilter` contiene la matemática sin depender de hardware: predicción con velocidad angular y corrección con gravedad, o acelerómetro si no hay gravedad. Sin giroscopio usa un único filtro exponencial (sin la doble demora anterior).

La calibración promedia 350 ms de lecturas estables y construye ejes tangentes a la gravedad neutral. El desplazamiento angular evita perder sensibilidad al sostener el teléfono inclinado. Zona muerta radial 1,2°; velocidad máxima a 18° con sensibilidad 1,5. Un corte de lecturas de 150 ms detiene la entrada; tras 1 s se ofrece táctil temporal. La recuperación no cambia la preferencia manual de táctil. Al suspender se borra la entrada; al volver se conserva la neutral y se reinicia la estimación.

Godot Android ya rota los sensores según la pantalla y entrega gravedad con signo opuesto al acelerómetro nativo de Android; el giroscopio mantiene su signo. Referencias oficiales: [transformación de ejes](https://github.com/godotengine/godot/blob/master/platform/android/java/lib/src/main/java/org/godotengine/godot/input/GodotInputHandler.java), [signos de gravedad y giroscopio](https://github.com/godotengine/godot/blob/master/platform/android/java/lib/src/main/java/org/godotengine/godot/input/InputEventRunnable.java). No se repite la rotación de paisaje en GDScript.

## Generación

El laberinto usa búsqueda en profundidad sobre una cuadrícula 25 × 15. La semilla reproduce el mapa. Las cuatro esquinas están conectadas al cetro central. Regenerar limpia todas las celdas que intersectan los personajes y abre rutas al centro conservando sus coordenadas.

La montaña es una polilínea espiral de dos vueltas, con cuatro accesos que convergen en la entrada inferior. El mismo modelo define el dibujo y la zona transitables. Los agujeros excluyen posiciones, esquinas, cetro y otros objetos al generarse; los enemigos recalculan rutas por BFS.

## Contrato de red

- Transporte: ENet, servidor jugador, puerto UDP configurable (24567 por defecto), máximo tres clientes. Protocolo interno versión 1.
- Sala: roster con peer, número/color, nombre y estado listo. Solo el anfitrión elige modo y comienza. Las nuevas entradas se rechazan durante una ronda.
- Entradas: dirección normalizada a 30 Hz, RPC `unreliable_ordered`, canal 1. El anfitrión obtiene la identidad del remitente y rechaza vectores no finitos; una entrada expira tras 250 ms.
- Estados: snapshots a 20 Hz, canal 2, comprimidos con Zstandard para reducir fragmentación UDP. Incluyen secuencia, revisión de mapa, reloj, jugadores, objetos, contador de cima y ganador.
- Eventos: checkpoints completos y audio mediante RPC fiable, canal 0. Los clientes descartan secuencias anteriores y estados de otra revisión.
- Mapa: el anfitrión distribuye la cuadrícula/geometría completa mediante RPC fiable. La simulación espera confirmación de todos los clientes antes de comenzar o continuar después de regenerar. Tras 8 segundos sin confirmar, desconecta al peer que falta.

Los nombres de nodos RPC permanecen estables en `/root/Session`. No se transmiten objetos, recursos ni rutas ejecutables. Los clientes solicitan usar objetos; el servidor comprueba que les pertenezcan y los consume una sola vez.

## Flujo y fallos

Estados: `menu`, `connecting`, `lobby`, `match`, `results`. La conexión tiene un límite de espera de 8 segundos. Salir cierra ENet y destruye la simulación. Perder un cliente actualiza el roster y retira su cuerpo; si queda solo el anfitrión, se cancela la ronda. Perder al anfitrión lleva a los clientes al menú con un mensaje.

No se migra el anfitrión ni se reconecta un jugador a una ronda iniciada. No hay matchmaking, Bluetooth, Internet, torneo ni tercer modo. Los empates de recogida se resuelven por orden estable de participantes; el empate en el cetro usa distancia y después número de jugador.

## Desarrollo y exportación

El complemento MCP existente permanece disponible en el editor. El autoload `MCPRuntime` apunta a un puente que carga el helper únicamente en ejecuciones gráficas del editor. El preset Android excluye el complemento, pruebas y documentación; el APK conserva solo el puente inactivo.

La implementación no requiere bibliotecas, plugins Android ni recursos externos. Las pruebas con escritorio no sustituyen la validación de sensores, rendimiento y Wi-Fi en teléfonos físicos.
