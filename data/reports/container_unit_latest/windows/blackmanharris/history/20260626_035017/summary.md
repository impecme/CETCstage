# windows/blackmanharris Summary

- generated_at: 2026-06-26 03:50:17
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 2.384186e-07
- gpu_vs_cpu max_rel: 5.218995e-04
- gpu_vs_cpu rmse: 4.770082e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 5.201097e-04

## Performance

- cpu median_ms: 0.296
- cpu mean_ms: 0.296
- cpu p95_ms: 0.296
- gpu_e2e median_ms: 0.083
- gpu_e2e mean_ms: 0.083
- gpu_e2e p95_ms: 0.083
- gpu_e2e speedup: 3.558x
- gpu_kernel median_ms: 0.035
- gpu_kernel speedup: 8.533x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 0.563 MiB

## Cases

- periodic_small: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=2.384186e-07
