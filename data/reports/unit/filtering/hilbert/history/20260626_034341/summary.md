# filtering/hilbert Summary

- generated_at: 2026-06-26 03:43:41
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.554942e-06
- gpu_vs_cpu max_rel: 2.825295e-06
- gpu_vs_cpu rmse: 3.692687e-07
- reference max_abs: 5.960464e-08
- reference max_rel: 5.960464e-08

## Performance

- cpu median_ms: 125.951
- cpu mean_ms: 125.951
- cpu p95_ms: 125.951
- gpu_e2e median_ms: 2.977
- gpu_e2e mean_ms: 2.977
- gpu_e2e p95_ms: 2.977
- gpu_e2e speedup: 42.311x
- gpu_kernel median_ms: 2.823
- gpu_kernel speedup: 44.609x
- device_cache allocations: 6 calls, 20.000 MiB
- device_cache hits/misses: 8/6
- device_cache recycled: 12 blocks, 76.000 MiB

## Cases

- analytic_1d: pass, max_abs=2.980232e-07
- perf_1d: pass, max_abs=1.554942e-06
