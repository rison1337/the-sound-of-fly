"""Audio file -> musical score -> complete fixed-brain simulation -> cache."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time

import numpy as np
from score import decode, analyze, features_at
from timeline import TimelineWriter
from sync_analysis import build_sync_report

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
VERSION = 4


def progress(stage, value, **extra):
    print(json.dumps({'stage': stage, 'progress': round(value, 4), **extra}), flush=True)


def prepare(source, start=0., duration=0., separation='demucs', force=False):
    source = Path(source).resolve()
    if not source.is_file(): raise FileNotFoundError(source)
    if start<0 or duration<0: raise ValueError('Start and duration must be nonnegative')
    # Include all computation sources, not only a manually incremented version.
    digest = hashlib.sha256()
    with source.open('rb') as stream:
        for chunk in iter(lambda: stream.read(2**20), b''): digest.update(chunk)
    for name in ('prepare.py','score.py','neural_audio.py','neural_frames.py','separate.py','downstream.py','calibration.py','sync_analysis.py'):
        digest.update((HERE/name).read_bytes())
    digest.update(f'{VERSION}:{start}:{duration}:{separation}'.encode())
    directory = HERE/'runtime/projects'/digest.hexdigest()[:20]
    directory.mkdir(parents=True, exist_ok=True)
    manifest = directory/'project.json'
    if manifest.exists() and not force:
        progress('ready', 1., project=str(manifest), reused=True)
        return manifest
    manifest.unlink(missing_ok=True)
    progress('decode', .01)
    pcm, rate = decode(source, directory/'audio.wav', start, duration)
    stems = None
    if separation == 'demucs':
        interpreter = ROOT/'.tools/music-separator/Scripts/python.exe'
        if not interpreter.exists():
            raise RuntimeError('Separator missing. Run SETUP_SEPARATOR.cmd, or select Fast analysis.')
        progress('separate instruments', .03)
        stems = directory/'stems'
        subprocess.run([str(interpreter), str(HERE/'separate.py'), str(directory/'audio.wav'), str(stems)],
                       check=True, stdout=sys.stdout, stderr=sys.stderr, creationflags=0x08000000)
    progress('musical score', .16)
    score = analyze(pcm, rate, stems)
    np.savez_compressed(directory/'score.npz', times=score['times'], bands=score['bands'],
                        voices=score['voices'], pitch=score['pitch'], brightness=score['brightness'])
    score_metadata = {k: score[k] for k in ('events','boundaries','phrases','duration','source_kind','beat_seconds','beat_confidence')}
    (directory/'score.json').write_text(json.dumps(score_metadata, separators=(',', ':')), encoding='utf-8')
    del pcm
    progress('load fixed brain', .2)
    from neural_audio import NeuralMusic
    from calibration import calibrate
    brain = NeuralMusic(gpu='auto', seed=17)
    progress('calibrate downstream voices', .205)
    calibration = calibrate(brain, directory/'calibration.json')
    (directory/'readout_routes.json').write_text(json.dumps({
        'kind':'connectome_downstream_calibrated_2_3_hop', 'routes':brain.readout_routes,
        'input_cells':brain.voice_inputs.tolist(),
        'readout_cells':[c.tolist() for c in brain.voice_cells],
        'contour_cells':[[c.tolist() for c in voice] for voice in brain.voice_contour_cells]
    }, indent=2), encoding='utf-8')
    ensemble_map = np.zeros(brain.frames.WIDTH*brain.frames.height, np.uint8)
    ensemble_map[:brain.brain.n] = brain.ensemble_ids
    (directory/'ensemble_map_u8.bin').write_bytes(ensemble_map.tobytes())
    writer = TimelineWriter(directory)
    voice_history = []
    frames = math.ceil(score['duration']/.02)+1
    # Stimulate each voice early by its measured peak delay. The downstream
    # response therefore reaches its visual articulation near the source event.
    advances = np.asarray([float(row['peak_ms'])/1000. for row in calibration], np.float32)
    (directory/'voice_timing.json').write_text(json.dumps({
        'advances_s': advances.tolist(), 'calibration': calibration,
        'meaning':'positive lookahead: at model time t inject source at t+advance'
    }, indent=2), encoding='utf-8')
    # Integrate the opening lookahead from silence so the first attack is not
    # discarded. Advance input at the actual 2ms model clock, not 20ms blocks.
    model_step=brain.brain.dt_s
    preroll=math.ceil((float(advances.max())+.10)/model_step)
    for step in range(-preroll,0):
        brain.set_audio(features_at(score, step*model_step, advances))
        brain.step()
    brain.frames.encode(brain.brain.rate_ema, brain.tick)
    begun = time.monotonic()
    try:
        for index in range(frames):
            t = index*.02
            if index:
                for step in range(round((t-.02)/model_step),round(t/model_step)):
                    brain.set_audio(features_at(score, step*model_step, advances))
                    brain.step()
            state = brain.readout(.02)
            voice_history.append(state.get('neural_voices', []))
            # Recording time is the audio timeline; retain model time separately.
            state.update(seq=index, sim_time=t, model_time=brain.fly.elapsed, paused=False,
                         frame_width=brain.frames.WIDTH, frame_height=brain.frames.height,
                         input_db=-120., input_level=0., audio={'device': source.name, 'error': ''})
            writer.append(state, brain.frames.encode(brain.brain.rate_ema, brain.tick))
            if index%50 == 0:
                progress('simulate fixed brain', .22+.77*index/frames,
                         seconds=t, duration=score['duration'], elapsed=time.monotonic()-begun)
    finally:
        writer.close()
    sync_report = build_sync_report(score, voice_history)
    (directory/'sync_report.json').write_text(json.dumps(sync_report, separators=(',', ':')), encoding='utf-8')
    score_metadata['events']=score['events']
    (directory/'score.json').write_text(json.dumps(score_metadata,separators=(',', ':')),encoding='utf-8')
    result = {'version': VERSION, 'source_name': source.name, 'source_start': start,
              'duration': score['duration'], 'sample_rate': rate, 'neural_hz': 50,
              'neurons': brain.brain.n, 'ensembles': 256, 'frames': frames,
              'separation': score['source_kind'], 'neural_preroll_ms': 0,
              'weights': 'fixed', 'seed': 17, 'complete': True,
              'voice_readout':'connectome_downstream_calibrated_2_3_hop', 'readout_input_overlap':0,
              'voice_timing_calibrated':True, 'calibration_probe':'three fixed pulses; weights unchanged',
              'sync_report':'sync_report.json'}
    temporary = manifest.with_suffix('.tmp')
    temporary.write_text(json.dumps(result, indent=2), encoding='utf-8')
    os.replace(temporary, manifest)
    progress('ready', 1., project=str(manifest))
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('audio', type=Path)
    parser.add_argument('--start', type=float, default=0.)
    parser.add_argument('--duration', type=float, default=0.)
    parser.add_argument('--separation', choices=['demucs','dsp'], default='demucs')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    prepare(args.audio, args.start, args.duration, args.separation, args.force)
