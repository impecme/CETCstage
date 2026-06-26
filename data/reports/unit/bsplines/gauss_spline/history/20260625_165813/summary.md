# bsplines/gauss_spline Summary

- generated_at: 2026-06-25 16:58:13
- pass: true
- accuracy_cases: 0
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 3.158603e-07
- gpu_vs_cpu rmse: 1.364907e-08

## Performance

- cpu median_ms: 7.318
- cpu mean_ms: 7.318
- cpu p95_ms: 7.318
- gpu_e2e median_ms: 0.180
- gpu_e2e mean_ms: 0.180
- gpu_e2e p95_ms: 0.180
- gpu_e2e speedup: 40.581x
- gpu_kernel median_ms: 0.128
- gpu_kernel speedup: 57.212x
- device_cache allocations: 2 calls, 8.000 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 40.000 MiB

## Cases

- perf_order5_large_vector: pass, max_abs=1.192093e-07
