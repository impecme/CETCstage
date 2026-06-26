# windows/flattop Summary

- generated_at: 2026-06-26 03:50:22
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 2.682209e-07
- gpu_vs_cpu max_rel: 8.431189e-04
- gpu_vs_cpu rmse: 5.497513e-08
- reference max_abs: 7.450581e-08
- reference max_rel: 7.879893e-06

## Performance

- cpu median_ms: 0.373
- cpu mean_ms: 0.373
- cpu p95_ms: 0.373
- gpu_e2e median_ms: 0.083
- gpu_e2e mean_ms: 0.083
- gpu_e2e p95_ms: 0.083
- gpu_e2e speedup: 4.471x
- gpu_kernel median_ms: 0.037
- gpu_kernel speedup: 10.118x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 0.563 MiB

## Cases

- sym_small: pass, max_abs=8.195639e-08
- perf_large: pass, max_abs=2.682209e-07
