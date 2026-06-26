# windows/exponential Summary

- generated_at: 2026-06-26 09:53:40
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
- gpu_e2e median_ms: 0.073
- gpu_e2e mean_ms: 0.073
- gpu_e2e p95_ms: 0.073
- gpu_e2e speedup: 1.164x
- gpu_kernel median_ms: 0.029
- gpu_kernel speedup: 2.954x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 71/2
- device_cache recycled: 73 blocks, 4.438 MiB

## Cases

- default_tau: pass, max_abs=5.960464e-08
- center_tau: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=5.960464e-08
