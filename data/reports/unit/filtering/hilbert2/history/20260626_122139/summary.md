# filtering/hilbert2 Summary

- generated_at: 2026-06-26 12:21:39
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.409558e-06
- gpu_vs_cpu max_rel: 1.713465e-05
- gpu_vs_cpu rmse: 3.663172e-07
- reference max_abs: 1.228781e-07
- reference max_rel: 1.125241e-07

## Performance

- cpu median_ms: 90.037
- cpu mean_ms: 90.037
- cpu p95_ms: 90.037
- gpu_e2e median_ms: 3.732
- gpu_e2e mean_ms: 3.732
- gpu_e2e p95_ms: 3.732
- gpu_e2e speedup: 24.124x
- gpu_kernel median_ms: 3.634
- gpu_kernel speedup: 24.778x
- device_cache allocations: 6 calls, 20.000 MiB
- device_cache hits/misses: 70/6
- device_cache recycled: 74 blocks, 572.000 MiB

## Cases

- analytic_2d: pass, max_abs=1.228781e-07
- perf_2d: pass, max_abs=1.409558e-06
