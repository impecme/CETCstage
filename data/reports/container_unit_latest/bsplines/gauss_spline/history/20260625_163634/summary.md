# bsplines/gauss_spline Summary

- generated_at: 2026-06-25 16:36:34
- pass: true
- accuracy_cases: 3
- perf_cases: 0

## Errors

- gpu_vs_cpu max_abs: 5.960464e-08
- gpu_vs_cpu max_rel: 1.330017e-07
- gpu_vs_cpu rmse: 2.044426e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 2.451261e-06

## Performance

- device_cache allocations: 4 calls, 0.000 MiB
- device_cache hits/misses: 0/4
- device_cache recycled: 3 blocks, 0.000 MiB

## Cases

- order3_vector: pass, max_abs=5.960464e-08
- order6_matrix: pass, max_abs=2.980232e-08
- invalid_order: pass, max_abs=0.000000e+00
