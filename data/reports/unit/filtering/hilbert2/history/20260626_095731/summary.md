# filtering/hilbert2 Summary

- generated_at: 2026-06-26 09:57:31
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

- cpu median_ms: 104.045
- cpu mean_ms: 104.045
- cpu p95_ms: 104.045
- gpu_e2e median_ms: 3.695
- gpu_e2e mean_ms: 3.695
- gpu_e2e p95_ms: 3.695
- gpu_e2e speedup: 28.158x
- gpu_kernel median_ms: 3.639
- gpu_kernel speedup: 28.595x
- device_cache allocations: 6 calls, 20.000 MiB
- device_cache hits/misses: 70/6
- device_cache recycled: 74 blocks, 572.000 MiB

## Cases

- analytic_2d: pass, max_abs=1.228781e-07
- perf_2d: pass, max_abs=1.409558e-06
