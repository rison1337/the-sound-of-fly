"""Offline articulation from recorded downstream samples, never audio amplitude.

The musical clock fixes the contact time. A bounded response window supplies
strength/contour from the same voice's recorded neurons. Source timestamps are
retained so this editorial retiming is inspectable, not presented as zero
biological latency.
"""
import numpy as np
try:
    from .score import ROLES
except ImportError:
    from score import ROLES


def build_sync_report(score, voice_history, step_s=.02):
    rows=np.asarray(voice_history,dtype=np.float32)
    if rows.ndim!=3 or rows.shape[1:]!=(6,4):
        raise ValueError('Expected recorded frames x 6 downstream voices x 4 values')
    times=np.arange(len(rows))*step_s
    report=[]
    for voice in range(6):
        events=[e for e in score['events'] if e['voice']==voice]
        for i,event in enumerate(events):
            t=float(event['time'])
            # Midpoints prevent an adjacent note from donating its entire peak.
            lo=max(0.,t-.06,(events[i-1]['time']+t)*.5 if i else 0.)
            hi=min(times[-1]+step_s,t+.16,(events[i+1]['time']+t)*.5 if i+1<len(events) else times[-1]+step_s)
            indices=np.flatnonzero((times>=lo)&(times<hi))
            if not len(indices): indices=np.array([min(len(rows)-1,round(t/step_s))])
            strength=np.clip(rows[indices,voice,0]*.35+rows[indices,voice,1]*.65,0.,1.)**1.5
            # Prefer the nearest peak among ties, not the first frame of a plateau.
            best=np.flatnonzero(strength>=strength.max()-.001)
            local=best[np.argmin(np.abs(times[indices[best]]-t))]
            peak=int(indices[local]); sample=rows[peak,voice].tolist()
            event['neural_sample']=sample
            event['neural_source_time']=round(float(times[peak]),5)
            event['prepare_s']=.07 if voice in (0,2,3) else .12
            report.append({'id':event['id'],'voice':voice,'source_time':t,
                           'neural_peak_time':float(times[peak]),
                           'neural_offset_ms':round((times[peak]-t)*1000.,2),
                           'strength':round(float(strength[local]),5),
                           'motion_contact_time':t})
    voices=[]
    for voice in range(6):
        events=[e for e in report if e['voice']==voice]
        responding=[e for e in events if e['strength']>.02]
        offsets=[e['neural_offset_ms'] for e in responding]
        voices.append({'voice':voice,'role':ROLES[voice],'events':len(events),
                       'responding_events':len(responding),
                       'median_strength':float(np.median([e['strength'] for e in events])) if events else None,
                       'median_neural_offset_ms':float(np.median(offsets)) if offsets else None,
                       'p90_abs_neural_offset_ms':float(np.percentile(np.abs(offsets),90)) if offsets else None})
    return {'step_s':step_s,'voices':voices,'events':sorted(report,key=lambda e:e['id']),
            'method':'per-voice bounded downstream sample retimed to musical contact; silence stays silent',
            'render_quantization_ms':1000./120.,
            'note':'Neural offsets are measured. Motion contacts are scheduled, not measured screen/audio-device latency.',
            'levels':rows[:,:,:2].round(4).tolist()}
