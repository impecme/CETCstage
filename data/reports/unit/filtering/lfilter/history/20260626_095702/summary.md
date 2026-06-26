# filtering/lfilter Summary

- generated_at: 2026-06-26 09:57:02
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 2.980232e-07
- gpu_vs_cpu max_rel: 8.013197e-05
- gpu_vs_cpu rmse: 5.072446e-08
- reference max_abs: 4.470348e-08
- reference max_rel: 2.006396e-07

## Performance

- cpu median_ms: 0.206
- cpu mean_ms: 0.206
- cpu p95_ms: 0.206
- gpu_e2e median_ms: 0.362
- gpu_e2e mean_ms: 0.362
- gpu_e2e p95_ms: 0.362
- gpu_e2e speedup: 0.568x
- gpu_kernel median_ms: 0.121
- gpu_kernel speedup: 1.698x
- device_cache allocations: 9 calls, 0.253 MiB
- device_cache hits/misses: 73/9
- device_cache recycled: 76 blocks, 8.875 MiB

## Cases

- with_state_1d: pass, max_abs=0.000000e+00
- perf_1d: pass, max_abs=2.980232e-07
