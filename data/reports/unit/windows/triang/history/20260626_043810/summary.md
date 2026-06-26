# windows/triang Summary

- generated_at: 2026-06-26 04:38:10
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 1.192093e-07
- gpu_vs_cpu rmse: 4.362614e-08
- reference max_abs: 0.000000e+00
- reference max_rel: 0.000000e+00

## Performance

- cpu median_ms: 57.259
- cpu mean_ms: 57.259
- cpu p95_ms: 57.259
- gpu_e2e median_ms: 1.083
- gpu_e2e mean_ms: 1.083
- gpu_e2e p95_ms: 1.083
- gpu_e2e speedup: 52.872x
- gpu_kernel median_ms: 1.020
- gpu_kernel speedup: 56.140x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 576.000 MiB

## Cases

- periodic_small: pass, max_abs=0.000000e+00
- perf_large: pass, max_abs=1.192093e-07
