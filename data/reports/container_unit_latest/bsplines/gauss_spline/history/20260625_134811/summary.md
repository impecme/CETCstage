# bsplines/gauss_spline Summary

- generated_at: 2026-06-25 13:48:11
- pass: true
- accuracy_cases: 0
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 3.155789e-07
- gpu_vs_cpu rmse: 9.126075e-09

## Performance

- cpu median_ms: 7.306
- cpu mean_ms: 7.306
- cpu p95_ms: 7.306
- gpu_e2e median_ms: 3.336
- gpu_e2e mean_ms: 3.336
- gpu_e2e p95_ms: 3.336
- gpu_e2e speedup: 2.190x
- gpu_kernel median_ms: 3.266
- gpu_kernel speedup: 2.237x
- device_cache allocations: 2 calls, 8.000 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 40.000 MiB

## Cases

- perf_order5_large_vector: pass, max_abs=1.192093e-07
