"""Fixed-probe readout calibration: select electrodes, never fit neural weights.

Three known pulses per role at fixed pitches, independent of the chosen song.
Only genuinely responsive, structurally reachable non-input cells are selected.
All probe state is discarded before music simulation starts.
"""
import json
import numpy as np
try:
    from .downstream import select_downstream
except ImportError:
    from downstream import select_downstream


def calibrate(model, report_path=None):
    candidates, contour_groups, routes = select_downstream(
        model.brain.w, model.voice_inputs, model.voice_assignment, model.voice_bins,
        max_cells=4096, disjoint=False)
    starts = np.array([.25, .65, 1.05])
    duration = 1.50
    dt = model.brain.dt_s
    n = model.brain.n
    evoked = np.zeros((6, n), np.float32)
    traces = []
    baseline_counts = []
    # Matched spontaneous baseline: same RNG and times, no sensory injection.
    model.reset_state()
    model.set_audio({'bands':np.zeros(16),'voices':np.zeros(6),'pitch':.5})
    background=np.zeros(n,np.float32)
    for step in range(round(duration/dt)):
        model.step()
        if any(s<=step*dt<s+.28 for s in starts): background+=model.brain.spikes
    for role in range(6):
        model.reset_state()
        trace, spikes = [], []
        total = np.zeros(n, np.float32)
        quiet = np.zeros(n, np.float32)
        for step in range(round(duration/dt)):
            t = step*dt
            pulse = next((i for i,s in enumerate(starts) if s<=t<s+.16), -1)
            levels = np.zeros(6)
            if pulse>=0: levels[role]=.75
            if step%5 == 0:
                model.set_audio({'bands':np.full(16,.7),'voices':levels,
                                 'pitch':(.25,.5,.75)[max(0,pulse)]})
            model.step()
            if t<.20: quiet += model.brain.spikes
            elif any(s<=t<s+.28 for s in starts): total += model.brain.spikes
            if (step+1)%5 == 0:
                trace.append(model.brain.rate_ema[candidates[role]].copy())
                spikes.append(model.frames.counts[candidates[role]].copy()/ .01)
                model.frames.counts.fill(0)
        evoked[role] = np.maximum(0.,(total-background)/.84)
        baseline_counts.append(quiet/.20)
        traces.append((np.asarray(trace),np.asarray(spikes)))
    total_response = evoked.sum(axis=0)
    occupied = np.zeros(n,bool); occupied[model.voice_inputs]=True
    selected, contours, report = [], [], []
    for role in range(6):
        ids = candidates[role]
        selectivity = evoked[role,ids]/np.maximum(total_response[ids],1e-6)
        rank = evoked[role,ids]*(.10+selectivity)**2
        rank[occupied[ids]]=0.
        order = np.argsort(-rank,kind='stable')
        usable = order[(rank[order]>.02) & (evoked[role,ids[order]]>.10)]
        chosen_local = usable[:384]
        chosen = ids[chosen_local]
        if len(chosen)<8:
            raise RuntimeError(f'Voice {role}: only {len(chosen)} responsive downstream cells; no audio fallback')
        selected.append(chosen); occupied[chosen]=True
        contours.append([np.intersect1d(chosen,c) for c in contour_groups[role]])
        rate, instant = traces[role]
        rate=rate[:,chosen_local].mean(axis=1); instant=instant[:,chosen_local].mean(axis=1)
        times=(np.arange(len(rate))+1)*.01
        baseline=float(np.quantile(rate[times<.2],.9))
        # A 160ms selection probe finds stable readouts, but its end-of-note
        # maximum is not an attack delay. Measure timing with separate 40ms
        # impulses after selection, using the unchanged network.
        model.reset_state()
        attack_trace=[]
        for step in range(round(duration/dt)):
            t=step*dt
            pulse=next((i for i,s in enumerate(starts) if s<=t<s+.04),-1)
            levels=np.zeros(6)
            if pulse>=0: levels[role]=.75
            if step%5==0:
                model.set_audio({'bands':np.full(16,.7),'voices':levels,
                                 'pitch':(.25,.5,.75)[max(0,pulse)]})
            model.step()
            if (step+1)%5==0: attack_trace.append(float(model.brain.rate_ema[chosen].mean()))
        timing_rate=np.asarray(attack_trace)
        onset_delays,peak_delays,release_times=[],[],[]
        for start in starts:
            window=np.flatnonzero((times>=start)&(times<start+.20))
            peak_index=window[int(np.argmax(timing_rate[window]))]
            peak=float(timing_rate[peak_index]); threshold=baseline+max(.04,(peak-baseline)*.20)
            active=window[timing_rate[window]>threshold]
            if active.size:
                onset_delays.append(float(times[active[0]]-start))
                peak_delays.append(float(times[peak_index]-start))
                after=np.flatnonzero((times>max(start+.04,times[peak_index]))&(times<start+.35)&(timing_rate<threshold))
                if after.size: release_times.append(float(times[after[0]]-max(start+.04,times[peak_index])))
        direct=np.asarray(abs(model.brain.w[model.voice_inputs[model.voice_assignment==role]]).sum(axis=0)).ravel()
        report.append({**routes[role], 'cells':len(chosen), 'also_one_hop':int(np.count_nonzero(direct[chosen])),
                       'selection':'fixed signed-network probe among structural candidates',
                       'timing_probe_width_ms':40.,
                       'onset_ms':round(float(np.median(onset_delays))*1000,2) if onset_delays else 0.,
                       'peak_ms':round(float(np.median(peak_delays))*1000,2) if peak_delays else 0.,
                       'release_ms':round(float(np.median(release_times))*1000,2) if release_times else 240.,
                       'reliable_pulses':len(onset_delays), 'probe_peak_hz':float(rate.max()),
                       'noise_floor_hz':baseline+.015,
                       'rate_scale_hz':max(.10,float(np.quantile(rate,.95))-baseline)*.85,
                       'spike_scale_hz':max(.20,float(np.quantile(instant,.95)))*.85,
                       'mean_functional_selectivity':float(selectivity[chosen_local].mean())})
    model.voice_cells=selected; model.voice_contour_cells=contours
    model.readout_routes=report
    model.voice_calibration=report
    model.readout_mask.fill(False); model.readout_mask[np.concatenate(selected)]=True
    model.update_voice_owners()
    model.reset_state()
    if report_path:
        report_path.write_text(json.dumps({'method':'fixed three-pulse calibration; no weight changes',
                                         'voices':report},indent=2),encoding='utf-8')
    return report
