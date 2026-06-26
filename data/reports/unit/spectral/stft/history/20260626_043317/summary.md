# spectral/stft Summary

- generated_at: 2026-06-26 04:33:17
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 2.384477e-07
- gpu_vs_cpu max_rel: 1.209719e+23
- gpu_vs_cpu rmse: 2.191228e-08
- reference max_abs: 1.299205e-07
- reference max_rel: 1.876826e-01

## Performance

- cpu median_ms: 400.171
- cpu mean_ms: 400.171
- cpu p95_ms: 400.171
- gpu_e2e median_ms: 20.723
- gpu_e2e mean_ms: 20.723
- gpu_e2e p95_ms: 20.723
- gpu_e2e speedup: 19.311x
- gpu_kernel median_ms: 19.874
- gpu_kernel speedup: 20.135x
- device_cache allocations: 10 calls, 36.391 MiB
- device_cache hits/misses: 8/10
- device_cache recycled: 14 blocks, 294.272 MiB

## Cases

- zeros_padded: pass, max_abs=1.248873e-07
- perf_zeros_padded: pass, max_abs=2.384477e-07
