"""End-to-end protocol test: connect to a running sim server (python -m sim),
verify state stream, inject a stimulus, read the response.

Usage: python tools/test_server.py
"""
import json
import socket
import time


def main() -> None:
    sock = socket.create_connection(("127.0.0.1", 9876))
    sock.settimeout(5.0)
    f = sock.makefile("r", encoding="utf-8", newline="\n")

    def read_state() -> dict:
        while True:
            line = f.readline()
            if not line:
                raise RuntimeError("server closed")
            return json.loads(line)

    s = read_state()
    print(
        f"state: active={s['active']}% turn={s['turn']:+.3f} speed={s['speed']:.3f} "
        f"sps={s['sps']} dt={s['dt_ms']}"
    )
    sock.sendall(
        (json.dumps({"cmd": "stim", "name": "light", "value": 0.9, "side": 1}) + "\n").encode()
    )
    time.sleep(2.0)
    turns = [read_state()["turn"] for _ in range(10)]
    print("light-R turn samples:", [f"{t:+.2f}" for t in turns])
    sock.sendall((json.dumps({"cmd": "stim", "name": "light", "value": 0.0}) + "\n").encode())
    sock.close()
    print("CLIENT TEST OK")


if __name__ == "__main__":
    main()
