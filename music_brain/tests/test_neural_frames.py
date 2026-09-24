import numpy as np
from music_brain.neural_frames import NeuralFrames


def test_each_neuron_survives_transport_with_independent_rate_and_spikes():
    n=165122
    frame=NeuralFrames(n)
    spikes=np.zeros(n,bool)
    spikes[[0,87000,n-1]]=True
    frame.observe(spikes,9)
    frame.observe(spikes,10)
    rates=np.linspace(0,250,n,dtype=np.float32)
    data=np.frombuffer(frame.encode(rates,12),np.uint8).reshape(-1,4)
    decoded=(data[:n,0].astype(np.uint16)+256*data[:n,1].astype(np.uint16))/32.
    np.testing.assert_allclose(decoded,rates,atol=1/64.)
    assert data[n-1,2]==2
    assert data[87000,3]==2
    assert data[1,2]==0
    assert data[1,3]==255
    next_data=np.frombuffer(frame.encode(rates,13),np.uint8).reshape(-1,4)
    assert next_data[:n,2].sum()==0
    assert next_data[n-1,3]==3


def test_reordering_activity_changes_the_frame_even_with_identical_mean():
    first=NeuralFrames(4).encode(np.array([20.,0.,0.,0.]),0)
    second=NeuralFrames(4).encode(np.array([0.,0.,0.,20.]),0)
    assert first!=second


def test_gpu_addresses_survive_compatibility_half_float_storage():
    indices=np.arange(165122)
    addresses=np.column_stack([indices%512,indices//512]).astype(np.float16)
    recovered=addresses[:,0].astype(int)+512*addresses[:,1].astype(int)
    np.testing.assert_array_equal(recovered,indices)
