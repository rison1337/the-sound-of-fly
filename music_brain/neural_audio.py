"""Artificial sound encoding into annotated cells of the existing MaleCNS model.

Frequency assignments are an engineering mapping, not biological tuning data.
Visual outputs contain simulated firing rates and individual spike events.
"""
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from droffel_sim import FlyNervousSystem
try:
    from .neural_events import NeuralEvents
    from .neural_frames import NeuralFrames
    from .downstream import select_downstream
except ImportError:
    from neural_events import NeuralEvents
    from neural_frames import NeuralFrames
    from downstream import select_downstream


class NeuralMusic:
    def __init__(self, gpu="auto", seed=17):
        self.seed = seed
        # The Isaac configuration's norm=5 can sustain a reverberating state after
        # sound ends. This music-specific gain returns to its baseline in silence.
        self.fly = FlyNervousSystem(gpu=gpu, seed=seed, norm=3.0, profile="interactive")
        self.brain = self.fly.brain
        # Low spontaneous activity leaves the audio-evoked response legible.
        self.brain.background_hz = .03
        self.rng = np.random.default_rng(seed+1)
        self.encoding = "multisensory"
        self.auditory = self.fly.groups["vibration"]
        self.sources = [self.fly.groups[key] for key in
                        ("vibration", "touch", "odor_a", "odor_b", "light_L", "light_R")]
        self.band_assignment = [np.arange(len(group)) % 16 for group in self.sources]
        self.band_cells = {}
        for mode in ('multisensory', 'auditory'):
            self.band_cells[mode] = [np.concatenate([
                group[(assignment+i*2) % 16 == band]
                for i, (group, assignment) in enumerate(zip(self.sources, self.band_assignment))
                if mode != 'auditory' or i == 0]) for band in range(16)]
        self.editor = NeuralEvents()
        self.frames = NeuralFrames(self.brain.n)
        self.tick = 0
        self.drive_idx = np.empty(0, np.int64)
        self.drive_probability = np.empty(0, np.float32)
        self.driven_mask = np.zeros(self.brain.n, bool)
        self.controls = np.zeros(8, np.float32)
        self.last_levels = np.zeros(8, np.float32)
        self.phase = 0.
        self.neural_pulse = 0.
        self.propagated_spikes = 0
        positions = np.fromfile(ROOT / "terrarium/data/soma_positions_f32.bin", np.float32).reshape(-1, 3)
        vnc = np.fromfile(ROOT / "terrarium/data/soma_is_vnc.bin", np.uint8).astype(bool)
        self.visible = np.any(positions != 0, axis=1) & ~vnc
        # Anatomical spatial readouts, each normalized by its actual cell count.
        cuts = np.quantile(positions[self.visible, 0], [0., .25, .5, .75, 1.])
        mid_y = float(np.median(positions[self.visible, 1]))
        self.regions = []
        for half in range(2):
            for sector in range(4):
                mask = self.visible & (positions[:, 0] >= cuts[sector])
                mask &= positions[:, 0] <= cuts[sector+1] if sector == 3 else positions[:, 0] < cuts[sector+1]
                mask &= (positions[:, 1] >= mid_y) if half else (positions[:, 1] < mid_y)
                self.regions.append(np.flatnonzero(mask))
        valid = np.any(positions != 0, axis=1)
        lower, upper = np.quantile(positions[valid], [.01,.99], axis=0)
        bins = np.clip((positions-lower)/np.maximum(upper-lower,.001)*[8,8,4],0,[7,7,3]).astype(int)
        self.ensemble_ids = bins[:,0]+8*bins[:,1]+64*bins[:,2]
        # Missing-coordinate cells stay represented, in documented abstract bins.
        self.ensemble_ids[~valid] = np.flatnonzero(~valid)%256
        self.ensemble_sizes = np.maximum(1,np.bincount(self.ensemble_ids,minlength=256))
        # Disjoint synthetic voice inputs. These are engineering assignments,
        # not instrument-tuned biological neurons; synaptic weights stay fixed.
        self.voice_inputs = np.unique(np.concatenate(self.sources))
        self.voice_assignment = np.arange(len(self.voice_inputs)) % 6
        self.voice_bins = (np.arange(len(self.voice_inputs)) // 6) % 16
        self.voice_cells, self.voice_contour_cells, self.readout_routes = select_downstream(
            self.brain.w, self.voice_inputs, self.voice_assignment, self.voice_bins)
        self.readout_mask = np.zeros(self.brain.n, bool)
        self.readout_mask[np.concatenate(self.voice_cells)] = True
        self.voice_calibration = [{'noise_floor_hz':.04,'rate_scale_hz':.7,'spike_scale_hz':2.4} for _ in range(6)]
        self.update_voice_owners()

    def update_voice_owners(self):
        self.voice_owners = []
        for cells in self.voice_cells:
            weights = np.bincount(self.ensemble_ids[cells], minlength=256)
            order = np.argsort(weights)[::-1]
            self.voice_owners.append(next(int(i) for i in order if int(i) not in self.voice_owners))

    def reset_state(self):
        """Reset dynamic state after fixed probes. Connectivity is untouched."""
        self.brain.v.fill(0.); self.brain.spikes.fill(False); self.brain.rate_ema.fill(0.)
        self.brain.activity_ema=0.; self.brain.rng=np.random.default_rng(self.seed)
        self.rng=np.random.default_rng(self.seed+1)
        self.frames=NeuralFrames(self.brain.n); self.tick=0; self.fly.elapsed=0.
        self.controls.fill(0.); self.last_levels.fill(0.); self.phase=0.; self.neural_pulse=0.
        self.propagated_spikes=0; self.editor=NeuralEvents()

    def set_audio(self, features, strength=1., encoding="multisensory"):
        bands = np.clip(np.asarray(features["bands"], dtype=np.float32), 0., 1.)
        self.encoding = encoding
        if 'voices' in features:
            voices = np.clip(np.asarray(features['voices']), 0., 1.)
            level = voices[self.voice_assignment]
            pitches = np.asarray(features.get('voice_pitch', np.full(6,features.get('pitch',.5))))
            position = np.clip(pitches[self.voice_assignment], 0., 1.)*15.
            # Pitch becomes a moving sensory excitation, not a shader knob.
            tuning = .30+.70*np.exp(-((self.voice_bins-position)/3.)**2)
            tonal = np.isin(self.voice_assignment, [1, 4, 5])
            role_bands=np.asarray(features.get('voice_bands',np.tile(bands,(6,1))))
            activity = level*np.where(tonal, tuning, .45+.55*role_bands[self.voice_assignment,self.voice_bins])
            self.drive_idx = self.voice_inputs
            self.drive_probability = -np.expm1(-220.*activity*strength*self.brain.dt_s)
            self.driven_mask[:] = False
            self.driven_mask[self.drive_idx] = True
            self._check_readout_isolation()
            return
        ids, probabilities = [], []
        for i, (group, assignment) in enumerate(zip(self.sources, self.band_assignment)):
            if encoding == "auditory" and i != 0:
                continue
            if not len(group):
                continue
            # An explicit synthetic interface: spectrum -> Poisson sensory events.
            # Multisensory also stimulates vision, touch and smell annotation groups.
            activity = bands[(assignment+i*2) % 16]
            hz = (260. if i == 0 else 160.)*activity*strength
            ids.append(group)
            probabilities.append(-np.expm1(-hz*self.brain.dt_s))
        self.drive_idx = np.concatenate(ids) if ids else np.empty(0, np.int64)
        self.drive_probability = np.concatenate(probabilities) if ids else np.empty(0, np.float32)
        self.driven_mask[:] = False
        self.driven_mask[self.drive_idx] = True
        self._check_readout_isolation()

    def _check_readout_isolation(self):
        if np.any(self.readout_mask & self.driven_mask):
            raise RuntimeError('Directly stimulated cells reached a downstream voice readout')

    def step(self):
        injected = self.drive_idx[self.rng.random(len(self.drive_idx)) < self.drive_probability]
        self.brain.step(injected)
        self.tick += 1
        self.frames.observe(self.brain.spikes, self.tick)
        self.fly.elapsed += self.brain.dt_s
        self.propagated_spikes += int(np.count_nonzero(self.brain.spikes & ~self.driven_mask))

    def readout(self, elapsed=.05):
        self._check_readout_isolation()
        rates = self.brain.rate_ema
        # Each control is a different neural population, not a raw FFT band.
        # Mean plus responding-cell fraction makes sparse cascades visible.
        raw = np.array([float(rates[group].mean()) for group in self.regions], dtype=np.float32)
        response = np.array([float(np.mean(rates[group] > 3.)) for group in self.regions], dtype=np.float32)
        levels = np.clip(1.-np.exp(-np.maximum(raw-.04,0.)/.9)+np.maximum(response-.004,0.)*2., 0., 1.)
        self.neural_pulse = max(float(np.maximum(levels-self.last_levels, 0.).mean()*7.),
                                self.neural_pulse*np.exp(-elapsed/.18))
        self.last_levels = levels
        self.controls += (levels-self.controls)*(1.-np.exp(-elapsed/.09))
        self.phase += elapsed*(.025+float(self.controls.mean())*3.2+self.neural_pulse*1.4)
        # Fast cues come from actual firing rates of the stimulated sensory cells;
        # recurrent anatomical populations above determine the slower visual form.
        neural_bands = np.array([float(rates[idx].mean()) if len(idx) else 0.
                                 for idx in self.band_cells[self.encoding]])
        neural_bands = np.clip((neural_bands-.2)/125., 0., 1.)
        cues = self.editor.update(neural_bands, elapsed)
        ensemble_rates = np.bincount(self.ensemble_ids, weights=rates, minlength=256)/self.ensemble_sizes
        ensemble_spikes = np.bincount(self.ensemble_ids, weights=self.frames.counts, minlength=256)
        voice_states = []
        for v, cells in enumerate(self.voice_cells):
            response = np.array([rates[c].mean() if len(c) else 0.
                                 for c in self.voice_contour_cells[v]])
            contour = float(np.dot(response, np.linspace(0., 1., 4))/max(.01, response.sum()))
            hz = float(rates[cells].mean()) if len(cells) else 0.
            instant = float(self.frames.counts[cells].mean())/max(.002, elapsed) if len(cells) else 0.
            # A display transfer for sparse downstream rates. No audio amplitude
            # or sensory rate is mixed back into this recurrent readout.
            calibration=self.voice_calibration[v]
            voice_states.append([float(-np.expm1(-max(0., hz-calibration['noise_floor_hz'])/calibration['rate_scale_hz'])),
                                 float(-np.expm1(-max(0., instant-calibration['noise_floor_hz'])/calibration['spike_scale_hz'])), contour,
                                 float(np.mean(rates[cells] > 3.)) if len(cells) else 0.])
        return {**cues, "neural_voices": voice_states, "voice_owners": self.voice_owners,
                "voice_readout": "connectome_downstream_2_3_hop", "readout_input_overlap": 0,
                "neural_bands": np.round(neural_bands,5).tolist(),
                "ensembles": np.round(ensemble_rates,4).tolist(),
                "ensemble_sizes": self.ensemble_sizes.tolist(),
                "ensemble_spikes": ensemble_spikes.astype(int).tolist(),
                "controls": self.controls.tolist(), "pulse": min(1., self.neural_pulse),
                "phase": self.phase, "raw_rates": raw.tolist(),
                "responding": int(np.count_nonzero(rates > 2.)),
                "mean_hz": float(rates.mean()), "neurons": self.brain.n,
                "connections": self.brain.w.nnz, "sim_time": self.fly.elapsed,
                "kernel": self.brain.kernel_name,
                "propagated_spikes": self.propagated_spikes}
