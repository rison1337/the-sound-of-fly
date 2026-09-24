"""Sensory input ports and motor readout, driven by dataset annotations.

Sensory groups: dataset `class` column (visual, olfactory, thermosensory,
mechanosensory, gustatory). Stimuli are lateralized: side=-1 injects into the
left population only, +1 right, 0 both.

Steering readout: type-matched L/R neuron pairs from the optomotor pathway
(HS/CH lobula-plate tangential cells, DNa/DNp descending neurons). Pairing by
cell type cancels the slow global-activity drift that swamps raw population
differentials. Forward drive: same pairs' combined rate, high-passed, so the
cruising tone cancels out and only stimulus-evoked increases move the fly.
"""
from collections import deque
from pathlib import Path

import numpy as np
import pandas as pd

from .arena import APPROACH

STIM_BASE_HZ = {"light": 150.0, "odor": 40.0, "heat": 80.0, "sound": 60.0, "taste": 40.0}
STEER_TYPES = ("H2", "HSS", "HSE", "CH", "DNa", "DNp", "HS")


class Ports:
    def __init__(self, brain, ann_path: Path, readout_hz_window: float = 500.0):
        self.brain = brain
        pos_of = {int(b): i for i, b in enumerate(brain.ids)}
        ann = pd.read_parquet(ann_path)
        ann = ann[ann["bodyId"].isin(pos_of)].copy()
        ann["idx"] = ann["bodyId"].map(pos_of)
        self.ann = ann

        self.groups: dict[str, np.ndarray] = {}
        for name, mask in {
            "light": ann["class"] == "visual",
            "odor": ann["class"] == "olfactory",
            "heat": ann["class"] == "thermosensory",
            "sound": ann["class"] == "mechanosensory",
            "taste": ann["class"] == "gustatory",
        }.items():
            self.groups[name] = ann.loc[mask, "idx"].to_numpy(dtype=np.int64)
        # per-side subsets for lateralized stimulation
        side_by_idx = ann.set_index("idx")["somaSide"]
        self.sides: dict[str, dict[str, np.ndarray]] = {}
        for name, idxs in self.groups.items():
            vals = side_by_idx.reindex(idxs).fillna("").to_numpy()
            self.sides[name] = {"L": idxs[vals == "L"], "R": idxs[vals == "R"]}

        # identified steering neurons (for telemetry display)
        dn = ann[ann["superclass"] == "descending_neuron"]
        self.motor: dict[str, np.ndarray] = {}
        for t in ("DNa01", "DNa02", "DNp20"):
            for side in ("L", "R"):
                sel = dn[(dn["type"] == t) & (dn["somaSide"] == side)]
                if len(sel):
                    self.motor[f"{t}_{side}"] = sel["idx"].to_numpy(dtype=np.int64)

        # type-matched L/R pairs for steering: optomotor pathway
        self.steer_pairs: dict[str, dict[str, np.ndarray]] = {}
        pool = ann[
            ann["superclass"].isin(["visual_projection", "descending_neuron"])
            & ann["somaSide"].isin(["L", "R"])
        ].copy()
        pool["type"] = pool["type"].fillna("")
        pool = pool[pool["type"].str.startswith(STEER_TYPES)]
        for t, grp in pool.groupby("type"):
            L = grp.loc[grp["somaSide"] == "L", "idx"].to_numpy(dtype=np.int64)
            R = grp.loc[grp["somaSide"] == "R", "idx"].to_numpy(dtype=np.int64)
            if L.size and R.size and L.size <= 60 and R.size <= 60:
                self.steer_pairs[t] = {"L": L, "R": R}

        # superclass codes for the heatmap
        self.superclasses = sorted(ann["superclass"].dropna().unique())
        sup_code = {s: i for i, s in enumerate(self.superclasses)}
        self.sup_idx = np.full(brain.n, -1, dtype=np.int32)
        rows = ann.dropna(subset=["superclass"])
        self.sup_idx[rows["idx"].to_numpy(dtype=np.int64)] = [
            sup_code[s] for s in rows["superclass"]
        ]
        self.type_by_idx = {
            int(i): (t if isinstance(t, str) else "")
            for i, t in zip(ann["idx"], ann["type"])
        }

        self.rng = np.random.default_rng(1)
        win = max(1, int(readout_hz_window / brain.dt_ms))
        self._window = win
        self._group_hist = {name: deque(maxlen=win) for name in self.groups}
        self._motor_hist = {k: deque(maxlen=win) for k in self.motor}
        self._stimuli: dict[str, tuple[float, int]] = {}
        # steering: per-side rate over the steer population, high-passed against
        # each side's own slow baseline EMA (drift cancels, response survives)
        steer_all_L = [i for p in self.steer_pairs.values() for i in p["L"]]
        steer_all_R = [i for p in self.steer_pairs.values() for i in p["R"]]
        self._steerL = np.array(steer_all_L, dtype=np.int64)
        self._steerR = np.array(steer_all_R, dtype=np.int64)
        self._steerL_hist: deque[int] = deque(maxlen=max(1, win // 2))
        self._steerR_hist: deque[int] = deque(maxlen=max(1, win // 2))
        self._emaL = 0.0
        self._emaR = 0.0
        self._fwd_slow = 0.0
        self._fwd_hist: deque[float] = deque(maxlen=win)

    def set_stimulus(self, name: str, value: float, side: int = 0) -> None:
        """Back-compat wrapper: stimulus id == group name."""
        self.set_point_stimulus(name, name, value, side)

    def set_point_stimulus(self, stim_id: str, kind: str, value: float, side: int = 0) -> None:
        if kind not in self.groups:
            raise KeyError(f"unknown stimulus kind '{kind}', have {sorted(self.groups)}")
        self._stimuli[stim_id] = (kind, float(np.clip(value, 0.0, 1.0)), int(np.clip(side, -1, 1)))

    def clear_point_stimuli(self) -> None:
        self._stimuli.clear()

    def _inject(self) -> np.ndarray:
        parts = []
        for stim_id, (kind, value, side) in self._stimuli.items():
            if value <= 0.0:
                continue
            subsets = self.sides[kind]
            chosen = (
                [subsets["L"], subsets["R"]]
                if side == 0
                else [subsets["L"] if side < 0 else subsets["R"]]
            )
            for sub in chosen:
                if sub.size == 0:
                    continue
                k = self.rng.poisson(
                    STIM_BASE_HZ[kind] * value * self.brain.dt_s * sub.size
                )
                # tiny groups (heat: 25 neurons, split per side) plus a Poisson
                # tail can exceed the population; sampling without replacement
                k = min(k, sub.size)
                if k:
                    parts.append(self.rng.choice(sub, size=k, replace=False))
        return np.concatenate(parts) if parts else np.empty(0, dtype=np.int64)

    def step(self) -> None:
        inject = self._inject()
        self.brain.step(inject)
        spikes = self.brain.spikes
        for name in self.groups:
            self._group_hist[name].append(int(spikes[self.groups[name]].sum()))
        for key, idxs in self.motor.items():
            self._motor_hist[key].append(int(spikes[idxs].sum()))
        # per-step steering accumulators (see readout)
        c_l = int(spikes[self._steerL].sum())
        c_r = int(spikes[self._steerR].sum())
        self._steerL_hist.append(c_l)
        self._steerR_hist.append(c_r)
        hz_l = self._win_hz(self._steerL_hist, self._steerL.size)
        hz_r = self._win_hz(self._steerR_hist, self._steerR.size)
        a = 0.002  # ~1 s baseline EMA at dt=2 ms
        self._emaL += a * (hz_l - self._emaL)
        self._emaR += a * (hz_r - self._emaR)
        fwd = 0.5 * (hz_l + hz_r)
        self._fwd_hist.append(fwd)
        self._fwd_slow = 0.9995 * self._fwd_slow + 0.0005 * fwd

    def _win_hz(self, hist: deque, size: int) -> float:
        if size == 0 or not hist:
            return 0.0
        return 1000.0 / self.brain.dt_ms * (sum(hist) / len(hist)) / size

    def _hist_hz(self, hist: deque, size: int) -> float:
        if size == 0 or not hist:
            return 0.0
        return 1000.0 / self.brain.dt_ms * (sum(hist) / len(hist)) / size

    def readout(self, stim_drive: dict | None = None) -> dict:
        """stim_drive: arena's per-kind {"L","R"} intensity sums. Blended into the
        motor output as an engineered reflex arc (approach light/odor/taste, avoid
        heat, freeze at sound) on top of the brain's own steering."""
        group_hz = {
            name: self._hist_hz(self._group_hist[name], int(self.groups[name].size))
            for name in self.groups
        }
        motor_hz = {
            key: round(self._hist_hz(self._motor_hist[key], int(self.motor[key].size)), 2)
            for key in self.motor
        }

        # steering: change-from-own-baseline differential between sides
        hz_l = self._win_hz(self._steerL_hist, self._steerL.size)
        hz_r = self._win_hz(self._steerR_hist, self._steerR.size)
        d_l = hz_l - self._emaL
        d_r = hz_r - self._emaR
        turn = (d_r - d_l) / (abs(self._emaL) + abs(self._emaR) + 1.0)
        forward = float(np.mean(self._fwd_hist)) if self._fwd_hist else 0.0

        # blend the brain's own steering with the reflex drive from placed stimuli
        brain_turn = turn
        brain_speed = float(np.clip((forward - self._fwd_slow) / 25.0, 0.0, 1.0))
        turn_drive = 0.0
        speed_drive = 0.0
        freeze = 0.0
        if stim_drive:
            for kind, d in stim_drive.items():
                total = d.get("L", 0.0) + d.get("R", 0.0)
                if total <= 0.02 and d.get("S", 0.0) <= 0.02:
                    continue
                net = (d.get("R", 0.0) - d.get("L", 0.0)) / (total + 0.15)
                if kind in APPROACH:
                    turn_drive += net
                    speed_drive += min(0.9, d.get("S", 0.0) * 1.4)
                elif kind == "heat":
                    turn_drive -= net  # steer away
                    speed_drive += min(0.9, total * 1.6)  # and escape faster
                elif kind == "sound":
                    freeze = min(0.85, freeze + d.get("S", total) * 1.2)
        turn = 0.45 * brain_turn + turn_drive
        speed = (0.12 + brain_speed + speed_drive) * (1.0 - freeze)

        # superclass rates for the heatmap (EMA-smoothed instantaneous)
        spikes = self.brain.spikes
        known = self.sup_idx >= 0
        counts = np.bincount(self.sup_idx[spikes & known], minlength=len(self.superclasses))
        sizes = np.bincount(self.sup_idx[known], minlength=len(self.superclasses))
        if not hasattr(self, "_rates_ema"):
            self._rates_ema = {name: 0.0 for name in self.superclasses}
        for i, name in enumerate(self.superclasses):
            if sizes[i]:
                inst = 1000.0 / self.brain.dt_ms * counts[i] / sizes[i]
                self._rates_ema[name] = 0.9 * self._rates_ema[name] + 0.1 * inst
        rates = {k: round(v, 2) for k, v in self._rates_ema.items()}

        ann_idx = self.ann["idx"].to_numpy(dtype=np.int64)
        rates_n = self.brain.rate_ema[ann_idx]
        top_pos = np.argpartition(rates_n, -8)[-8:]
        top_pos = top_pos[np.argsort(rates_n[top_pos])[::-1]]
        top = []
        for pos in top_pos:
            idx = int(ann_idx[pos])
            if self.brain.rate_ema[idx] < 5.0:
                continue
            top.append(
                {
                    "id": int(self.brain.ids[idx]),
                    "type": self.type_by_idx.get(idx, ""),
                    "hz": round(float(self.brain.rate_ema[idx]), 1),
                }
            )

        # x-ray cloud: graph row indices + integer Hz for every neuron above 6 Hz,
        # capped at 3000 entries (Godot colors those instances of the point cloud)
        hot = np.flatnonzero(self.brain.rate_ema > 6.0)
        if hot.size > 3000:
            hot = hot[np.argpartition(self.brain.rate_ema[hot], -3000)[-3000:]]
        order = np.argsort(self.brain.rate_ema[hot])[::-1]
        cloud = [[int(i), int(round(float(self.brain.rate_ema[i])))] for i in hot[order]]

        return {
            "turn": float(np.clip(turn, -1.0, 1.0)),
            "speed": float(np.clip(speed, 0.0, 1.0)),
            "brain_turn": float(np.clip(brain_turn * 5.0, -1.0, 1.0)),
            "hz_global": round(
                float(self.brain.spikes.mean())
                * self.brain.n
                * 1000.0
                / self.brain.dt_ms
            ),
            "group_hz": {k: round(v, 2) for k, v in group_hz.items()},
            "motor_hz": motor_hz,
            "steer_pairs": len(self.steer_pairs),
            "rates": rates,
            "top": top,
            "cloud": cloud,
            "active": round(self.brain.activity_fraction() * 100, 2),
        }
