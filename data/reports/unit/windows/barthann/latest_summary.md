# windows/barthann Summary

- generated_at: 2026-06-26 12:17:42
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 4.059513e-04
- gpu_vs_cpu rmse: 2.504086e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 7.192543e-08

## Performance

- cpu median_ms: 0.122
- cpu mean_ms: 0.122
- cpu p95_ms: 0.122
- gpu_e2e median_ms: 0.075
- gpu_e2e mean_ms: 0.075
- gpu_e2e p95_ms: 0.075
- gpu_e2e speedup: 1.640x
- gpu_kernel median_ms: 0.030
- gpu_kernel speedup: 4.048x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4.438 MiB

## Cases

- sym_small: pass, max_abs=0.000000e+00
- perf_large: pass, max_abs=1.192093e-07
