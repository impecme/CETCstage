# filtering/wiener Summary

- generated_at: 2026-06-26 09:57:00
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 7.748604e-07
- gpu_vs_cpu max_rel: 9.755279e-07
- gpu_vs_cpu rmse: 2.980232e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 9.030185e-08

## Performance

- cpu median_ms: 669.926
- cpu mean_ms: 669.926
- cpu p95_ms: 669.926
- gpu_e2e median_ms: 3.569
- gpu_e2e mean_ms: 3.569
- gpu_e2e p95_ms: 3.569
- gpu_e2e speedup: 187.689x
- gpu_kernel median_ms: 3.384
- gpu_kernel speedup: 197.966x
- device_cache allocations: 8 calls, 16.000 MiB
- device_cache hits/misses: 70/8
- device_cache recycled: 75 blocks, 288.000 MiB

## Cases

- image_2d_default_noise: pass, max_abs=5.960464e-08
- perf_image_large: pass, max_abs=7.748604e-07
