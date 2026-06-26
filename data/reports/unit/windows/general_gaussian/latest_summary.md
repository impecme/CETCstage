# windows/general_gaussian Summary

- generated_at: 2026-06-26 12:18:27
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 1.526352e-05
- gpu_vs_cpu rmse: 2.508244e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 1.084783e-06

## Performance

- cpu median_ms: 592.775
- cpu mean_ms: 592.775
- cpu p95_ms: 592.775
- gpu_e2e median_ms: 1.895
- gpu_e2e mean_ms: 1.895
- gpu_e2e p95_ms: 1.895
- gpu_e2e speedup: 312.733x
- gpu_kernel median_ms: 1.838
- gpu_kernel speedup: 322.585x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4544.000 MiB

## Cases

- shape_pair: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=1.192093e-07
