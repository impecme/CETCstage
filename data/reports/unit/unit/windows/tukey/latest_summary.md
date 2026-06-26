# windows/tukey Summary

- generated_at: 2026-06-26 03:50:53
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 5.960464e-08
- gpu_vs_cpu max_rel: 5.539859e-06
- gpu_vs_cpu rmse: 8.893399e-09
- reference max_abs: 4.768372e-07
- reference max_rel: 8.987079e-07

## Performance

- cpu median_ms: 0.082
- cpu mean_ms: 0.082
- cpu p95_ms: 0.082
- gpu_e2e median_ms: 0.161
- gpu_e2e mean_ms: 0.161
- gpu_e2e p95_ms: 0.161
- gpu_e2e speedup: 0.508x
- gpu_kernel median_ms: 0.107
- gpu_kernel speedup: 0.768x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 0.563 MiB

## Cases

- alpha_035: pass, max_abs=0.000000e+00
- perf_large: pass, max_abs=5.960464e-08
