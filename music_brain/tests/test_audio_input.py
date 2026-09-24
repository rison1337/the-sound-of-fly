import numpy as np
import pytest

from music_brain.audio_input import AudioAnalysis


def tone(frequency, rate=48000, amplitude=.12):
    return (amplitude*np.sin(np.arange(4096)*2*np.pi*frequency/rate)).astype(np.float32)


def test_stereo_phase_does_not_cancel_music():
    wave = tone(880)
    normal = AudioAnalysis().analyze(np.column_stack([wave, wave]), 48000, 1.)
    opposite = AudioAnalysis().analyze(np.column_stack([wave, -wave]), 48000, 1.)
    np.testing.assert_allclose(normal['bands'], opposite['bands'])
    assert opposite['rms'] > .05


@pytest.mark.parametrize('frequency', [100, 880, 5000])
def test_tones_activate_the_corresponding_spectral_region(frequency):
    analyzer = AudioAnalysis()
    result = analyzer.analyze(tone(frequency), 48000, 1.)
    winner = int(np.argmax(result['bands']))
    expected = np.searchsorted(analyzer.edges, frequency)-1
    assert abs(winner-expected) <= 1
    assert result['bands'][winner] > .6


def test_paused_audio_decays_to_silence_without_latching():
    analyzer = AudioAnalysis()
    assert analyzer.analyze(tone(440), 48000, 1.)['bands'].max() > .5
    for _ in range(50):
        result = analyzer.analyze(np.zeros((4096, 2)), 48000, .04)
    assert not result['bands'].any()
    assert result['level'] == 0.


def test_invalid_pcm_cannot_poison_the_network():
    result = AudioAnalysis().analyze(np.array([np.nan, np.inf, -np.inf]), 48000)
    assert np.isfinite(result['bands']).all()
    assert result['rms'] == 0.


def test_sensitivity_does_not_turn_digital_silence_into_stimulation():
    result = AudioAnalysis().analyze(np.zeros((4096, 2)), 44100, gain=5.)
    assert not result['bands'].any()


def test_cut_clock_detects_separate_attacks_but_not_silence_or_sustained_tone():
    analyzer = AudioAnalysis()
    quiet = np.zeros((4096, 2), np.float32)
    for _ in range(20):
        result = analyzer.analyze(quiet, 48000, .025)
    assert result['cut_id'] == 0
    first = analyzer.analyze(tone(880), 48000, .025)
    assert first['cut_id'] == 1
    for _ in range(30):
        sustained = analyzer.analyze(tone(880), 48000, .025)
    assert sustained['cut_id'] == first['cut_id']
    for _ in range(30):
        analyzer.analyze(quiet, 48000, .025)
    second = analyzer.analyze(tone(880), 48000, .025)
    assert second['cut_id'] == 2
