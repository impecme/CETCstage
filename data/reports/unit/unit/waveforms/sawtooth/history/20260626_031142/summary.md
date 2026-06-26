# waveforms/sawtooth Summary

- generated_at: 2026-06-26 03:11:42
- pass: true
- accuracy_cases: 0
- perf_cases: 2

## Errors

- gpu_vs_cpu max_abs: 2.384186e-07
- gpu_vs_cpu max_rel: 3.750000e-01
- gpu_vs_cpu rmse: 1.141789e-07

## Performance

- cpu median_ms: 9.077
- cpu mean_ms: 9.026
- cpu p95_ms: 9.077
- gpu_e2e median_ms: 0.244
- gpu_e2e mean_ms: 0.243
- gpu_e2e p95_ms: 0.244
- gpu_e2e speedup: 37.250x
- gpu_kernel median_ms: 0.210
- gpu_kernel speedup: 43.320x
- device_cache allocations: 2 calls, 8.000 MiB
- device_cache hits/misses: 10/2
- device_cache recycled: 12 blocks, 48.000 MiB

## Cases

- perf_scalar: pass, max_abs=1.192093e-07
- perf_vector: pass, max_abs=2.384186e-07
