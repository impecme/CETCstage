# radartools/ca_cfar Summary

- generated_at: 2026-06-26 04:32:01
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 0.000000e+00
- gpu_vs_cpu max_rel: 0.000000e+00
- gpu_vs_cpu rmse: 0.000000e+00
- reference max_abs: 3.051758e-05
- reference max_rel: 1.618951e-07

## Performance

- cpu median_ms: 8.773
- cpu mean_ms: 8.773
- cpu p95_ms: 8.773
- gpu_e2e median_ms: 2.086
- gpu_e2e mean_ms: 2.086
- gpu_e2e p95_ms: 2.086
- gpu_e2e speedup: 4.205x
- gpu_kernel median_ms: 1.857
- gpu_kernel speedup: 4.723x
- device_cache allocations: 9 calls, 12.009 MiB
- device_cache hits/misses: 16/9
- device_cache recycled: 24 blocks, 76.039 MiB

## Cases

- ones_1d: pass, max_abs=0.000000e+00
- spike_2d: pass, max_abs=0.000000e+00
- perf_2d: pass, max_abs=0.000000e+00
