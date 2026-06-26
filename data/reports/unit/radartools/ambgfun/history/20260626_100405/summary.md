# radartools/ambgfun Summary

- generated_at: 2026-06-26 10:04:05
- pass: true
- accuracy_cases: 3
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 3.725290e-07
- gpu_vs_cpu max_rel: 1.811450e+22
- gpu_vs_cpu rmse: 1.587030e-07
- reference max_abs: 3.725290e-07
- reference max_rel: 6.337249e+00

## Performance

- cpu median_ms: 8140.689
- cpu mean_ms: 8140.689
- cpu p95_ms: 8140.689
- gpu_e2e median_ms: 167.864
- gpu_e2e mean_ms: 167.864
- gpu_e2e p95_ms: 167.864
- gpu_e2e speedup: 48.496x
- gpu_kernel median_ms: 167.327
- gpu_kernel speedup: 48.651x
- device_cache allocations: 80 calls, 72699.820 MiB
- device_cache hits/misses: 144/80
- device_cache recycled: 151 blocks, 8.883 MiB

## Cases

- surface_auto: pass, max_abs=1.192093e-07
- delay_cross: pass, max_abs=2.980232e-07
- doppler_auto: pass, max_abs=3.725290e-07
- perf_surface: pass, max_abs=2.980232e-07
