"""Legacy causal analyser used only by reference-analysis diagnostics."""
from collections import deque
import math

import numpy as np


class AudioAnalysis:
    """Stereo-power FFT; opposite-phase stereo must not cancel the input."""
    def __init__(self, size=4096, bands=16):
        self.size = size
        self.count = bands
        self.window = np.hanning(size).astype(np.float32)
        self.edges = np.geomspace(45., 16000., bands + 1)
        self.smooth = np.zeros(bands, dtype=np.float32)
        self.onset_baseline = .004
        self.onset_clock = 0.
        self.last_onset = -1.
        self.onset_id = 0
        self.timing_id = 0
        self.timing_history = deque(maxlen=48)
        self.band_flux_baseline = np.full(3,.008)
        self.last_band_event = np.full(3,-1.)

    def analyze(self, samples, rate, elapsed=.04, gain=1.):
        x = np.asarray(samples, dtype=np.float32)
        if x.ndim == 1:
            x = x[:, None]
        x = np.nan_to_num(x, nan=0., posinf=0., neginf=0.)
        x = np.clip(x[-self.size:], -1., 1.)
        rms = float(np.sqrt(np.mean(x*x))) if x.size else 0.
        stereo = np.sqrt(np.mean(x*x, axis=0)) if x.size else np.zeros(2)
        if len(x) < self.size:
            x = np.pad(x, ((self.size-len(x), 0), (0, 0)))
        power = np.mean(np.abs(np.fft.rfft(x*self.window[:, None], axis=0))**2, axis=1)
        power *= 4./float(self.window.sum()**2)
        freqs = np.fft.rfftfreq(self.size, 1./rate)
        bands = []
        for low, high in zip(self.edges[:-1], self.edges[1:]):
            mask = (freqs >= low) & (freqs < high)
            value = float(np.sqrt(power[mask].sum())) if mask.any() else 0.
            # Bounded logarithmic mapping, with an absolute silence/noise floor.
            db = 20.*math.log10(max(1e-8, value*gain))
            bands.append(np.clip((db+64.)/49., 0., 1.))
        target = np.asarray(bands, dtype=np.float32)
        if rms*gain < .00025:
            target[:] = 0.
        # This clock controls cut timing only; it does not control neural imagery.
        self.onset_clock += elapsed
        flux = float(np.maximum(target-self.smooth,0.).mean())
        cut = 0.
        if rms*gain > .001 and flux > max(.018,self.onset_baseline*1.8) and self.onset_clock-self.last_onset>.095:
            self.last_onset=self.onset_clock
            self.onset_id+=1
            cut=float(np.clip(flux*5.,.2,1.))
        self.onset_baseline += (flux-self.onset_baseline)*(1.-math.exp(-elapsed/1.5))
        # Independent clocks catch percussion and fills that a single averaged
        # onset misses. Only IDs/timestamps leave the service for visual timing.
        rises=np.maximum(target-self.smooth,0.)
        for group,(lo,hi) in enumerate(((0,5),(5,11),(11,16))):
            local_flux=float(rises[lo:hi].mean())
            threshold=max(.025,float(self.band_flux_baseline[group])*1.9)
            if rms*gain>.001 and local_flux>threshold and self.onset_clock-self.last_band_event[group]>.055:
                self.last_band_event[group]=self.onset_clock
                self.timing_id+=1
                self.timing_history.append((self.timing_id,self.onset_clock))
            self.band_flux_baseline[group]+=(local_flux-self.band_flux_baseline[group])*(1.-math.exp(-elapsed/1.))
        tau = np.where(target > self.smooth, .012, .065)
        self.smooth += (target-self.smooth)*(1.-np.exp(-max(0., elapsed)/tau))
        self.smooth[self.smooth < .0001] = 0.
        dbfs = 20.*math.log10(max(1e-6, rms))
        pan = float((stereo[-1]-stereo[0])/max(1e-6, stereo.sum())) if stereo.size > 1 else 0.
        return {"bands": self.smooth.copy(), "rms": rms, "dbfs": dbfs,
                "timing_events": [{"id":i,"age_ms":round((self.onset_clock-born)*1000.,2)}
                                  for i,born in self.timing_history if self.onset_clock-born<.3],
                "cut_id": self.onset_id, "cut_strength": cut,
                "pan": pan, "level": float(np.clip((dbfs+64.)/49., 0., 1.))}
