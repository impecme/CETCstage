# filter_design/firwin2 Summary

- generated_at: 2026-06-26 03:43:13
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 6.025657e-07
- gpu_vs_cpu max_rel: 2.855665e+00
- gpu_vs_cpu rmse: 5.275668e-08
- reference max_abs: 4.842877e-08
- reference max_rel: 8.448581e+05

## Performance

- cpu median_ms: 0.252
- cpu mean_ms: 0.252
- cpu p95_ms: 0.252
- gpu_e2e median_ms: 0.109
- gpu_e2e mean_ms: 0.109
- gpu_e2e p95_ms: 0.109
- gpu_e2e speedup: 2.314x
- gpu_kernel median_ms: 0.020
- gpu_kernel speedup: 12.747x
- device_cache allocations: 12 calls, 0.016 MiB
- device_cache hits/misses: 8/12
- device_cache recycled: 17 blocks, 0.036 MiB

## Cases

- type1_lowpass: pass, max_abs=2.980232e-08
- type3_antisymmetric: pass, max_abs=5.960464e-08
- perf_multiband_large: pass, max_abs=6.025657e-07
