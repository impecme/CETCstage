# spectral/stft Summary

- generated_at: 2026-06-26 02:42:09
- pass: true
- accuracy_cases: 0
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.609406e-07
- gpu_vs_cpu max_rel: 1.209719e+23
- gpu_vs_cpu rmse: 1.715154e-08

## Performance

- cpu median_ms: 10.950
- cpu mean_ms: 10.950
- cpu p95_ms: 10.950
- gpu_e2e median_ms: 0.847
- gpu_e2e mean_ms: 0.847
- gpu_e2e p95_ms: 0.847
- gpu_e2e speedup: 12.923x
- gpu_kernel median_ms: 0.664
- gpu_kernel speedup: 16.495x
- device_cache allocations: 5 calls, 1.139 MiB
- device_cache hits/misses: 8/5
- device_cache recycled: 10 blocks, 9.204 MiB

## Cases

- perf_zeros_padded: pass, max_abs=1.609406e-07
