# wavelets/morlet Summary

- generated_at: 2026-06-26 04:34:36
- pass: true
- accuracy_cases: 5
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 9.775889e-07
- gpu_vs_cpu max_rel: 5.653906e-06
- gpu_vs_cpu rmse: 2.019176e-07
- reference max_abs: 1.464873e-07
- reference max_rel: 1.215373e-05

## Performance

- cpu median_ms: 529.095
- cpu mean_ms: 529.095
- cpu p95_ms: 529.095
- gpu_e2e median_ms: 5.571
- gpu_e2e mean_ms: 5.571
- gpu_e2e p95_ms: 5.571
- gpu_e2e speedup: 94.973x
- gpu_kernel median_ms: 5.483
- gpu_kernel speedup: 96.497x
- device_cache allocations: 3 calls, 128.000 MiB
- device_cache hits/misses: 9/3
- device_cache recycled: 12 blocks, 1152.000 MiB

## Cases

- complete_default: pass, max_abs=5.960464e-08
- standard_custom: pass, max_abs=1.877141e-09
- point_center: pass, max_abs=0.000000e+00
- zero_points: pass, max_abs=0.000000e+00
- invalid_s: pass, max_abs=0.000000e+00
- perf_complete_large: pass, max_abs=9.775889e-07
