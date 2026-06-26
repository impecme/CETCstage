# spectral/welch Summary

- generated_at: 2026-06-26 10:05:43
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 3.725290e-09
- gpu_vs_cpu max_rel: 3.905944e-01
- gpu_vs_cpu rmse: 4.658885e-10
- reference max_abs: 7.450581e-09
- reference max_rel: 5.933893e-01

## Performance

- cpu median_ms: 2.753
- cpu mean_ms: 2.753
- cpu p95_ms: 2.753
- gpu_e2e median_ms: 2.046
- gpu_e2e mean_ms: 2.046
- gpu_e2e p95_ms: 2.046
- gpu_e2e speedup: 1.346x
- gpu_kernel median_ms: 1.649
- gpu_kernel speedup: 1.669x
- device_cache allocations: 7 calls, 0.129 MiB
- device_cache hits/misses: 211/7
- device_cache recycled: 217 blocks, 0.211 MiB

## Cases

- mean_hann: pass, max_abs=3.725290e-09
- perf_mean_hann: pass, max_abs=2.793968e-09
