# filtering/filtfilt Summary

- generated_at: 2026-06-26 08:09:33
- pass: true
- accuracy_cases: 0
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.172325e-07
- gpu_vs_cpu max_rel: 4.854955e-05
- gpu_vs_cpu rmse: 6.523781e-08

## Performance

- cpu median_ms: 0.560
- cpu mean_ms: 0.560
- cpu p95_ms: 0.560
- gpu_e2e median_ms: 0.662
- gpu_e2e mean_ms: 0.662
- gpu_e2e p95_ms: 0.662
- gpu_e2e speedup: 0.846x
- gpu_kernel median_ms: 0.403
- gpu_kernel speedup: 1.389x
- device_cache allocations: 12 calls, 0.753 MiB
- device_cache hits/misses: 67/12
- device_cache recycled: 74 blocks, 7.878 MiB

## Cases

- perf_iir_pad: pass, max_abs=4.172325e-07
