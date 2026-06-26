# radartools/ca_cfar Summary

- generated_at: 2026-06-26 10:04:07
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

- cpu median_ms: 8.594
- cpu mean_ms: 8.594
- cpu p95_ms: 8.594
- gpu_e2e median_ms: 2.175
- gpu_e2e mean_ms: 2.175
- gpu_e2e p95_ms: 2.175
- gpu_e2e speedup: 3.951x
- gpu_kernel median_ms: 1.875
- gpu_kernel speedup: 4.584x
- device_cache allocations: 9 calls, 12.009 MiB
- device_cache hits/misses: 140/9
- device_cache recycled: 148 blocks, 572.275 MiB

## Cases

- ones_1d: pass, max_abs=0.000000e+00
- spike_2d: pass, max_abs=0.000000e+00
- perf_2d: pass, max_abs=0.000000e+00
