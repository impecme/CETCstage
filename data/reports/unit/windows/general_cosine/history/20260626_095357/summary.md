# windows/general_cosine Summary

- generated_at: 2026-06-26 09:53:57
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

- cpu median_ms: 399.360
- cpu mean_ms: 399.360
- cpu p95_ms: 399.360
- gpu_e2e median_ms: 5.674
- gpu_e2e mean_ms: 5.674
- gpu_e2e p95_ms: 5.674
- gpu_e2e speedup: 70.379x
- gpu_kernel median_ms: 5.616
- gpu_kernel speedup: 71.115x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4544.000 MiB

## Cases

- custom_coeff: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=3.576279e-07
