import numpy as np
import pytest
from scipy.sparse import csr_matrix
from music_brain.downstream import select_downstream


def graph_fixture():
    # Each role/quarter: input -> relay -> downstream -> downstream2.
    rows, cols, data = [], [], []
    for seed in range(24):
        for a, b in [(seed,seed+24),(seed+24,seed+48),(seed+48,seed+72)]:
            rows.append(a); cols.append(b); data.append(-.8 if a%5==0 else 1.)
        rows.append(seed+48); cols.append(seed); data.append(5.)  # feedback to INPUT
    return csr_matrix((data,(rows,cols)),shape=(110,110),dtype=np.float32)


def test_readout_is_postsynaptic_multihop_and_disjoint_from_every_input():
    graph = graph_fixture(); original=graph.copy()
    inputs=np.arange(24); voices=inputs//4; bins=(inputs%4)*4
    cells, contours, meta=select_downstream(graph,inputs,voices,bins,max_cells=8)
    for role in range(6):
        expected=set(range(48+role*4,52+role*4))|set(range(72+role*4,76+role*4))
        assert set(cells[role])==expected
        assert not np.intersect1d(cells[role],inputs).size
        assert all(len(c)==2 for c in contours[role])
        assert meta[role]['direct_input_overlap']==0
    assert len(set(np.concatenate(cells)))==48
    assert (graph!=original).nnz==0  # selecting paths cannot alter simulation weights


def test_no_fallback_to_inputs_when_connectome_has_no_downstream_path():
    with pytest.raises(ValueError,match='refusing sensory fallback'):
        select_downstream(csr_matrix((24,24)),np.arange(24),np.arange(24)//4,(np.arange(24)%4)*4)


def test_direction_matters_reversed_paths_are_not_output_routes():
    graph=graph_fixture()
    # Remove feedback, then transpose: now sensory nodes have no outgoing edges.
    graph=graph.tolil(); graph[48:72,:24]=0; graph=graph.tocsr().T.tocsr()
    with pytest.raises(ValueError):
        select_downstream(graph,np.arange(24),np.arange(24)//4,(np.arange(24)%4)*4)
