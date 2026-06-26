# windows/exponential Summary

- generated_at: 2026-06-26 03:50:22
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 5.960464e-08
- gpu_vs_cpu max_rel: 2.295571e-07
- gpu_vs_cpu rmse: 4.214685e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 1.300743e-07

## Performance

- cpu median_ms: 0.085
- cpu mean_ms: 0.085
- cpu p95_ms: 0.085
- gpu_e2e median_ms: 0.167
- gpu_e2e mean_ms: 0.167
- gpu_e2e p95_ms: 0.167
- gpu_e2e speedup: 0.507x
- gpu_kernel median_ms: 0.098
- gpu_kernel speedup: 0.861x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 9/2
- device_cache recycled: 11 blocks, 0.563 MiB

## Cases

- default_tau: pass, max_abs=5.960464e-08
- center_tau: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=5.960464e-08
