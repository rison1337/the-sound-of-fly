"""Headless smoke test of Brain+Ports: spontaneous activity, then light, then odor.

Usage: python tools/test_sim_headless.py [gain]
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from sim.brain import Brain
from sim.ports import Ports

gain = float(sys.argv[1]) if len(sys.argv) > 1 else 0.015
brain = Brain(ROOT / "data" / "graph_malecns_v1.npz", dt_ms=2.0, gain=gain)
ports = Ports(brain, ROOT / "data" / "annotations_malecns_v1.parquet")
print(f"gain={gain}")
print("groups:", {k: int(v.size) for k, v in ports.groups.items()})
print("motor:", {k: int(v.size) for k, v in ports.motor.items()})


def run(label: str, steps: int, stim: dict | None = None) -> None:
    for k in list(ports._stimuli):
        ports.set_stimulus(k, 0.0)
    for k, v in (stim or {}).items():
        if isinstance(v, tuple):
            ports.set_stimulus(k, *v)
        else:
            ports.set_stimulus(k, v)
    t0 = time.perf_counter()
    for _ in range(steps):
        ports.step()
    wall = time.perf_counter() - t0
    bio = steps * brain.dt_ms / 1000.0
    r = ports.readout()
    print(
        f"[{label}] {bio:.1f}s bio in {wall:.1f}s ({bio / wall:.2f}x RT) "
        f"active={r['active']}% turn={r['turn']:+.3f} speed={r['speed']:.3f}"
    )
    nz = {k: v for k, v in r["motor_hz"].items() if v > 0.01}
    print("   motor_hz:", nz if nz else "(silent)")
    print("   top:", [(t["type"], t["hz"]) for t in r["top"][:5]])


run("spontaneous", 2500)
run("light both", 2500, {"light": (0.9, 0)})
run("light right", 2500, {"light": (0.9, 1)})
run("odor ON", 2500, {"odor": (0.9, 0)})
