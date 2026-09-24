import numpy as np
from music_brain.score import features_at, plan_phrases
from music_brain.sync_analysis import build_sync_report


def test_lookahead_injects_future_attack_early_and_pads_silence():
    times=np.arange(101)*.01
    levels=np.zeros((101,6)); levels[50,0]=1.; levels[60,1]=.8
    score={'times':times,'duration':1.,'voices':levels,'pitch':times,
           'bands':np.repeat(times[:,None],16,axis=1),'brightness':times}
    frame=features_at(score,.4,[.1,.2,0,0,0,0])
    assert frame['voices'][0]==1. and frame['voices'][1]==.8
    assert np.allclose(frame['voice_bands'][:2,0],[.5,.6])
    score['voices'][:]=1.
    assert not features_at(score,-1.,[.1]*6)['voices'].any()
    assert not features_at(score,1.,[.1]*6)['voices'].any()


def test_event_strength_comes_from_own_downstream_and_silent_voice_stays_silent():
    rows=np.zeros((101,6,4)); rows[54,0]=[.5,.2,.7,.1]
    rows[51,2]=[1.,1.,.2,.3]
    score={'events':[{'id':1,'time':1.,'voice':0},{'id':2,'time':1.,'voice':4}]}
    report=build_sync_report(score,rows)
    assert score['events'][0]['neural_source_time']==1.08
    assert np.allclose(score['events'][0]['neural_sample'],rows[54,0])
    assert score['events'][1]['neural_sample']==[0.,0.,0.,0.]
    assert report['voices'][4]['responding_events']==0
    assert report['events'][0]['motion_contact_time']==1.


def test_next_note_cannot_donate_peak_to_previous_note():
    rows=np.zeros((101,6,4)); rows[55,0]=[.9,.8,.2,0.]
    score={'events':[{'id':1,'time':1.,'voice':0},{'id':2,'time':1.1,'voice':0}]}
    build_sync_report(score,rows)
    assert score['events'][0]['neural_sample'][0]==0.
    assert score['events'][1]['neural_sample'][0]>.8


def test_phrase_cuts_have_an_audio_source_and_silence_does_not_tick():
    times=np.arange(1401)*.01
    events=[{'id':i,'time':t,'voice':0,'confidence':.5} for i,t in enumerate([.5,1.,4.1,4.5,8.8,12.9])]
    phrases=plan_phrases(times,np.ones((1401,6)),events,[],14.)
    assert all(p['start']==0 or p['start'] in [e['time'] for e in events] for p in phrases)
    quiet=plan_phrases(times,np.zeros((1401,6)),[],[],14.)
    assert len(quiet)==1 and quiet[0]['kind']=='silence'
