"""Offline musical score. Audio describes stimulation and timing, never geometry.

Six overlapping roles are NOT six perfectly isolated instruments. Optional
Demucs stems improve bass/drum/vocal separation; HPSS is the explicit fallback.
"""
from pathlib import Path
import subprocess

import numpy as np
from scipy.ndimage import median_filter, uniform_filter1d
from scipy.signal import find_peaks, stft, butter, sosfiltfilt
from scipy.io import wavfile

RATE = 24000
HOP = 240
ROLES = ('impact', 'bass', 'snare', 'detail', 'lead', 'bed')


def decode(source, destination, start=0., duration=0.):
    command = ['ffmpeg', '-v', 'error', '-y', '-ss', str(start), '-i', str(source)]
    if duration > 0:
        command += ['-t', str(duration)]
    subprocess.run(command + ['-vn', '-ar', str(RATE), '-ac', '2', '-c:a', 'pcm_s16le',
                              str(destination)], check=True, creationflags=0x08000000)
    rate, pcm = wavfile.read(destination)
    if len(pcm) < rate * .1:
        raise ValueError('Choose at least 0.1 seconds of audio')
    return pcm.astype(np.float32) / 32768., rate


def spectrum(pcm, rate):
    if pcm.ndim == 1:
        pcm = pcm[:, None]
    # Stereo POWER preserves opposite-phase material.
    spectra = [stft(pcm[:, c], fs=rate, nperseg=2048, noverlap=2048-HOP,
                    boundary='zeros', padded=True)[2] for c in range(pcm.shape[1])]
    power = np.mean([np.abs(s)**2 for s in spectra], axis=0).T.astype(np.float32)
    return power, np.fft.rfftfreq(2048, 1./rate)


def _bounded(x):
    return np.clip((20.*np.log10(np.maximum(x, 1e-8))+64.)/49., 0., 1.)


def refine_attack(signal, rate, candidate, low, high):
    """2ms power rise in THIS role's stem and frequency range, not the mix."""
    step=max(1,round(rate*.002))
    lo=max(0,round((candidate-.035)*rate)); hi=min(len(signal),round((candidate+.025)*rate))
    fragment=signal[lo:hi]
    bins=len(fragment)//step
    if bins<4: return float(candidate)
    values=np.sqrt((fragment[:bins*step].reshape(bins,-1)**2).mean(axis=1))
    rise=np.diff(values)
    if rise.max()<.00008: return float(candidate)
    # The caller prefilters the full stem without phase shift. Arguments retain
    # the band provenance for diagnostic/tests; no snippet-edge filter artifacts.
    return (lo+(int(np.argmax(rise))+1)*step)/rate


def plan_phrases(times, levels, events, boundaries, duration):
    """Explicit cuts at real attacks/section changes; no free-running scene timer."""
    onset_times=np.array([e['time'] for e in events if e['voice'] in (0,2,4)])
    candidates=[]
    for boundary in boundaries:
        near=onset_times[np.abs(onset_times-boundary)<.24]
        candidates.append(float(near[np.argmin(np.abs(near-boundary))]) if len(near) else float(boundary))
    cuts=[0.]
    # Long sections get subshots only ON strong detected attacks, never at t+N.
    for event in events:
        t=event['time']
        structural=any(abs(t-b)<.012 for b in candidates)
        if t-cuts[-1]>.75 and (structural or
                (t-cuts[-1]>3.2 and event['voice'] in (0,2) and event['confidence']>.16)):
            cuts.append(t)
    for boundary in candidates:
        if .75<boundary<duration-.25 and min(abs(boundary-c) for c in cuts)>.75: cuts.append(boundary)
    cuts=sorted(set(cuts))+[float(duration)]
    phrases=[]
    for start,end in zip(cuts[:-1],cuts[1:]):
        sample=(times>=start)&(times<end)
        selected=[e for e in events if start<=e['time']<end]
        density=len(selected)/max(.1,end-start)
        active=levels[sample].mean(axis=0) if sample.any() else np.zeros(6)
        half=(start+end)*.5
        before=levels[(times>=start)&(times<half)].mean() if np.any((times>=start)&(times<half)) else 0.
        after=levels[(times>=half)&(times<end)].mean() if np.any((times>=half)&(times<end)) else 0.
        kind='silence' if active.max()<.05 else ('buildup' if after-before>.10 else ('fill' if density>14 else 'phrase'))
        phrases.append({'start':start,'end':end,'kind':kind,'attack_density':density,
                        'stages':[start,start+(end-start)*.18,start+(end-start)*.48,end-min(.35,(end-start)*.18),end]})
    return phrases


