# waveforms/sawtooth Summary

- generated_at: 2026-06-26 09:52:15
- pass: true
- accuracy_cases: 2
- perf_cases: 2

## Errors

- gpu_vs_cpu max_abs: 2.384186e-07
- gpu_vs_cpu max_rel: 3.750000e-01
- gpu_vs_cpu rmse: 1.145572e-07
- reference max_abs: 7.589099e-08
- reference max_rel: 8.940697e-08

## Performance

- cpu median_ms: 159.757
- cpu mean_ms: 159.419
- cpu p95_ms: 159.757
- gpu_e2e median_ms: 2.886
- gpu_e2e mean_ms: 2.885
- gpu_e2e p95_ms: 2.886
- gpu_e2e speedup: 55.357x
- gpu_kernel median_ms: 2.853
- gpu_kernel speedup: 56.005x
- device_cache allocations: 6 calls, 128.000 MiB
- device_cache hits/misses: 73/6
- device_cache recycled: 76 blocks, 4736.000 MiB

## Cases

- triangle_scalar: pass, max_abs=7.589099e-08
- vector_width: pass, max_abs=0.000000e+00
- perf_scalar: pass, max_abs=1.192093e-07
- perf_vector: pass, max_abs=2.384186e-07
