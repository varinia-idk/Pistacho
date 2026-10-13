# Pistacho

Party game 2D para Android en Godot 4.7.2: hasta 4 jugadores inclinan el teléfono para mover bolas con inercia. Ver `DESIGN.md` para supuestos y dudas abiertas.

**Estado: fase 1** — control por inclinación + dash, modo Laberinto, bots y overlay de debug, en un teléfono.

## Jugar
- Android: sostén el teléfono cómodo durante la cuenta 3-2-1 (calibración). Inclina para acelerar; giro brusco = dash.
- Escritorio: flechas = inclinar, Espacio = dash, E = ítem.
- Botón **DBG** (arriba a la izquierda): un slider por cada valor de `Config`, lecturas de sensores, FPS. Se guarda en `user://config.json`.

## Estructura
```text
scripts/autoload/   Config (números ajustables) y Game (rondas, puntos, input, bots)
scripts/core/       GameMode (base de los modos) y puente del MCP de editor
scripts/input/      Lectura de inclinación y gesto de dash
scripts/players/    Jugador (RigidBody2D), vista y bot
scripts/modes/      maze/ (generador puro + modo) y mountain/ (generador de espiral)
scripts/ui/         Escena principal, HUD y overlay de debug
tests/              test_maze, test_spiral, test_tilt y sim_bots (simulación solo con bots)
```

## Tests
```sh
godot --headless --path . -s res://tests/test_maze.gd
godot --headless --path . -s res://tests/test_spiral.gd
godot --headless --path . -s res://tests/test_tilt.gd
godot --headless --path . --fixed-fps 60 res://tests/sim_bots.tscn -- 15   # simulación solo con bots
```

La versión anterior (v0.1.2) está en la etiqueta git `v0.1.2-legacy`.
