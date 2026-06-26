# windows/parzen Summary

- generated_at: 2026-06-26 12:20:07
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

- cpu median_ms: 60.782
- cpu mean_ms: 60.782
- cpu p95_ms: 60.782
- gpu_e2e median_ms: 1.503
- gpu_e2e mean_ms: 1.503
- gpu_e2e p95_ms: 1.503
- gpu_e2e speedup: 40.448x
- gpu_kernel median_ms: 1.415
- gpu_kernel speedup: 42.961x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4544.000 MiB

## Cases

- sym_small: pass, max_abs=7.450581e-09
- perf_large: pass, max_abs=5.960464e-08
