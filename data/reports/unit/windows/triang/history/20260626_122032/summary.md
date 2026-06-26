# windows/triang Summary

- generated_at: 2026-06-26 12:20:32
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 1.192093e-07
- gpu_vs_cpu rmse: 4.362614e-08
- reference max_abs: 0.000000e+00
- reference max_rel: 0.000000e+00

## Performance

- cpu median_ms: 59.099
- cpu mean_ms: 59.099
- cpu p95_ms: 59.099
- gpu_e2e median_ms: 1.072
- gpu_e2e mean_ms: 1.072
- gpu_e2e p95_ms: 1.072
- gpu_e2e speedup: 55.126x
- gpu_kernel median_ms: 1.020
- gpu_kernel speedup: 57.924x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4544.000 MiB

## Cases

- periodic_small: pass, max_abs=0.000000e+00
- perf_large: pass, max_abs=1.192093e-07