def analyze(pcm, rate=RATE, stems=None):
    """Centred, future-aware analysis on a 10ms sample clock (no wall time)."""
    power, freqs = spectrum(pcm, rate)
    frames = len(power)
    times = np.arange(frames)*HOP/rate
    magnitude = np.sqrt(power)
    harmonic = median_filter(magnitude, size=(31, 1))
    percussive = median_filter(magnitude, size=(1, 31))
    mask = harmonic**2 / np.maximum(harmonic**2+percussive**2, 1e-15)
    h, p = power*mask, power*(1.-mask)
    source_kind = 'harmonic/percussive DSP'
    bass_h, lead_h, bed_h = h, h, h
    if pcm.ndim==1: pcm=pcm[:,None]
    role_audio=[pcm]*6
    if stems:
        def stem_power(name):
            stem_rate, raw = wavfile.read(stems / (name+'.wav'))
            if stem_rate!=rate: raise ValueError('Stem sample rate differs from soundtrack')
            if np.issubdtype(raw.dtype, np.integer): raw = raw.astype(np.float32)/32768.
            result, _ = spectrum(raw, rate)
            if result.shape != power.shape:
                raise ValueError('Stem sample alignment differs from the original')
            return result,raw
        p,drums = stem_power('drums')
        bass_h,bass_audio = stem_power('bass')
        bed_h,other = stem_power('other')
        vocal_power,vocals = stem_power('vocals')
        # Lead is vocal where present; otherwise use melodic accompaniment.
        vocal_energy=vocal_power.sum(axis=1)
        voice_present=vocal_energy>np.maximum(1e-7,bed_h.sum(axis=1)*.12)
        lead_h=np.where(voice_present[:,None],vocal_power,bed_h)
        sample_presence=np.interp(np.arange(len(pcm))/rate,times,voice_present.astype(float))[:,None]
        lead_audio=vocals*sample_presence+other*(1.-sample_presence)
        role_audio=[drums,bass_audio,drums,drums,lead_audio,other]
        source_kind = 'Demucs htdemucs: drums / bass / vocals / other'
    def energy(matrix, lo, hi):
        return np.sqrt(matrix[:, (freqs >= lo) & (freqs < hi)].sum(axis=1))
    raw = np.column_stack([energy(p, 35, 220), energy(bass_h, 35, 420),
                           energy(p, 220, 3600), energy(p, 3600, 12000),
                           energy(lead_h, 220, 4800), energy(bed_h, 300, 10000)])
    levels = _bounded(raw)
    # Per-track display-input contrast. This is audio calibration, never neural
    # learning; avoid every loud separated stem living at the same 0.9 ceiling.
    floor = np.maximum(.10, np.quantile(levels, .12, axis=0)-.08)
    ceiling = np.maximum(floor+.30, np.quantile(levels, .98, axis=0))
    levels = np.clip((levels-floor)/(ceiling-floor), 0., 1.)
    # Attacks/release are independent; no single global pulse replaces them.
    envelopes = np.zeros_like(levels)
    attack = np.array([.005, .014, .004, .003, .012, .100])
    release = np.array([.065, .110, .050, .026, .100, .350])
    for i in range(1, frames):
        tau = np.where(levels[i] > envelopes[i-1], attack, release)
        envelopes[i] = envelopes[i-1]+(levels[i]-envelopes[i-1])*(1.-np.exp(-.01/tau))
    edges = np.geomspace(45., 12000., 17)
    bands = np.column_stack([_bounded(energy(power, lo, hi)) for lo, hi in zip(edges[:-1], edges[1:])])
    active = power.sum(axis=1)>1e-8
    levels[~active] = 0.; bands[~active] = 0.
    # Stable spectral pitch contour, not a claim of polyphonic note transcription.
    lead_range = (freqs >= 170) & (freqs < 2600)
    indices = np.argmax(lead_h[:, lead_range], axis=1)
    pitch = np.log2(freqs[lead_range][indices]/170.)/4.
    pitch = median_filter(pitch, size=5)*np.minimum(1., levels[:, 4]*2.)
    brightness = np.sum(power*(freqs/12000.), axis=1)/np.maximum(power.sum(axis=1), 1e-12)
    events = []
    role_ranges=[(35,220),(35,420),(220,3600),(3600,11000),(220,4800),(300,10000)]
    for voice in range(6):
        novelty = np.maximum(0., levels[:, voice]-np.roll(levels[:, voice], 2))
        novelty[:2] = 0.
        baseline = uniform_filter1d(novelty, 101)
        peaks, _ = find_peaks(novelty, height=np.maximum(.065, baseline*2.2),
                              prominence=.025, distance=[10,15,5,5,18,35][voice])
        low,high=role_ranges[voice]
        filtered=sosfiltfilt(butter(3,[low,high],btype='bandpass',fs=rate,output='sos'),role_audio[voice],axis=0)
        for k in peaks:
            refined=refine_attack(filtered,rate,times[k],low,high)
            if refined>=len(pcm)/rate: continue
            events.append({'time': round(float(refined), 5), 'voice': voice,
                           'timing_source':'role_stem_band' if stems else 'isolated_mix_band',
                           'confidence': round(float(np.clip(novelty[k], 0., 1.)), 4)})
    events.sort(key=lambda e: (e['time'], e['voice']))
    for i, event in enumerate(events): event['id'] = i+1
    # Structural novelty compares the preceding/following 1s timbral histories.
    kernel = max(1, int(rate/HOP))
    smooth = uniform_filter1d(bands, kernel, axis=0)
    novelty = np.zeros(frames)
    if frames > kernel:
        novelty[kernel//2:-kernel//2] = np.abs(smooth[kernel:]-smooth[:-kernel]).mean(axis=1)
    boundary_indices, _ = find_peaks(novelty, height=max(.045, float(np.percentile(novelty, 80))),
                                     prominence=.025, distance=180)
    boundaries = [float(times[k]) for k in boundary_indices if .7 < times[k] < len(pcm)/rate-.5]
    # Keep individual attacks unquantized; tempo is only a confidence-rated hint.
    impact_times = np.array([e['time'] for e in events if e['voice'] == 0])
    intervals = np.diff(impact_times)
    intervals = intervals[(intervals > .25) & (intervals < 1.2)]
    beat = float(np.median(intervals)) if len(intervals)>3 else 0.
    confidence = max(0., 1.-float(np.std(intervals)/max(.001, beat))) if beat else 0.
    phrases=plan_phrases(times,levels,events,boundaries,len(pcm)/rate)
    return {'times': times, 'bands': bands, 'voices': envelopes, 'pitch': pitch,
            'brightness': brightness, 'events': events, 'boundaries': boundaries,
            'duration': len(pcm)/rate, 'source_kind': source_kind,
            'beat_seconds': beat, 'beat_confidence': confidence, 'phrases':phrases}


def features_at(score, t, advances=None):
    k = min(len(score['times'])-1, max(0, int(round(t/.01))))
    voice_levels=score['voices'][k]
    voice_pitch=np.full(6,float(score['pitch'][k]))
    if advances is not None:
        # Positive lookahead: at model time t, inject source audio at t+delay.
        # Padding is silence, never an indefinitely held first/last sample.
        source_times=t+np.asarray(advances)
        indices=np.clip(np.rint(source_times/.01).astype(int),0,len(score['times'])-1)
        voice_levels=score['voices'][indices,np.arange(6)]
        voice_pitch=score['pitch'][indices]
        voice_levels=np.where((source_times>=0)&(source_times<score['duration']),voice_levels,0.)
        voice_bands=score['bands'][indices]
    else:
        voice_bands=np.tile(score['bands'][k],(6,1))
    return {'bands': score['bands'][k], 'voices': voice_levels,'voice_pitch':voice_pitch,'voice_bands':voice_bands,
            'pitch': float(score['pitch'][k]), 'brightness': float(score['brightness'][k])}
