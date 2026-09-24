import io
import json
import struct

import numpy as np
import pytest

from music_brain.score import RATE, analyze
from music_brain.timeline import TimelineWriter, read_record


def test_silence_has_no_events_or_neural_stimulation():
    score = analyze(np.zeros((RATE*3, 2), np.float32))
    assert not score['bands'].any()
    assert not score['voices'].any()
    assert score['events'] == []
    assert score['boundaries'] == []


def test_bass_and_melody_have_distinct_roles_with_equal_timing():
    t = np.arange(RATE*2)/RATE
    scores = [analyze((.12*np.sin(2*np.pi*f*t))[:, None]) for f in (90., 880.)]
    bass, lead = [s['voices'][50:150].mean(axis=0) for s in scores]
    assert bass[1]>lead[1]+.2
    assert lead[4]>bass[4]+.2
    assert not np.allclose(scores[0]['pitch'], scores[1]['pitch'])


def test_short_hits_have_typed_sample_clock_events_near_actual_attack():
    pcm = np.zeros(RATE*3, np.float32)
    rng = np.random.default_rng(17)
    for start in (.5, 1., 1.5, 2.):
        x = np.arange(int(RATE*.10))/RATE
        hit = .25*rng.normal(size=len(x))*np.exp(-x/.012)
        pcm[int(start*RATE):int(start*RATE)+len(x)] += hit
    score = analyze(pcm[:, None])
    percussive = [e for e in score['events'] if e['voice'] in (2,3)]
    for start in (.5,1.,1.5,2.):
        assert any(abs(e['time']-start)<.025 for e in percussive)
    assert len({e['id'] for e in score['events']}) == len(score['events'])
    assert all(a['time']<=b['time'] for a,b in zip(score['events'],score['events'][1:]))


def test_full_binary_record_round_trip_and_rejects_truncation(tmp_path):
    writer = TimelineWriter(tmp_path)
    frame = bytes(range(256))*2600
    writer.append({'sim_time':0., 'seq':0},frame)
    writer.append({'sim_time':.02, 'seq':1},frame[::-1])
    writer.close()
    index = json.loads((tmp_path/'index.json').read_text())
    with (tmp_path/'neural.bin').open('rb') as stream:
        state, restored = read_record(stream,index[1]['offset'])
    assert state['seq']==1 and restored==frame[::-1]
    with pytest.raises(ValueError): read_record(io.BytesIO(b'123'),0)
    with pytest.raises(ValueError): read_record(io.BytesIO(struct.pack('<II',999999,12)),0)
