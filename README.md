# Pistacho

Juego arcade 2D en **GDScript / Godot 4.7.2** para Android. Hasta cuatro personas compiten inclinando sus teléfonos, conectadas a la misma red Wi-Fi o a un hotspot. Incluye práctica individual y controles de escritorio.

Resolución base de presentación: **1920 × 1080**. En escritorio la ventana arranca maximizada; en Android utiliza pantalla completa. El dibujo 2D se renderiza a la resolución de la ventana y la interfaz conserva sus proporciones al adaptarse al área disponible.

## Jugar

1. Abre `project.godot` con Godot y pulsa **F6** sobre la escena principal, o **F5** para iniciar el proyecto.
2. Para jugar solo, pulsa **Practicar en solitario**, elige modo y pulsa **Comenzar**.
3. Para multijugador, conecta todos los teléfonos a la misma red. Uno pulsa **Crear sala**; los demás introducen su IP y el puerto que muestra la sala y pulsan **Conectar**. Predeterminado: UDP `24567`.
4. Cada jugador sostiene el teléfono en una posición cómoda, pulsa **Calibrar posición neutral** y **Estoy listo**. El anfitrión elige el modo y comienza.
5. Al terminar, el anfitrión pulsa **Volver a la sala** para jugar otra ronda.

Las redes de invitados pueden aislar dispositivos e impedir la conexión. La conexión es local: no requiere cuentas ni servidor externo. Si aparecen varias IP, utiliza la de la red Wi-Fi compartida. Para un hotspot, los invitados usan la dirección del teléfono que aloja la sala.

### Controles

| Acción | Android | Escritorio |
|---|---|---|
| Moverse | Inclinar el teléfono | WASD / flechas |
| Usar objeto | Botón inferior derecho | Espacio / botón |
| Recalibrar | Botón Calibrar | C / botón |
| Control alternativo | Activar Táctil en la sala | Joystick con ratón |

El control combina **giroscopio y gravedad** para medir la inclinación respecto a tu posición cómoda. Pulsa **Calibrar** y mantén el teléfono quieto medio segundo. Con sensibilidad predeterminada empieza a responder desde 1,2° y alcanza velocidad máxima a 18°. La sensibilidad se ajusta en la sala y se guarda localmente; mantener una inclinación conserva el movimiento.

Si falta el giroscopio o la gravedad, utiliza los sensores disponibles y el acelerómetro filtrado. Si no hay lecturas utilizables, ofrece joystick temporal y recupera la inclinación al volver los sensores. Una selección manual de control táctil se conserva. La orientación es horizontal fija.

## Modos

**Laberinto.** Cada personaje sale de una esquina de un mapa aleatorio. Gana el primero que toque el cetro central. Desde los 20 segundos aparecen cajas, cada 12 segundos, con un máximo de tres. Puedes guardar un objeto y activarlo cuando quieras:

- **Nuevo laberinto:** cambia el mapa conservando exactamente las posiciones actuales y abriendo rutas seguras hacia el centro. Retira cajas y peligros del mapa anterior.
- **Controles invertidos:** invierte solo a los rivales durante 8 segundos.
- **Agujeros:** aparecen seis durante 8 segundos después de un aviso de 1 segundo. Afectan a todos.
- **Perseguidores:** tres enemigos recorren los pasillos durante 8 segundos y devuelven a quien toquen a su esquina, incluido el dueño del objeto.

Los eventos del mismo tipo se reemplazan; las duraciones no se suman. Reaparecer vacía el objeto, limpia efectos personales y concede 2 segundos de protección frente a peligros y empujones.

**Rey de la montaña.** Los cuatro accesos se unen en una única espiral. Mantente solo en la cima durante 15 segundos continuos para ganar. Salir o compartir la cima reinicia el contador. Las bombas avisan antes de explotar y las minas visibles se rearman después de usarse. Las explosiones y los rivales pueden empujarte fuera del camino: caer devuelve a tu esquina.

La caja de crecimiento se activa al recogerla: aumenta el tamaño y duplica la resistencia al empuje durante 8 segundos. En esta vista superior, esa resistencia representa el mayor peso. La práctica conserva las mismas reglas, con un solo personaje.

## Organización

```text
scenes/       Escenas reutilizables de interfaz, personajes, arena y objetos
scripts/
  core/       Reglas, simulación, sonido y puente de desarrollo
  network/    Salas, RPC, sincronización y desconexiones
  input/      Inclinación, calibración y sensibilidad
  players/    Cuerpo físico y representación del personaje
  modes/      Generación de laberintos, espiral y dibujo del mapa
  objects/    Representación de cajas y peligros
  ui/         Menú, sala, HUD, resultados y joystick
resources/    GameRules: tiempos, velocidades y fuerzas ajustables
assets/       Icono original; gráficos y sonidos generados por código
tests/        Reglas, física e integración ENet con procesos reales
docs/         Arquitectura, exportación y validación Android
build/        APK y capturas locales (ignorado por Git)
```

Para afinar el juego, abre `resources/game_rules.tres` en el inspector. Los valores predeterminados y sus unidades están en `scripts/core/game_rules.gd`.

## Verificar

Sin instalar dependencias:

```sh
godot --headless --path . --script tests/test_suite.gd
python3 tests/run_network.py
```

Las pruebas de red abren puertos UDP locales y lanzan hasta cuatro procesos Godot. Comprueban estado final idéntico, eventos, regreso a la sala y desconexiones. Guardan los registros en `tests/output/`. Deben ejecutarse en un entorno que permita conexiones locales.

Para exportar y probar en Android, consulta [docs/ANDROID.md](docs/ANDROID.md). La arquitectura y las limitaciones están en [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md).
