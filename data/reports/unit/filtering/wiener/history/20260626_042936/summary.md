# filtering/wiener Summary

- generated_at: 2026-06-26 04:29:36
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

- cpu median_ms: 696.148
- cpu mean_ms: 696.148
- cpu p95_ms: 696.148
- gpu_e2e median_ms: 3.528
- gpu_e2e mean_ms: 3.528
- gpu_e2e p95_ms: 3.528
- gpu_e2e speedup: 197.325x
- gpu_kernel median_ms: 3.359
- gpu_kernel speedup: 207.221x
- device_cache allocations: 8 calls, 16.000 MiB
- device_cache hits/misses: 8/8
- device_cache recycled: 13 blocks, 40.000 MiB

## Cases

- image_2d_default_noise: pass, max_abs=5.960464e-08
- perf_image_large: pass, max_abs=7.748604e-07
