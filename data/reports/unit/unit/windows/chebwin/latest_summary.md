# windows/chebwin Summary

- generated_at: 2026-06-26 03:50:21
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 6.303191e-05
- gpu_vs_cpu max_rel: 4.020537e-03
- gpu_vs_cpu rmse: 1.638754e-05
- reference max_abs: 7.320195e-07
- reference max_rel: 4.334624e-05

## Performance

- cpu median_ms: 0.167
- cpu mean_ms: 0.167
- cpu p95_ms: 0.167
- gpu_e2e median_ms: 0.070
- gpu_e2e mean_ms: 0.070
- gpu_e2e p95_ms: 0.070
- gpu_e2e speedup: 2.374x
- gpu_kernel median_ms: 0.019
- gpu_kernel speedup: 8.947x
- device_cache allocations: 2 calls, 0.006 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 0.053 MiB

## Cases

- sym_80db: pass, max_abs=5.662441e-07
- perf_large: pass, max_abs=6.303191e-05
