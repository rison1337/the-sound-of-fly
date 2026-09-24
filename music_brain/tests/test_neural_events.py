import numpy as np
from music_brain.neural_events import NeuralEvents


def test_silence_and_steady_population_do_not_generate_repeated_cuts():
    editor = NeuralEvents()
    for _ in range(100):
        assert editor.update(np.zeros(16), .025)['event']['id'] == 0
    onset = editor.update(np.full(16, .5), .025)['event']['id']
    assert onset == 1
    for _ in range(100):
        state = editor.update(np.full(16, .5), .025)
        assert state['event']['id'] == onset
    assert state['hit'] < .001


def test_distinct_neural_transients_produce_distinct_montage_events():
    editor = NeuralEvents()
    for _ in range(12): editor.update(np.zeros(16), .025)
    low = np.r_[np.full(5,.4), np.zeros(11)]
    first = editor.update(low, .025)
    assert first['event']['kind'] == 'impact'
    for _ in range(12): editor.update(np.zeros(16), .025)
    high = np.r_[np.zeros(11), np.full(5,.4)]
    second = editor.update(high, .025)
    assert second['event']['kind'] == 'detail'
    assert second['event']['id'] == first['event']['id']+1


def test_pause_does_not_advance_montage():
    editor = NeuralEvents()
    editor.update(np.full(16,.6), .025)
    before = editor.last_event.copy()
    for _ in range(20):
        state = editor.update(np.zeros(16), 0.)
        assert state['event'] == before
