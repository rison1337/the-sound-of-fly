"""Arena state: fly pose + placed stimuli, translated into port stimulation.

Stimulus intensity falls off with distance to the fly; the injection side
(left/right photoreceptor populations etc.) is chosen from which side of the
fly's heading the stimulus sits, so placing a light to the fly's left produces
a genuine left-side visual drive.
"""
import math


def clampf_min(v: float, lo: float = 0.12) -> float:
    return max(v, lo)

KIND_RANGE = {"light": 20.0, "odor": 16.0, "heat": 10.0, "sound": 16.0, "taste": 12.0}
KIND_STRENGTH = {"light": 1.0, "odor": 1.0, "heat": 1.0, "sound": 1.0, "taste": 1.0}
APPROACH = {"light", "odor", "taste"}


class Arena:
    def __init__(self) -> None:
        self.fly_x = 0.0
        self.fly_z = 0.0
        self.fly_yaw = 0.0
        self.stims: dict[int, tuple[str, float, float]] = {}
        # aggregated per-kind drive, rebuilt every apply(): kind -> {"L": x, "R": y}
        self.drive: dict[str, dict[str, float]] = {}

    def set_pose(self, x: float, z: float, yaw: float) -> None:
        self.fly_x = float(x)
        self.fly_z = float(z)
        self.fly_yaw = float(yaw)

    def add_stim(self, stim_id: int, kind: str, x: float, z: float) -> None:
        if kind in KIND_RANGE:
            self.stims[int(stim_id)] = (kind, float(x), float(z))

    def remove_stim(self, stim_id: int) -> None:
        self.stims.pop(int(stim_id), None)

    def debug_info(self) -> dict:
        return {
            "fly": [round(self.fly_x, 2), round(self.fly_z, 2), round(self.fly_yaw, 2)],
            "stims": [
                [sid, kind, round(x, 1), round(z, 1)]
                for sid, (kind, x, z) in self.stims.items()
            ],
        }

    def apply(self, ports) -> None:
        ports.clear_point_stimuli()
        self.drive = {}
        fx, fz, yaw = self.fly_x, self.fly_z, self.fly_yaw
        # Godot convention: forward = (cos yaw, -sin yaw) in xz, right = (sin yaw, cos yaw)
        rx, rz = math.sin(yaw), math.cos(yaw)
        for sid, (kind, x, z) in self.stims.items():
            rng = KIND_RANGE[kind]
            vx, vz = x - fx, z - fz
            dist = math.hypot(vx, vz)
            if dist > rng:
                continue
            intensity = KIND_STRENGTH[kind] * (1.0 - dist / rng)
            if dist > 1e-6:
                lat = (vx * rx + vz * rz) / dist
                side = 1 if lat > 0.2 else (-1 if lat < -0.2 else 0)
            else:
                side = 0
            ports.set_point_stimulus(str(sid), kind, intensity, side)
            # close to an appetitive source: ease the steering split and ease the
            # speed drive, so the fly settles at the source instead of orbiting it
            if kind in APPROACH:
                turn_eff = intensity * (0.3 + 0.7 * min(1.0, dist / 3.0))
                speed_eff = intensity * clampf_min(dist / 3.0)
                if dist < 1.5:
                    side = 0
            else:
                turn_eff = intensity
                speed_eff = intensity
            d = self.drive.setdefault(kind, {"L": 0.0, "R": 0.0, "S": 0.0})
            # side 0 (ahead) drives both halves equally
            d["L" if side <= 0 else "R"] += turn_eff
            if side == 0:
                d["R"] += turn_eff
            d["S"] += speed_eff
