# Android: exportación y validación

## Exportar

El preset **Android** usa:

- Identificador: `com.fabricio.pistacho`; versión `0.1.2`, código 3.
- Arquitecturas ARM64 y x86_64 (esta última permite emuladores).
- Orientación horizontal, pantalla inmersiva y renderizado Compatibility.
- Presentación base 1920 × 1080, escalado `canvas_items` y pantalla completa en móviles. La ventana maximizada se aplica al escritorio; el teléfono utiliza su resolución disponible y respeta el área segura.
- Permiso `INTERNET`, necesario también para Wi-Fi local.
- Sensores de gravedad, acelerómetro y giroscopio habilitados en el proyecto.
- Interpolación física habilitada, física a 60 Hz, VSync y frame pacing Android habilitados; sin redondear posiciones a píxeles ni imponer un límite de 30 FPS.
- Firma de depuración de Godot; no incluye claves de publicación.

Requisitos: Godot 4.7.2 con sus plantillas de exportación, Android SDK con build-tools y un JDK compatible configurados en **Editor → Configuración del editor → Exportar → Android**. El entorno de desarrollo utilizado ya dispone de estos componentes; no se añadieron dependencias.

Desde el proyecto:

```sh
mkdir -p build
godot --headless --path . --export-debug Android build/pistacho-debug.apk
```

También puedes usar **Proyecto → Exportar → Android → Exportar proyecto**, activando depuración. El preset excluye `addons/godot_mcp`, pruebas, documentación y artefactos locales.

Para instalar en un dispositivo conectado y autorizado:

```sh
adb devices -l
adb install -r build/pistacho-debug.apk
adb shell am start -n com.fabricio.pistacho/com.godot.game.GodotApp
```

El APK de depuración permite pruebas locales. Para publicar hará falta una firma de lanzamiento y revisar los requisitos vigentes de la tienda.

## Validación manual pendiente en teléfonos físicos

No había dispositivos conectados a ADB durante la implementación. Completar esta tabla en dispositivos reales antes de considerar validado Android:

| Prueba | Resultado esperado |
|---|---|
| Inclinación en cuatro direcciones | El personaje sigue la inclinación después de calibrar |
| Posición cómoda neutral | El personaje permanece quieto y no deriva |
| Inclinar unos 6° / 18° tras calibrar | Movimiento suave / velocidad máxima con sensibilidad 1,5 |
| Arranque de sensores con demora | Joystick temporal; vuelve a inclinación cuando llegan lecturas válidas |
| Volver de otra app o desbloquear | Conserva la calibración; descarta movimiento anterior |
| Sin sensor de gravedad | Acelerómetro filtrado o joystick utilizables |
| Pantallas con recortes | HUD y botones dentro del área segura |
| Wi-Fi con 2 y 4 teléfonos | Sala, cuenta regresiva y mapas compartidos |
| Hotspot, anfitrión como punto de acceso | Invitados se conectan a su IP local |
| Regeneración con jugadores moviéndose | Coordenadas conservadas, ningún jugador encerrado |
| Empujones y explosiones | Mismo resultado en todos los teléfonos |
| Cambiar de app, bloquear pantalla o perder Wi-Fi | Sin entradas atascadas; desconexión manejada |
| Ambos modos durante 10 minutos | Objetivo de 60 FPS sin calentamiento excesivo |
| Movimiento continuo en práctica, pantallas 60/90/120 Hz | Avance uniforme sin pulsaciones a 20 Hz |
| Wi-Fi con variación moderada en llegada de paquetes | Interpolación continua; margen visual de 150 ms solo en clientes |

Registrar modelo, Android, FPS, duración y condiciones de red. El objetivo de rendimiento no se ha medido en hardware físico.
