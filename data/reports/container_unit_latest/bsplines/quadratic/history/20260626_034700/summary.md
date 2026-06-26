# bsplines/quadratic Summary

- generated_at: 2026-06-26 03:47:00
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

- cpu median_ms: 59.762
- cpu mean_ms: 59.762
- cpu p95_ms: 59.762
- gpu_e2e median_ms: 1.679
- gpu_e2e mean_ms: 1.679
- gpu_e2e p95_ms: 1.679
- gpu_e2e speedup: 35.595x
- gpu_kernel median_ms: 1.625
- gpu_kernel speedup: 36.772x
- device_cache allocations: 6 calls, 128.000 MiB
- device_cache hits/misses: 8/6
- device_cache recycled: 13 blocks, 640.000 MiB

## Cases

- boundary_vector: pass, max_abs=0.000000e+00
- matrix_dense: pass, max_abs=0.000000e+00
- perf_large_vector: pass, max_abs=5.960464e-08
