# wavelets/ricker Summary

- generated_at: 2026-06-26 04:34:39
- pass: true
- accuracy_cases: 3
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 2.980232e-08
- gpu_vs_cpu max_rel: 2.541462e-07
- gpu_vs_cpu rmse: 2.107342e-08
- reference max_abs: 2.980232e-08
- reference max_rel: 1.693439e-07

## Performance

- cpu median_ms: 367.624
- cpu mean_ms: 367.624
- cpu p95_ms: 367.624
- gpu_e2e median_ms: 29.524
- gpu_e2e mean_ms: 29.524
- gpu_e2e p95_ms: 29.524
- gpu_e2e speedup: 12.452x
- gpu_kernel median_ms: 29.409
- gpu_kernel speedup: 12.500x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 9/2
- device_cache recycled: 11 blocks, 576.000 MiB

## Cases

- width4_points17: pass, max_abs=2.980232e-08
- width10_point1: pass, max_abs=0.000000e+00
- invalid_a: pass, max_abs=0.000000e+00
- perf_large: pass, max_abs=2.980232e-08
