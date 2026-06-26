# spectral/spectrogram Summary

- generated_at: 2026-06-26 03:46:20
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 5.960464e-08
- gpu_vs_cpu max_rel: 4.474719e+12
- gpu_vs_cpu rmse: 6.500600e-09
- reference max_abs: 5.960464e-08
- reference max_rel: 2.490654e-01

## Performance

- cpu median_ms: 365.702
- cpu mean_ms: 365.702
- cpu p95_ms: 365.702
- gpu_e2e median_ms: 39.319
- gpu_e2e mean_ms: 39.319
- gpu_e2e p95_ms: 39.319
- gpu_e2e speedup: 9.301x
- gpu_kernel median_ms: 38.508
- gpu_kernel speedup: 9.497x
- device_cache allocations: 10 calls, 20.267 MiB
- device_cache hits/misses: 10/10
- device_cache recycled: 16 blocks, 149.133 MiB

## Cases

- psd_case: pass, max_abs=1.490116e-08
- complex_case: pass, max_abs=5.960464e-08
- perf_psd: pass, max_abs=5.401671e-08
