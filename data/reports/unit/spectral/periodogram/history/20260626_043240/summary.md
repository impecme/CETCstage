# spectral/periodogram Summary

- generated_at: 2026-06-26 04:32:40
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.907349e-06
- gpu_vs_cpu max_rel: 4.104759e+02
- gpu_vs_cpu rmse: 1.491096e-08
- reference max_abs: 3.725290e-08
- reference max_rel: 3.775551e+00

## Performance

- cpu median_ms: 1.413
- cpu mean_ms: 1.413
- cpu p95_ms: 1.413
- gpu_e2e median_ms: 72.892
- gpu_e2e mean_ms: 72.892
- gpu_e2e p95_ms: 72.892
- gpu_e2e speedup: 0.019x
- gpu_kernel median_ms: 72.378
- gpu_kernel speedup: 0.020x
- device_cache allocations: 8 calls, 0.378 MiB
- device_cache hits/misses: 24/8
- device_cache recycled: 31 blocks, 2.253 MiB

## Cases

- hann_density: pass, max_abs=1.117587e-08
- perf_hann_density: pass, max_abs=1.907349e-06
