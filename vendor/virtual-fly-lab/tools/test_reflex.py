"""Probe: connect to the sim server, place stimuli, read the LATEST state.

Usage: python tools/test_reflex.py
"""
import json
import socket
import time


def main() -> None:
    sock = socket.create_connection(("127.0.0.1", 9876))
    sock.settimeout(0.3)
    buf = b""

    def read_latest():
        """Drain the socket for up to 0.6 s and return the last complete state."""
        nonlocal buf
        deadline = time.time() + 0.6
        latest = None
        while time.time() < deadline:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                latest = json.loads(line)
        return latest

    def send(o):
        sock.sendall((json.dumps(o) + "\n").encode())

    send({"cmd": "pose", "x": 0, "z": 0, "yaw": 0})
    time.sleep(0.5)
    read_latest()

    send({"cmd": "add_stim", "id": 99, "kind": "light", "x": 8, "z": 4})
    time.sleep(2)
    s = read_latest()
    print("light right :", "turn=%+.2f speed=%.2f" % (s["turn"], s["speed"]))

    send({"cmd": "add_stim", "id": 98, "kind": "heat", "x": 8, "z": -4})
    time.sleep(2)
    s = read_latest()
    print("+ heat left :", "turn=%+.2f speed=%.2f" % (s["turn"], s["speed"]))

    send({"cmd": "remove_stim", "id": 99})
    send({"cmd": "remove_stim", "id": 98})
    time.sleep(2)
    s = read_latest()
    print("clean       :", "turn=%+.2f speed=%.2f" % (s["turn"], s["speed"]))
    sock.close()


if __name__ == "__main__":
    main()
