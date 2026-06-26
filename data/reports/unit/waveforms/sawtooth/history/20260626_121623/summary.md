# waveforms/sawtooth Summary

- generated_at: 2026-06-26 12:16:23
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

- cpu median_ms: 159.004
- cpu mean_ms: 158.729
- cpu p95_ms: 159.004
- gpu_e2e median_ms: 2.890
- gpu_e2e mean_ms: 2.888
- gpu_e2e p95_ms: 2.890
- gpu_e2e speedup: 55.025x
- gpu_kernel median_ms: 2.852
- gpu_kernel speedup: 55.743x
- device_cache allocations: 6 calls, 128.000 MiB
- device_cache hits/misses: 73/6
- device_cache recycled: 76 blocks, 4736.000 MiB

## Cases

- triangle_scalar: pass, max_abs=7.589099e-08
- vector_width: pass, max_abs=0.000000e+00
- perf_scalar: pass, max_abs=1.192093e-07
- perf_vector: pass, max_abs=2.384186e-07
