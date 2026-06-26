# radartools/mvdr Summary

- generated_at: 2026-06-26 10:04:10
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.489229e-04
- gpu_vs_cpu max_rel: 2.629748e-04
- gpu_vs_cpu rmse: 1.072363e-04
- reference max_abs: 4.326910e-04
- reference max_rel: 6.284157e-05

## Performance

- cpu median_ms: 21.180
- cpu mean_ms: 21.180
- cpu p95_ms: 21.180
- gpu_e2e median_ms: 11.159
- gpu_e2e mean_ms: 11.159
- gpu_e2e p95_ms: 11.159
- gpu_e2e speedup: 1.898x
- gpu_kernel median_ms: 0.847
- gpu_kernel speedup: 24.998x
- device_cache allocations: 5 calls, 8.001 MiB
- device_cache hits/misses: 72/5
- device_cache recycled: 75 blocks, 0.005 MiB

## Cases

- calc_cov_true: pass, max_abs=1.489229e-04
- covariance_input: pass, max_abs=3.071953e-08
- perf_calc_cov: pass, max_abs=7.963751e-05
