"""Bootstrap: download the MaleCNS v1.0 connectome data and build everything
the sim needs. Run once:

    python tools/setup_data.py [--dir D:\\fly-data]

Downloads ~1.1 GB from the public Janelia bucket (no login needed), then builds:
    data/graph_malecns_v1.npz            CSR adjacency for the sim
    data/annotations_malecns_v1.parquet  id -> type/class/superclass
    data/soma_positions_f32.bin (+ .npz) positions for the brain view
    world/data/soma_positions_f32.bin    copy for Godot
"""
import argparse
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://storage.googleapis.com/flyem-male-cns/v1.0/connectome-data/flat-connectome"
FILES = {
    "body-annotations-male-cns-v1.0-minconf-0.5.feather": 15 * 2**20,
    "body-neurotransmitters-male-cns-v1.0.feather": 43 * 2**20,
    "connectome-weights-male-cns-v1.0-minconf-0.5.feather": 1051 * 2**20,
}


def download(url: str, dst: Path) -> None:
    part = dst.with_suffix(dst.suffix + ".part")
    print(f"downloading {dst.name} ...", flush=True)
    done = 0

    def hook(count: int, block: int, total: int) -> None:
        nonlocal done
        done += block
        if done - hook.last >= 50 * 2**20:
            hook.last = done
            print(f"  {done / 2**20:.0f} MB", flush=True)

    hook.last = 0
    urllib.request.urlretrieve(url, part, reporthook=hook)
    part.replace(dst)
    print(f"  done: {dst.name}", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default=r"D:\fly-data", help="raw dataset directory")
    args = ap.parse_args()
    data_dir = Path(args.dir)
    data_dir.mkdir(parents=True, exist_ok=True)

    for name, _size in FILES.items():
        dst = data_dir / name
        if dst.exists() and dst.stat().st_size > 0.9 * FILES[name]:
            print(f"already present: {name}")
            continue
        download(f"{BASE}/{name}", dst)

    env = os.environ.copy()
    env["FLY_DATA_DIR"] = str(data_dir)
    print("building graph ...", flush=True)
    subprocess.run([sys.executable, ROOT / "tools" / "build_graph.py"], env=env, check=True)
    print("extracting soma positions ...", flush=True)
    subprocess.run([sys.executable, ROOT / "tools" / "extract_soma.py"], env=env, check=True)

    world_data = ROOT / "world" / "data"
    world_data.mkdir(exist_ok=True)
    shutil.copy2(ROOT / "data" / "soma_positions_f32.bin", world_data / "soma_positions_f32.bin")

    print("\nSETUP COMPLETE. Now run:")
    print("  terminal 1:  python -m sim")
    print("  terminal 2:  Godot with this project's world/ folder")


if __name__ == "__main__":
    main()
