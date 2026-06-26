# bsplines/gauss_spline Summary

- generated_at: 2026-06-26 03:38:14
- pass: true
- accuracy_cases: 3
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 3.161530e-07
- gpu_vs_cpu rmse: 2.044426e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 2.451261e-06

## Performance

- cpu median_ms: 162.974
- cpu mean_ms: 162.974
- cpu p95_ms: 162.974
- gpu_e2e median_ms: 1.684
- gpu_e2e mean_ms: 1.684
- gpu_e2e p95_ms: 1.684
- gpu_e2e speedup: 96.794x
- gpu_kernel median_ms: 1.625
- gpu_kernel speedup: 100.310x
- device_cache allocations: 6 calls, 128.000 MiB
- device_cache hits/misses: 8/6
- device_cache recycled: 13 blocks, 640.000 MiB

## Cases

- order3_vector: pass, max_abs=5.960464e-08
- order6_matrix: pass, max_abs=2.980232e-08
- invalid_order: pass, max_abs=0.000000e+00
- perf_order5_large_vector: pass, max_abs=1.192093e-07
