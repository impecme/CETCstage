# radartools/mvdr Summary

- generated_at: 2026-06-26 03:45:33
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 3.404061e-04
- gpu_vs_cpu max_rel: 1.337076e-04
- gpu_vs_cpu rmse: 2.374302e-04
- reference max_abs: 6.083366e-04
- reference max_rel: 1.465885e-04

## Performance

- cpu median_ms: 21.227
- cpu mean_ms: 21.227
- cpu p95_ms: 21.227
- gpu_e2e median_ms: 52.527
- gpu_e2e mean_ms: 52.527
- gpu_e2e p95_ms: 52.527
- gpu_e2e speedup: 0.404x
- gpu_kernel median_ms: 42.298
- gpu_kernel speedup: 0.502x
- device_cache allocations: 5 calls, 8.001 MiB
- device_cache hits/misses: 10/5
- device_cache recycled: 13 blocks, 0.001 MiB

## Cases

- calc_cov_true: pass, max_abs=3.404061e-04
- covariance_input: pass, max_abs=3.071953e-08
- perf_calc_cov: pass, max_abs=3.936433e-05
