"""Montage cues extracted from model readouts, never from the raw audio FFT."""
from collections import deque
import math
import numpy as np


class NeuralEvents:
    def __init__(self):
        self.previous = np.zeros(16)
        self.history = deque(maxlen=90)
        self.clock = 0.
        self.last_onset = -10.
        self.event_id = 0
        self.strength = 0.
        self.last_event = {"id": 0, "kind": "idle", "strength": 0.}
        self.slow_energy = 0.

    def update(self, neural_bands, elapsed):
        values = np.clip(np.nan_to_num(np.asarray(neural_bands, float)), 0., 1.)
        if values.shape != (16,):
            raise ValueError('Expected sixteen neural population readouts')
        if elapsed <= 0:
            return self.state(values)
        self.clock += elapsed
        delta = np.maximum(values-self.previous, 0.)
        flux = float(np.sqrt(np.mean(delta**2)))
        baseline = float(np.median(self.history)) if self.history else .005
        threshold = max(.012, baseline*1.65)
        energy = float(values.mean())
        self.slow_energy += (energy-self.slow_energy)*(1.-math.exp(-elapsed/2.5))
        self.strength *= math.exp(-elapsed/.12)
        if energy > .055 and flux > threshold and self.clock-self.last_onset > .11:
            low, mid, high = [float(a.mean()) for a in (delta[:5], delta[5:11], delta[11:])]
            kind = ('impact', 'shape', 'detail')[int(np.argmax([low*1.12, mid, high]))]
            if energy-self.slow_energy > .16 and flux > .04:
                kind = 'drop'
            self.event_id += 1
            self.last_onset = self.clock
            self.strength = float(np.clip(flux*6.+.2, .25, 1.))
            self.last_event = {"id": self.event_id, "kind": kind, "strength": self.strength}
        self.history.append(flux)
        self.previous = values.copy()
        return self.state(values)

    def state(self, values):
        return {"event": self.last_event.copy(), "hit": self.strength,
                "neural_bands": values.tolist(), "drive": float(values.mean()),
                "slow_drive": self.slow_energy}
