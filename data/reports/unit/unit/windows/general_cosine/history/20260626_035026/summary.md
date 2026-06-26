# windows/general_cosine Summary

- generated_at: 2026-06-26 03:50:26
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 3.576279e-07
- gpu_vs_cpu max_rel: 1.717250e+02
- gpu_vs_cpu rmse: 4.702744e-08
- reference max_abs: 1.490116e-07
- reference max_rel: 1.382762e-06

## Performance

- cpu median_ms: 404.081
- cpu mean_ms: 404.081
- cpu p95_ms: 404.081
- gpu_e2e median_ms: 5.703
- gpu_e2e mean_ms: 5.703
- gpu_e2e p95_ms: 5.703
- gpu_e2e speedup: 70.856x
- gpu_kernel median_ms: 5.622
- gpu_kernel speedup: 71.872x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 576.000 MiB

## Cases

- custom_coeff: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=3.576279e-07
