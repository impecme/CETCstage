# radartools/ambgfun Summary

- generated_at: 2026-06-26 04:31:59
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

- cpu median_ms: 8392.955
- cpu mean_ms: 8392.955
- cpu p95_ms: 8392.955
- gpu_e2e median_ms: 167.926
- gpu_e2e mean_ms: 167.926
- gpu_e2e p95_ms: 167.926
- gpu_e2e speedup: 49.980x
- gpu_kernel median_ms: 167.329
- gpu_kernel speedup: 50.159x
- device_cache allocations: 18 calls, 9215.691 MiB
- device_cache hits/misses: 20/18
- device_cache recycled: 27 blocks, 1.133 MiB

## Cases

- surface_auto: pass, max_abs=1.192093e-07
- delay_cross: pass, max_abs=2.980232e-07
- doppler_auto: pass, max_abs=3.725290e-07
- perf_surface: pass, max_abs=2.980232e-07
