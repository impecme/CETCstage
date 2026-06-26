# bsplines/cubic Summary

- generated_at: 2026-06-26 03:46:51
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 5.960464e-08
- gpu_vs_cpu max_rel: 2.679172e-07
- gpu_vs_cpu rmse: 1.477458e-08
- reference max_abs: 2.980232e-08
- reference max_rel: 6.071463e-07

## Performance

- cpu median_ms: 0.327
- cpu mean_ms: 0.327
- cpu p95_ms: 0.327
- gpu_e2e median_ms: 0.144
- gpu_e2e mean_ms: 0.144
- gpu_e2e p95_ms: 0.144
- gpu_e2e speedup: 2.266x
- gpu_kernel median_ms: 0.053
- gpu_kernel speedup: 6.201x
- device_cache allocations: 6 calls, 2.000 MiB
- device_cache hits/misses: 8/6
- device_cache recycled: 13 blocks, 10.000 MiB

## Cases

- boundary_vector: pass, max_abs=2.980232e-08
- matrix_dense: pass, max_abs=2.980232e-08
- perf_large_vector: pass, max_abs=5.960464e-08
