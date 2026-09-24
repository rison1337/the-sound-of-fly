"""Readout populations selected by real directed paths, never injected cells.

CSR rows are presynaptic, columns postsynaptic. Absolute weights measure path
support for SELECTION only; the simulator still propagates original signed
weights. No weights are changed and there is no fit to a particular song.
"""
import numpy as np


def select_downstream(weights, input_cells, voice_assignment, pitch_bins, max_cells=384, disjoint=True):
    count = weights.shape[0]
    excluded = np.zeros(count, bool)
    excluded[input_cells] = True
    graph = abs(weights).tocsr()
    # Four subpaths per role retain a downstream contour. First-hop cells may
    # relay; final candidates must have a 2- or 3-edge path from the input.
    paths = np.zeros((6, 4, count), np.float32)
    first_hop = np.zeros((6, count), np.float32)
    for role in range(6):
        for quarter in range(4):
            seeds = input_cells[(voice_assignment == role) & (pitch_bins//4 == quarter)]
            if not len(seeds): continue
            first = np.asarray(graph[seeds].sum(axis=0)).ravel()/len(seeds)
            first[excluded] = 0.
            second = np.asarray(first @ graph).ravel()
            second[excluded] = 0.
            third = np.asarray(second @ graph).ravel()
            third[excluded] = 0.
            # Normalize globally, preserving actual relative path support.
            second /= max(float(second.sum()), 1e-12)
            third /= max(float(third.sum()), 1e-12)
            paths[role, quarter] = second*.7+third*.3
            first_hop[role] += first
    support = paths.sum(axis=1)
    total = support.sum(axis=0)
    cells, contours, metadata = [], [], []
    occupied = excluded.copy()
    for role in range(6):
        # Prefer attributable rather than indiscriminate hub readouts. Role
        # groups are also disjoint, while the recurrent network remains shared.
        selectivity = support[role]/np.maximum(total, 1e-12)
        score = support[role]*(.15+selectivity)**2
        score[occupied] = 0.
        candidates = np.flatnonzero(score > 0.)
        order = np.argsort(-score[candidates], kind='stable')
        chosen = candidates[order[:max_cells]].astype(np.int64)
        if not len(chosen):
            raise ValueError(f'Voice {role} has no non-input 2/3-hop readout; refusing sensory fallback')
        cells.append(chosen)
        if disjoint: occupied[chosen] = True
        # A cell's strongest supported subpath defines its contour bin.
        bins = paths[role, :, chosen].argmax(axis=1)
        contours.append([chosen[bins == q] for q in range(4)])
        metadata.append({'voice': role, 'cells': len(chosen), 'selection_path_hops': [2, 3],
                         'direct_input_overlap': int(excluded[chosen].sum()),
                         'mean_role_selectivity': float(selectivity[chosen].mean()),
                         'also_one_hop': int(np.count_nonzero(first_hop[role, chosen]))})
    assert not excluded[np.concatenate(cells)].any()
    return cells, contours, metadata
