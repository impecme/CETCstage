# filtering/hilbert Summary

- generated_at: 2026-06-26 12:21:23
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

- cpu median_ms: 122.812
- cpu mean_ms: 122.812
- cpu p95_ms: 122.812
- gpu_e2e median_ms: 2.893
- gpu_e2e mean_ms: 2.893
- gpu_e2e p95_ms: 2.893
- gpu_e2e speedup: 42.448x
- gpu_kernel median_ms: 2.832
- gpu_kernel speedup: 43.372x
- device_cache allocations: 6 calls, 20.000 MiB
- device_cache hits/misses: 70/6
- device_cache recycled: 74 blocks, 572.000 MiB

## Cases

- analytic_1d: pass, max_abs=2.980232e-07
- perf_1d: pass, max_abs=1.554942e-06
