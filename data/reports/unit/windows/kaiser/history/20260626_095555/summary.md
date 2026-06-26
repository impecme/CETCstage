# windows/kaiser Summary

- generated_at: 2026-06-26 09:55:55
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.668930e-06
- gpu_vs_cpu max_rel: 2.193891e-06
- gpu_vs_cpu rmse: 1.765054e-07
- reference max_abs: 1.192093e-07
- reference max_rel: 3.705745e-07

## Performance

- cpu median_ms: 2355.129
- cpu mean_ms: 2355.129
- cpu p95_ms: 2355.129
- gpu_e2e median_ms: 10.004
- gpu_e2e mean_ms: 10.004
- gpu_e2e p95_ms: 10.004
- gpu_e2e speedup: 235.414x
- gpu_kernel median_ms: 9.945
- gpu_kernel speedup: 236.816x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4544.000 MiB

## Cases

- beta_86: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=1.668930e-06
