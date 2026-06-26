# filtering/wiener Summary

- generated_at: 2026-06-26 12:21:09
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

- cpu median_ms: 676.707
- cpu mean_ms: 676.707
- cpu p95_ms: 676.707
- gpu_e2e median_ms: 3.480
- gpu_e2e mean_ms: 3.480
- gpu_e2e p95_ms: 3.480
- gpu_e2e speedup: 194.458x
- gpu_kernel median_ms: 3.343
- gpu_kernel speedup: 202.418x
- device_cache allocations: 8 calls, 16.000 MiB
- device_cache hits/misses: 70/8
- device_cache recycled: 75 blocks, 288.000 MiB

## Cases

- image_2d_default_noise: pass, max_abs=5.960464e-08
- perf_image_large: pass, max_abs=7.748604e-07
