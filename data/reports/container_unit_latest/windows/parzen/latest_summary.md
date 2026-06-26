# windows/parzen Summary

- generated_at: 2026-06-26 04:38:05
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 5.960464e-08
- gpu_vs_cpu max_rel: 2.378360e-07
- gpu_vs_cpu rmse: 1.870853e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 2.273462e-07

## Performance

- cpu median_ms: 62.417
- cpu mean_ms: 62.417
- cpu p95_ms: 62.417
- gpu_e2e median_ms: 1.480
- gpu_e2e mean_ms: 1.480
- gpu_e2e p95_ms: 1.480
- gpu_e2e speedup: 42.178x
- gpu_kernel median_ms: 1.413
- gpu_kernel speedup: 44.168x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 576.000 MiB

## Cases

- sym_small: pass, max_abs=7.450581e-09
- perf_large: pass, max_abs=5.960464e-08
