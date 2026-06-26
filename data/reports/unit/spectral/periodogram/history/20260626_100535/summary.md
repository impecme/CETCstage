# spectral/periodogram Summary

- generated_at: 2026-06-26 10:05:35
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.907349e-06
- gpu_vs_cpu max_rel: 3.675537e+03
- gpu_vs_cpu rmse: 1.491096e-08
- reference max_abs: 3.725290e-08
- reference max_rel: 3.775551e+00

## Performance

- cpu median_ms: 1.466
- cpu mean_ms: 1.466
- cpu p95_ms: 1.466
- gpu_e2e median_ms: 0.655
- gpu_e2e mean_ms: 0.655
- gpu_e2e p95_ms: 0.655
- gpu_e2e speedup: 2.239x
- gpu_kernel median_ms: 0.193
- gpu_kernel speedup: 7.598x
- device_cache allocations: 8 calls, 0.378 MiB
- device_cache hits/misses: 210/8
- device_cache recycled: 217 blocks, 17.753 MiB

## Cases

- hann_density: pass, max_abs=1.117587e-08
- perf_hann_density: pass, max_abs=1.907349e-06
