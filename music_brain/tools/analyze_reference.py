"""Read a local reference dataset; write reproducible timing evidence, not art scores.

No media is copied, no audio is played, and no model or application state changes.
Run from the Droffel root with the existing Python environment.
"""
import argparse
import json
from pathlib import Path
import sys
import wave

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from music_brain.audio_input import AudioAnalysis


def nearest(times, events):
    if not len(events) or not len(times):
        return np.empty(0)
    return np.min(np.abs(times[:, None] - events[None, :]), axis=1)


def analyze(dataset):
    manifest = json.loads((dataset / "manifest.json").read_text(encoding="utf-8"))
    cuts = np.array([cut["time_seconds"] for cut in manifest["scene_cuts"]])
    with wave.open(str(dataset / "audio.wav"), "rb") as source:
        if source.getsampwidth() != 2:
            raise ValueError("Expected PCM16 WAV; convert explicitly before analysis")
        rate = source.getframerate()
        channels = source.getnchannels()
        samples = np.frombuffer(source.readframes(source.getnframes()), "<i2")
        samples = samples.astype(np.float32).reshape(-1, channels) / 32768.0
    duration = len(samples) / rate
    analyzer = AudioAnalysis(size=2048)
    hop = round(rate * .025)
    onsets, times, levels, band_values = [], [], [], []
    last_id = -1
    for end in range(hop, len(samples) + 1, hop):
        result = analyzer.analyze(samples[max(0, end - 2048):end], rate, hop / rate)
        now = end / rate
        times.append(now)
        levels.append(result["dbfs"])
        band_values.append(result["bands"].tolist())
        for event in result["timing_events"]:
            if event["id"] > last_id:
                onsets.append(now - event["age_ms"] / 1000.)
                last_id = event["id"]
    # Merge coincident band detectors, but do not imply these are annotated beats.
    merged = []
    for t in onsets:
        if not merged or t - merged[-1] > .045:
            merged.append(t)
    onsets = np.asarray(merged)
    times, levels, band_values = map(np.asarray, (times, levels, band_values))
    regions = []
    for name, start, end in (("intro", 0, 22), ("montage_a", 22, 34),
                             ("continuous_space", 34, 40), ("montage_b", 40, 52),
                             ("diagram_to_tunnel", 52, 59), ("closing_montage", 59, 64.5),
                             ("outro", 64.5, duration)):
        selected = (times >= start) & (times < end)
        local_cuts = cuts[(cuts >= start) & (cuts < end)]
        local_onsets = onsets[(onsets >= start) & (onsets < end)]
        bands = band_values[selected].mean(axis=0)
        regions.append({
            "name": name, "start_s": start, "end_s": round(end, 3),
            "detected_image_changes": len(local_cuts),
            "detected_transients": len(local_onsets),
            "transients_per_second": round(len(local_onsets) / (end - start), 2),
            "rms_dbfs_percentiles_10_50_90": np.percentile(levels[selected], [10, 50, 90]).round(2).tolist(),
            "normalized_band_mean_low_mid_high": [round(float(bands[:5].mean()), 3),
                                                      round(float(bands[5:11].mean()), 3),
                                                      round(float(bands[11:].mean()), 3)],
        })
    # Dense events naturally land near cuts: include shifted controls, and do
    # not call temporal proximity proof that every cut was manually beat-matched.
    active_cuts = cuts[(cuts >= 22) & (cuts < 64.5)]
    active_onsets = onsets[(onsets >= 22) & (onsets < 64.5)]
    distances = nearest(active_cuts, active_onsets)
    control = []
    for shift in (.731, 1.137, 1.913, 2.471, 3.179, 4.313, 5.113):
        shifted = 22 + np.mod(active_onsets - 22 + shift, 42.5)
        control.append(float(np.mean(nearest(active_cuts, shifted) <= .075)))
    return {
        "source": manifest["source"], "duration_s": round(duration, 3),
        "image_change_threshold": manifest["extraction"]["scene_threshold"],
        "image_change_count": len(cuts),
        "image_change_interval_ms_percentiles_0_25_50_75_95_100":
            np.percentile(np.diff(cuts) * 1000, [0, 25, 50, 75, 95, 100]).round(1).tolist(),
        "image_change_times_s": cuts.tolist(),
        "audio_detector": {"name": "Music Brain AudioAnalysis", "fft_samples": 2048,
                           "hop_samples": hop, "sample_rate": rate, "channels": channels,
                           "merged_transient_times_s": np.round(onsets, 4).tolist()},
        "alignment_22_to_64_5_s": {
            "image_changes": len(active_cuts), "merged_audio_transients": len(active_onsets),
            "nearest_transient_ms_percentiles_25_50_75_95": np.percentile(distances * 1000, [25, 50, 75, 95]).round(1).tolist(),
            "fraction_within_75_ms": round(float(np.mean(distances <= .075)), 3),
            "shifted_control_fraction_mean": round(float(np.mean(control)), 3),
        },
        "regions": regions,
        "limitations": [
            "Threshold image changes include flashes, polarity changes and transitions inside a continuous scene, not just edits.",
            "25 ms causal audio analysis is not a musical beat annotation or an end-to-end latency measurement.",
            "Temporal proximity is compared against shifted controls; density alone produces many coincidences.",
            "Regions are manual visual annotations; band means are the existing analyzer's bounded logarithmic values, not physical power ratios.",
            "No subjective listening or claim that every musical event has been identified.",
        ],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report = analyze(args.dataset)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in
                      ("audio_detector", "image_change_times_s", "limitations")}, indent=2))
