# windows/general_hamming Summary

- generated_at: 2026-06-26 04:37:47
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.490116e-07
- gpu_vs_cpu max_rel: 6.924498e-07
- gpu_vs_cpu rmse: 4.544243e-08
- reference max_abs: 2.086163e-07
- reference max_rel: 9.313226e-07

## Performance

- cpu median_ms: 0.130
- cpu mean_ms: 0.130
- cpu p95_ms: 0.130
- gpu_e2e median_ms: 0.077
- gpu_e2e mean_ms: 0.077
- gpu_e2e p95_ms: 0.077
- gpu_e2e speedup: 1.695x
- gpu_kernel median_ms: 0.030
- gpu_kernel speedup: 4.313x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 0.563 MiB

## Cases

- alpha_052: pass, max_abs=1.192093e-07
- perf_large: pass, max_abs=1.490116e-07
