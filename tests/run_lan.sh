#!/bin/sh
# Prueba LAN real en localhost: 1 anfitrión + 2 clientes headless; el segundo se va a mitad de ronda.
# Uso: sh tests/run_lan.sh   (variable GODOT para otro binario)
set -u
cd "$(dirname "$0")/.."
OUT=tests/output
mkdir -p "$OUT"
LOGS="$OUT/lan-host.log $OUT/lan-client1.log $OUT/lan-client2.log"
rm -f $LOGS
GODOT=${GODOT:-godot}
run() { perl -e 'alarm shift; exec @ARGV' 90 "$GODOT" --headless --path . res://tests/sim_lan.tscn -- "$@"; }

run host 2 > "$OUT/lan-host.log" 2>&1 &
HOST=$!
sleep 1
run client 0 > "$OUT/lan-client1.log" 2>&1 &
C1=$!
sleep 0.5
run client 5 > "$OUT/lan-client2.log" 2>&1 &
C2=$!
wait $HOST $C1 $C2

FAIL=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FALLA $1"; FAIL=1; fi; }
num() { grep -h "$1" "$2" | head -1 | sed -E 's/.*[=: ]([-0-9.]+)( Hz)?$/\1/'; }

MAPS=$(grep -h '^LAN mapa' $LOGS | sort -u | wc -l | tr -d ' ')
COUNT=$(grep -h '^LAN mapa' $LOGS | wc -l | tr -d ' ')
check "mismo mapa en los 3 procesos ($COUNT reportes)" '[ "$MAPS" = 1 ] && [ "$COUNT" = 3 ]'
HDY=$(num 'LAN host ranura1 dy' "$OUT/lan-host.log")
check "la inclinación del cliente mueve su bola en el anfitrión (dy=$HDY)" 'awk "BEGIN{exit !(${HDY:-0} > 50)}"'
CDY=$(num 'LAN client ranura1 dy' "$OUT/lan-client1.log")
check "el cliente ve su bola moverse (dy=$CDY)" 'awk "BEGIN{exit !(${CDY:-0} > 50)}"'
HZ=$(num 'LAN client estados' "$OUT/lan-client1.log")
check "estado a ~30 Hz ($HZ Hz)" 'awk "BEGIN{exit !(${HZ:-0} > 24 && ${HZ:-0} < 36)}"'
check "el cliente que se va pasa a bot" 'grep -q "LAN host ranura2 bot" "$OUT/lan-host.log"'
check "fin de partida en anfitrión y cliente" 'grep -q "LAN host fin" "$OUT/lan-host.log" && grep -q "LAN client fin" "$OUT/lan-client1.log"'
check "el cliente vuelve al menú al cerrar la sala" 'grep -q "LAN client desconectado" "$OUT/lan-client1.log"'
check "sin errores" '! grep -hE "SCRIPT ERROR|^ERROR" $LOGS'
exit $FAIL
