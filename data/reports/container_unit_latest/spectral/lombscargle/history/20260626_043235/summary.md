# spectral/lombscargle Summary

- generated_at: 2026-06-26 04:32:35
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.768372e-06
- gpu_vs_cpu max_rel: 1.087981e-03
- gpu_vs_cpu rmse: 5.311925e-07
- reference max_abs: 3.814697e-06
- reference max_rel: 2.342106e-04

## Performance

- cpu median_ms: 2151.512
- cpu mean_ms: 2151.512
- cpu p95_ms: 2151.512
- gpu_e2e median_ms: 12.497
- gpu_e2e mean_ms: 12.497
- gpu_e2e p95_ms: 12.497
- gpu_e2e speedup: 172.165x
- gpu_kernel median_ms: 12.290
- gpu_kernel speedup: 175.056x
- device_cache allocations: 8 calls, 0.189 MiB
- device_cache hits/misses: 8/8
- device_cache recycled: 13 blocks, 0.564 MiB

## Cases

- normalized_precentered: pass, max_abs=3.784895e-06
- perf_large: pass, max_abs=4.768372e-06
