# windows/bohman Summary

- generated_at: 2026-06-26 09:53:35
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 5.555556e-02
- gpu_vs_cpu rmse: 2.225602e-08
- reference max_abs: 1.192093e-07
- reference max_rel: 3.268377e-06

## Performance

- cpu median_ms: 0.225
- cpu mean_ms: 0.225
- cpu p95_ms: 0.225
- gpu_e2e median_ms: 0.080
- gpu_e2e mean_ms: 0.080
- gpu_e2e p95_ms: 0.080
- gpu_e2e speedup: 2.804x
- gpu_kernel median_ms: 0.033
- gpu_kernel speedup: 6.766x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4.438 MiB

## Cases

- sym_small: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=1.192093e-07
