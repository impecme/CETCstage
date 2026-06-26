# filtering/channelize_poly Summary

- generated_at: 2026-06-26 09:57:52
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.264405e-06
- gpu_vs_cpu max_rel: 1.051719e-03
- gpu_vs_cpu rmse: 3.378300e-07
- reference max_abs: 6.143906e-08
- reference max_rel: 2.042958e-07

## Performance

- cpu median_ms: 355.013
- cpu mean_ms: 355.013
- cpu p95_ms: 355.013
- gpu_e2e median_ms: 26.638
- gpu_e2e mean_ms: 26.638
- gpu_e2e p95_ms: 26.638
- gpu_e2e speedup: 13.327x
- gpu_kernel median_ms: 26.425
- gpu_kernel speedup: 13.435x
- device_cache allocations: 8 calls, 16.001 MiB
- device_cache hits/misses: 70/8
- device_cache recycled: 75 blocks, 576.001 MiB

## Cases

- channels_4: pass, max_abs=7.028864e-08
- perf_channels_8: pass, max_abs=1.264405e-06
