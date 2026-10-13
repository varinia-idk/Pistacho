# Pistacho v0.1.0

Party game 2D para Android en Godot 4.7.2: hasta 4 jugadores inclinan el teléfono para mover bolas con inercia. Ver `DESIGN.md` para supuestos y dudas abiertas.

**Versión actual: v0.1.0** — modo Laberinto, control por inclinación y dash, bots y red LAN para hasta 4 jugadores. Los bots ocupan los huecos libres. Esta versión reinicia la numeración tras la reescritura; la antigua v0.1.2 se conserva en la rama `legacy` y en la etiqueta `v0.1.2-legacy`.

Incluye inicio con fondo animado, Unirse, Sala con IP visible, Ajustes y Cómo jugar. Durante la partida hay marcador, ronda y tiempo, cuenta atrás, indicador de dash, pausa, resultados con medallas y ganador con corona. El modo Montaña/Espiral aún no es jugable: solo está implementado y probado su generador.

## Jugar
- En grupo: todos en la misma Wi-Fi (o el punto de acceso de un teléfono). Uno pulsa **Crear sala** y muestra su IP; los demás la escriben y pulsan **Unirse**. Puerto UDP 7777.
- Android: sostén el teléfono cómodo durante la cuenta 3-2-1 (calibración). Inclina para acelerar; giro brusco = dash.
- Escritorio: flechas = inclinar, Espacio = dash, Escape = pausa/volver.
- Android: Atrás pausa durante la partida, vuelve en los menús y cierra el juego desde el inicio. En LAN, abrir la pausa no detiene la partida de los demás.
- Ajustes: sensibilidad, dificultad de bots, 3/5/7 rondas, vibración e inversión de ejes. Se guardan en `user://config.json`.
- El botón **DBG**, con ajustes finos y diagnósticos, solo aparece al ejecutar con el binario del editor; no aparece en el APK, tampoco en la exportación de depuración.

## Abrir el proyecto

Importa `project.godot` en **Godot 4.7.2** y ejecuta la escena principal. No necesita dependencias externas. El addon opcional `addons/godot_mcp/` queda fuera del repositorio y del APK; para usarlo localmente, instálalo y actívalo desde los plugins del editor. El puente de desarrollo no hace nada si el addon no existe.

## Estructura
```text
scripts/autoload/   Config (números ajustables), Net (sala y RPCs) y Game (rondas, puntos, input, bots)
scripts/core/       GameMode (base de los modos), interpolación de red y puente del MCP de editor
scripts/input/      Lectura de inclinación y gesto de dash
scripts/players/    Jugador (RigidBody2D), vista y bot
scripts/modes/      maze/ (generador puro + modo) y mountain/ (generador de espiral)
scripts/ui/         Escena principal, menús, tema, fondo animado, widgets, HUD y overlay del editor
tests/              test_maze, test_spiral, test_tilt, test_interp, sim_bots y sim_lan + run_lan.sh
```

## Tests

Ejecuta desde la raíz del proyecto. La simulación LAN necesita permiso para abrir sockets UDP locales. Las simulaciones usan los ajustes locales de `Config`; para comparar resultados, restablécelos desde Ajustes.

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . -s res://tests/test_maze.gd
godot --headless --path . -s res://tests/test_spiral.gd
godot --headless --path . -s res://tests/test_tilt.gd
godot --headless --path . -s res://tests/test_interp.gd
godot --headless --path . --fixed-fps 60 res://tests/sim_bots.tscn -- 15   # simulación solo con bots
sh tests/run_lan.sh                                                          # LAN real: anfitrión + 2 clientes
```

Validación de v0.1.0 con Godot 4.7.2: 500 semillas de laberinto y 200 de espiral sin fallos; inclinación e interpolación sin fallos; 15 rondas de bots sin atascos sin resolver; simulación LAN con anfitrión y dos clientes aprobada. Consulta `DESIGN.md` para los resultados y sus límites.

## Exportar Android

Necesitas las plantillas de exportación **4.7.2**, Android SDK, Java y un keystore de depuración configurados en el editor. Con ese entorno preparado:

```sh
mkdir -p build
godot --headless --path . --export-debug Android build/pistacho-v0.1.0-debug.apk
```

El preset genera un APK firmado de depuración para `arm64-v8a` y `x86_64`, paquete `com.fabricio.pistacho`, versión `0.1.0`, código `4`, con permisos `INTERNET` y `VIBRATE`. `build/` y los keystores se excluyen de git. Es un APK para pruebas; la firma de distribución no está configurada en el repositorio.
