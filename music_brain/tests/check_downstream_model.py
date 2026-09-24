"""Explicit full-model integration check; no model/data files are modified.

Compare intact and cut propagation using identical injection/background RNGs.
The cut network exists only in this diagnostic process, never in production.
"""
import json
from pathlib import Path
import sys

import numpy as np
from scipy.sparse import csr_matrix

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from music_brain.neural_audio import NeuralMusic
from music_brain.neural_frames import NeuralFrames


def main():
    model=NeuralMusic(gpu='off',seed=17)
    weights=model.brain.w
    print('ROUTES',json.dumps(model.readout_routes),flush=True)
    baseline_rng=model.brain.rng.bit_generator.state
    sensory_rng=model.rng.bit_generator.state
    def run(cut):
        brain=model.brain
        brain.w=csr_matrix(weights.shape,dtype=np.float32) if cut else weights
        brain.v.fill(0.); brain.spikes.fill(False); brain.rate_ema.fill(0.)
        brain.activity_ema=0.; brain.rng.bit_generator.state=baseline_rng
        model.rng.bit_generator.state=sensory_rng
        model.frames=NeuralFrames(brain.n); model.tick=0; model.fly.elapsed=0.
        result=[]
        for frame in range(80):
            active=frame>=20
            model.set_audio({'bands':np.ones(16)*(.65 if active else 0.),
                             'voices':np.ones(6)*(.8 if active else 0.), 'pitch':.5})
            for _ in range(10): model.step()
            assert not np.any(model.readout_mask & model.driven_mask)
            result.append([float(brain.rate_ema[c].mean()) for c in model.voice_cells])
            model.frames.encode(brain.rate_ema,model.tick)
        return np.array(result)
    intact=run(False); cut=run(True)
    report={'routes':model.readout_routes,'input_overlap':int(np.count_nonzero(model.readout_mask & model.driven_mask)),
            'intact_evoked_hz':intact[30:].mean(0).tolist(),'cut_evoked_hz':cut[30:].mean(0).tolist(),
            'intact_quiet_hz':intact[:20].mean(0).tolist()}
    path=ROOT/'music_brain/runtime/offline-qa/downstream_check.json'
    path.parent.mkdir(parents=True,exist_ok=True); path.write_text(json.dumps(report,indent=2))
    assert report['input_overlap']==0
    assert (intact[30:].mean(0)>cut[30:].mean(0)*2.+.03).all(), report
    print('DOWNSTREAM_MODEL_OK',json.dumps(report),flush=True)


if __name__=='__main__': main()
