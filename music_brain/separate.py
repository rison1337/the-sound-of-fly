"""Runs only in the isolated separator environment; never trains the model."""
import argparse
from pathlib import Path
import numpy as np
import torch
from scipy.io import wavfile
from scipy.signal import resample_poly
from demucs.pretrained import get_model
from demucs.apply import apply_model


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('audio', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    rate, pcm = wavfile.read(args.audio)
    pcm = pcm.astype(np.float32)/32768.
    model = get_model('htdemucs')
    torch.manual_seed(17)
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    model.to(device).eval()
    import math
    divisor = math.gcd(rate, model.samplerate)
    wave = resample_poly(pcm, model.samplerate//divisor, rate//divisor, axis=0)
    wave = torch.from_numpy(wave.T.copy())
    ref = wave.mean(0)
    mean, std = ref.mean(), ref.std().clamp_min(1e-8)
    normalized = (wave-mean)/std
    print(f'Separating four sources on {device}; model weights fixed', flush=True)
    with torch.inference_mode():
        separated = apply_model(model, normalized[None], device=device, shifts=0,
                                split=True, overlap=.25, segment=5., progress=True)[0].cpu()*std+mean
    args.output.mkdir(parents=True, exist_ok=True)
    for name, source in zip(model.sources, separated):
        restored = resample_poly(source.numpy().T, rate//divisor, model.samplerate//divisor, axis=0)
        restored = restored[:len(pcm)]
        if len(restored)<len(pcm): restored=np.pad(restored, ((0,len(pcm)-len(restored)),(0,0)))
        wavfile.write(args.output/(name+'.wav'), rate, restored.astype(np.float32))
    print('STEMS_READY', flush=True)


if __name__ == '__main__': main()
