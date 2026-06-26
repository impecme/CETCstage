# windows/blackmanharris Summary

- generated_at: 2026-06-26 12:17:43
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
- gpu_e2e median_ms: 0.082
- gpu_e2e mean_ms: 0.082
- gpu_e2e p95_ms: 0.082
- gpu_e2e speedup: 3.618x
- gpu_kernel median_ms: 0.035
- gpu_kernel speedup: 8.507x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4.438 MiB

## Cases

- periodic_small: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=2.384186e-07
