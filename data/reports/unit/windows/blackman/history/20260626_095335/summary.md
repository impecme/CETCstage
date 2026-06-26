# windows/blackman Summary

- generated_at: 2026-06-26 09:53:35
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
- gpu_e2e median_ms: 0.078
- gpu_e2e mean_ms: 0.078
- gpu_e2e p95_ms: 0.078
- gpu_e2e speedup: 2.717x
- gpu_kernel median_ms: 0.033
- gpu_kernel speedup: 6.439x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4.438 MiB

## Cases

- sym_small: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=1.788139e-07
