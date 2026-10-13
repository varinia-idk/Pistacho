"""Run actual ENet peers, require matching final snapshots and a clean exit."""
from pathlib import Path
import shutil
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tests" / "output"
OUTPUT.mkdir(exist_ok=True)
GODOT = shutil.which("godot")
if not GODOT:
    raise SystemExit("godot is not on PATH")

for mode, count in (("maze", 2), ("maze", 4), ("mountain", 4)):
    peers = []
    files = []
    try:
        for index in range(count):
            log = (OUTPUT / f"{mode}-{count}-{index}.log").open("w")
            files.append(log)
            command = [GODOT, "--headless", "--path", str(ROOT), "--script",
                       "tests/network_peer.gd", "--", f"role={'host' if index == 0 else 'client'}",
                       f"count={count}", f"mode={mode}", f"port={24677 + count}"]
            peers.append(subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT))
            time.sleep(0.4 if index == 0 else 0.15)
        codes = [peer.wait(timeout=28) for peer in peers]
    finally:
        for peer in peers:
            if peer.poll() is None:
                peer.terminate()
                peer.wait(timeout=5)
        for log in files:
            log.close()
    texts = [(OUTPUT / f"{mode}-{count}-{index}.log").read_text() for index in range(count)]
    hashes = [line.split()[1] for text in texts for line in text.splitlines() if line.startswith("FINAL_STATE ")]
    if any(codes) or len(hashes) != count or len(set(hashes)) != 1 or any(re.search(r"^(?:SCRIPT )?ERROR:", text, re.M) or "above the MTU" in text for text in texts):
        for text in texts:
            print(text[-6000:])
        raise SystemExit(f"FAILED {mode} / {count} peers: codes={codes}, hashes={hashes}")
    print(f"PASS {mode}: {count} ENet peers, same final state, lobby return")

for scenario, count in (("disconnects", 4), ("host_exit", 2)):
    peers, files = [], []
    try:
        for index in range(count):
            log = (OUTPUT / f"{scenario}-{index}.log").open("w")
            files.append(log)
            peers.append(subprocess.Popen(
                [GODOT, "--headless", "--path", str(ROOT), "--script", "tests/network_lifecycle.gd",
                 "--", f"index={index}", f"scenario={scenario}"],
                cwd=ROOT, stdout=log, stderr=subprocess.STDOUT))
            time.sleep(0.4 if index == 0 else 0.15)
        codes = [peer.wait(timeout=22) for peer in peers]
    finally:
        for peer in peers:
            if peer.poll() is None:
                peer.terminate()
                peer.wait(timeout=5)
        for log in files:
            log.close()
    texts = [(OUTPUT / f"{scenario}-{index}.log").read_text() for index in range(count)]
    if any(codes) or any("LIFECYCLE PASS" not in text or re.search(r"^(?:SCRIPT )?ERROR:", text, re.M) for text in texts):
        print("\n".join(text[-6000:] for text in texts))
        raise SystemExit(f"FAILED lifecycle {scenario}: {codes}")
    print(f"PASS lifecycle: {scenario}, {count} peers")
