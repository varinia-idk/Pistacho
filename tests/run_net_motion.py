"""Run real ENet peers through a deterministic UDP delay/loss proxy (stdlib only)."""

import heapq
import argparse
import math
import os
from pathlib import Path
import random
import re
import selectors
import socket
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["free", "walls", "contact", "respawn"], default="free")
    parser.add_argument("--fps", type=int, default=120)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / "tests/output"
    output.mkdir(exist_ok=True)
    rng = random.Random(1234)
    pending = []
    counter = 0
    client_address = None
    selector = selectors.DefaultSelector()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as front, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as back:
        front.bind(("127.0.0.1", 17777))
        back.bind(("127.0.0.1", 0))
        front.setblocking(False)
        back.setblocking(False)
        selector.register(front, selectors.EVENT_READ)
        selector.register(back, selectors.EVENT_READ)
        command = [os.environ.get("GODOT", "godot"), "--headless", "--path", str(root), "--max-fps", str(args.fps), "res://tests/sim_net_motion.tscn", "--"]
        with (output / "motion-host.log").open("w") as host_log, (output / "motion-client.log").open("w") as client_log:
            host = subprocess.Popen(command + ["host", args.scenario], stdout=host_log, stderr=subprocess.STDOUT)
            client = None
            try:
                time.sleep(0.5)
                client = subprocess.Popen(command + ["client", args.scenario], stdout=client_log, stderr=subprocess.STDOUT)
                start = time.monotonic()
                while time.monotonic() - start < 40 and (host.poll() is None or client.poll() is None):
                    now = time.monotonic()
                    for key, _ in selector.select(0.002):
                        data, address = key.fileobj.recvfrom(65535)
                        if key.fileobj is front:
                            client_address = address
                            target, destination = back, ("127.0.0.1", 7777)
                        else:
                            target, destination = front, client_address
                        if destination is None or rng.random() < 0.02:
                            continue
                        delay = rng.uniform(0.025, 0.070)
                        if (now - start) % 3 < 0.18:
                            delay += 0.180
                        counter += 1
                        heapq.heappush(pending, (now + delay, counter, target, destination, data))
                    while pending and pending[0][0] <= now:
                        _, _, target, destination, data = heapq.heappop(pending)
                        target.sendto(data, destination)
            finally:
                for process in [host, client]:
                    if process is not None and process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)
    logs = [(output / f"motion-{role}.log").read_text() for role in ["host", "client"]]
    for log in logs:
        lines = log.splitlines()
        print("\n".join(line for line in lines if line.startswith(("MOTION", "ERROR", "SCRIPT ERROR")))[:3000])
    if host.returncode != 0 or client is None or client.returncode != 0 or any("ERROR" in log for log in logs):
        raise SystemExit("FALLA: proceso, tiempo límite o errores de Godot")
    host_final = re.search(r"host_final=([-\d.]+),([-\d.]+)", logs[0])
    client_final = re.search(r"jumps=(\d+) max_step=([\d.]+) correction=([\d.]+) final=([-\d.]+),([-\d.]+)", logs[1])
    if host_final is None or client_final is None:
        raise SystemExit("FALLA: faltan métricas de movimiento")
    gap = math.dist(tuple(map(float, host_final.groups())), tuple(map(float, client_final.groups()[3:])))
    if int(client_final[1]) != 0 or gap > 3:
        raise SystemExit(f"FALLA: saltos={client_final[1]}, desvío final={gap:.2f} px")
    expected_dash = int(args.scenario == "walls")
    expected_teleport = int(args.scenario == "respawn")
    for role, log in zip(["host", "client"], logs):
        if f"MOTION {role} dashes={expected_dash} teleports={expected_teleport}" not in log:
            raise SystemExit("FALLA: dash/reaparición no se ejecutó exactamente una vez")
    print(f"ok {args.scenario} a {args.fps} FPS: sin saltos espurios, desvío {gap:.3f} px")


if __name__ == "__main__":
    main()
