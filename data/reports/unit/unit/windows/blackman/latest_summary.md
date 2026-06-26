# windows/blackman Summary

- generated_at: 2026-06-26 03:50:17
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.788139e-07
- gpu_vs_cpu max_rel: 1.666666e-01
- gpu_vs_cpu rmse: 4.371050e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 1.073742e+09

## Performance

- cpu median_ms: 0.213
- cpu mean_ms: 0.213
- cpu p95_ms: 0.213
- gpu_e2e median_ms: 0.082
- gpu_e2e mean_ms: 0.082
- gpu_e2e p95_ms: 0.082
- gpu_e2e speedup: 2.609x
- gpu_kernel median_ms: 0.033
- gpu_kernel speedup: 6.457x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 0.563 MiB

## Cases

- sym_small: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=1.788139e-07
