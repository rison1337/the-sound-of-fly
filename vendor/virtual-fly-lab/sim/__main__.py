"""Run the fly brain simulation server:  python -m sim [--port 9876] [--gpu auto]

Real-time paced loop: steps the brain at dt_ms of biology per dt_ms of wall
clock, drains commands from connected clients (stim / add_stim / remove_stim /
pose), publishes state ~10 Hz.
"""
import argparse
import time
from pathlib import Path

from .arena import Arena
from .brain import Brain
from .ports import Ports
from .server import SimServer

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=9876)
    ap.add_argument("--dt-ms", type=float, default=2.0)
    ap.add_argument("--gpu", choices=["auto", "on", "off"], default="auto")
    ap.add_argument("--graph", type=Path, default=ROOT / "data" / "graph_malecns_v1.npz")
    ap.add_argument("--ann", type=Path, default=ROOT / "data" / "annotations_malecns_v1.parquet")
    args = ap.parse_args()

    print("loading graph ...", flush=True)
    brain = Brain(args.graph, dt_ms=args.dt_ms, gpu_mode=args.gpu)
    print(f"neurons: {brain.n:,}  kernel: {brain.kernel_name}", flush=True)
    ports = Ports(brain, args.ann)
    arena = Arena()
    server = SimServer(port=args.port, port_file=ROOT / "world" / "data" / "sim_port.txt")
    print(f"SIM READY on 127.0.0.1:{server.port}", flush=True)

    dt = args.dt_ms / 1000.0
    next_wall = time.perf_counter()
    steps = 0
    t_report = time.perf_counter()

    while True:
        now = time.perf_counter()
        while not server.stimuli_q.empty():
            cmd = server.stimuli_q.get()
            match cmd.get("cmd"):
                case "stim":
                    try:
                        ports.set_stimulus(
                            str(cmd["name"]),
                            float(cmd.get("value", 0.0)),
                            int(cmd.get("side", 0)),
                        )
                    except (KeyError, ValueError):
                        pass
                case "add_stim":
                    arena.add_stim(
                        int(cmd.get("id", 0)),
                        str(cmd.get("kind", "light")),
                        float(cmd.get("x", 0.0)),
                        float(cmd.get("z", 0.0)),
                    )
                case "remove_stim":
                    arena.remove_stim(int(cmd.get("id", 0)))
                case "pose":
                    arena.set_pose(
                        float(cmd.get("x", 0.0)),
                        float(cmd.get("z", 0.0)),
                        float(cmd.get("yaw", 0.0)),
                    )

        behind = now - next_wall
        if behind > 0.5:  # fell too far behind: resync instead of spiraling
            next_wall = now
        n_steps = min(int(behind / dt) + 1, 50)
        for _ in range(n_steps):
            arena.apply(ports)
            ports.step()
        steps += n_steps
        next_wall += n_steps * dt
        if n_steps * dt < dt:
            time.sleep(dt - n_steps * dt)

        if now - t_report >= 0.1:
            state = ports.readout(stim_drive=arena.drive)
            state["arena"] = arena.debug_info()
            state["sps"] = round(steps / (now - t_report))
            state["dt_ms"] = args.dt_ms
            state["kernel"] = brain.kernel_name
            server.set_state(state)
            steps = 0
            t_report = now


if __name__ == "__main__":
    main()
