# filtering/detrend Summary

- generated_at: 2026-06-26 04:30:10
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 5.131942e-06
- gpu_vs_cpu rmse: 3.080060e-10
- reference max_abs: 1.048669e-06
- reference max_rel: 4.230430e-05

## Performance

- cpu median_ms: 5.557
- cpu mean_ms: 5.557
- cpu p95_ms: 5.557
- gpu_e2e median_ms: 1.092
- gpu_e2e mean_ms: 1.092
- gpu_e2e p95_ms: 1.092
- gpu_e2e speedup: 5.088x
- gpu_kernel median_ms: 0.945
- gpu_kernel speedup: 5.883x
- device_cache allocations: 4 calls, 8.000 MiB
- device_cache hits/misses: 8/4
- device_cache recycled: 11 blocks, 40.000 MiB

## Cases

- linear_bp: pass, max_abs=0.000000e+00
- perf_linear: pass, max_abs=1.192093e-07
