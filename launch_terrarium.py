"""One local instance; this launcher owns and cleans up only its child processes."""
import json
import msvcrt
import os
import socket
import subprocess
import sys
import time
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LOGS = ROOT / "logs"


def main():
    LOGS.mkdir(exist_ok=True)
    lock = (LOGS / "terrarium.lock").open("a+b")
    lock.seek(0)
    if lock.read(1) == b"":
        lock.write(b"0")
        lock.flush()
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        return  # An existing launcher already owns the terrarium.
    python = ROOT / ".venv/Scripts/python.exe"
    godot = ROOT / ".tools/godot/Godot_v4.7.2-stable_win64.exe"
    graph = ROOT / "vendor/virtual-fly-lab/data/graph_malecns_v1.npz"
    for required in (python, godot, graph):
        if not required.exists():
            raise FileNotFoundError(f"Required local file missing: {required}")
    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    env["PYTHONUNBUFFERED"] = "1"
    backend = game = None
    with (LOGS / "brain.log").open("w", encoding="utf-8") as brain_log, (LOGS / "terrarium.log").open("w", encoding="utf-8") as game_log:
        try:
            backend = subprocess.Popen([str(python), str(ROOT / "droffel_sim.py")],
                                       cwd=ROOT, env=env, stdout=brain_log,
                                       stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            deadline = time.monotonic() + 120
            while "READY " not in (LOGS / "brain.log").read_text(encoding="utf-8", errors="replace"):
                if backend.poll() is not None:
                    raise RuntimeError("Neural service stopped. See logs/brain.log")
                if time.monotonic() > deadline:
                    raise TimeoutError("Neural service startup timed out. See logs/brain.log")
                time.sleep(0.25)
            game_args = [str(godot), "--path", str(ROOT / "terrarium")]
            if "--brain" in sys.argv:
                game_args += ["--", "--brain"]
            game = subprocess.Popen(game_args,
                                    cwd=ROOT, stdout=game_log, stderr=subprocess.STDOUT)
            (LOGS / "launch_state.json").write_text(json.dumps({"launcher_pid": os.getpid(), "backend_pid": backend.pid,
                "godot_pid": game.pid, "started": time.strftime("%Y-%m-%d %H:%M:%S")}, indent=2))
            while game.poll() is None:
                if backend.poll() is not None:
                    # Closing the window sends quit just before Godot exits.
                    try:
                        game.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        raise RuntimeError("Neural service stopped unexpectedly. See logs/brain.log")
                time.sleep(0.25)
        finally:
            # Gracefully stop the service, including when Godot crashes before
            # its close handler can send quit.
            if backend is not None and backend.poll() is None:
                try:
                    port = int((ROOT / "terrarium/data/sim_port.txt").read_text())
                    with socket.create_connection(("127.0.0.1", port), timeout=1) as connection:
                        connection.sendall(b'{"cmd":"quit"}\n')
                    backend.wait(timeout=3)
                except (OSError, ValueError, subprocess.TimeoutExpired):
                    pass
            for proc in (game, backend):
                if proc is not None and proc.poll() is None:
                    # Windows venv executables can be redirector parents; /T
                    # cleans up their children as well. Only our live PIDs.
                    subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
                    proc.wait(timeout=5)
            lock.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        LOGS.mkdir(exist_ok=True)
        (LOGS / "launcher_error.log").write_text(traceback.format_exc(), encoding="utf-8")
        import tkinter.messagebox
        tkinter.messagebox.showerror("Droffel — ошибка запуска", f"{exc}\n\nПодробности: {LOGS}")
