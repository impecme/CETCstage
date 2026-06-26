# filtering/sosfilt Summary

- generated_at: 2026-06-26 09:57:08
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.172325e-07
- gpu_vs_cpu max_rel: 7.626356e-04
- gpu_vs_cpu rmse: 5.297287e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 2.187190e-07

## Performance

- cpu median_ms: 8.066
- cpu mean_ms: 8.066
- cpu p95_ms: 8.066
- gpu_e2e median_ms: 1.377
- gpu_e2e mean_ms: 1.377
- gpu_e2e p95_ms: 1.377
- gpu_e2e speedup: 5.858x
- gpu_kernel median_ms: 1.313
- gpu_kernel speedup: 6.143x
- device_cache allocations: 10 calls, 8.094 MiB
- device_cache hits/misses: 71/10
- device_cache recycled: 75 blocks, 288.000 MiB

## Cases

- with_state_1d: pass, max_abs=5.960464e-08
- perf_1d: pass, max_abs=4.172325e-07
