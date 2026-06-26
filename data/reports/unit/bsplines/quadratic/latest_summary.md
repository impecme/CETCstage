# bsplines/quadratic Summary

- generated_at: 2026-06-26 12:17:24
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 5.960464e-08
- gpu_vs_cpu max_rel: 1.191681e-07
- gpu_vs_cpu rmse: 5.356825e-09
- reference max_abs: 2.980232e-08
- reference max_rel: 9.126961e-07

## Performance

- cpu median_ms: 58.986
- cpu mean_ms: 58.986
- cpu p95_ms: 58.986
- gpu_e2e median_ms: 1.678
- gpu_e2e mean_ms: 1.678
- gpu_e2e p95_ms: 1.678
- gpu_e2e speedup: 35.163x
- gpu_kernel median_ms: 1.625
- gpu_kernel speedup: 36.297x
- device_cache allocations: 6 calls, 128.000 MiB
- device_cache hits/misses: 70/6
- device_cache recycled: 75 blocks, 4608.000 MiB

## Cases

- boundary_vector: pass, max_abs=0.000000e+00
- matrix_dense: pass, max_abs=0.000000e+00
- perf_large_vector: pass, max_abs=5.960464e-08
