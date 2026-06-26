# spectral/stft Summary

- generated_at: 2026-06-26 12:31:12
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 2.384477e-07
- gpu_vs_cpu max_rel: 1.209719e+23
- gpu_vs_cpu rmse: 2.191228e-08
- reference max_abs: 1.299205e-07
- reference max_rel: 1.876826e-01

## Performance

- cpu median_ms: 392.043
- cpu mean_ms: 392.043
- cpu p95_ms: 392.043
- gpu_e2e median_ms: 20.787
- gpu_e2e mean_ms: 20.787
- gpu_e2e p95_ms: 20.787
- gpu_e2e speedup: 18.860x
- gpu_kernel median_ms: 19.884
- gpu_kernel speedup: 19.716x
- device_cache allocations: 10 calls, 36.391 MiB
- device_cache hits/misses: 70/10
- device_cache recycled: 76 blocks, 2293.833 MiB

## Cases

- zeros_padded: pass, max_abs=1.248873e-07
- perf_zeros_padded: pass, max_abs=2.384477e-07
