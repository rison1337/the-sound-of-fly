"""Benchmark: time of one LIF step (sparse propagation) on CPU with the full graph.

This is the number that decides whether the sim kernel lives on CPU or TITAN V.
"""
import time
from pathlib import Path

import numpy as np
import scipy.sparse as sp

path = Path(__file__).resolve().parents[1] / "data" / "graph_malecns_v1.npz"
z = np.load(path)
n = len(z["ids"])
# stored pre->post; transpose to CSR so posts receive input via one row-sliced matvec
w_in = sp.csr_matrix((z["data"], z["indices"], z["indptr"].astype(np.int32)), shape=(n, n)).T.tocsr()
print(f"neurons: {n:,}   edges: {w_in.nnz:,}")

rng = np.random.default_rng(0)
v = np.zeros(n, dtype=np.float32)
spikes = (rng.random(n) > 0.999).astype(np.float32)

for _ in range(3):  # warmup
    v = v * 0.9 + w_in @ spikes

steps = 20
t0 = time.perf_counter()
for _ in range(steps):
    v = v * 0.9 + w_in @ spikes
    spikes = (v > 1.0).astype(np.float32)
    v *= 1.0 - spikes
dt_ms = (time.perf_counter() - t0) / steps * 1000
print(f"dense propagation: {dt_ms:.1f} ms per step  ({1000 / dt_ms:.0f} steps/s -> "
      f"{dt_ms:.1%} of real-time at dt=1ms, {dt_ms / 5:.1%} at dt=5ms)")

# event-driven: propagate only from neurons that spiked this step
w_fwd = sp.csr_matrix((z["data"], z["indices"], z["indptr"].astype(np.int32)), shape=(n, n))
for activity in (0.01, 0.001):
    idx = rng.choice(n, size=int(n * activity), replace=False)
    for _ in range(3):
        _ = w_fwd[idx].sum(axis=0)
    t0 = time.perf_counter()
    for _ in range(steps):
        inflow = w_fwd[idx].sum(axis=0)
    dt2_ms = (time.perf_counter() - t0) / steps * 1000
    print(f"event-driven @ {activity:.1%} active: {dt2_ms:.1f} ms per step")
