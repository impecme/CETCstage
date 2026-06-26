# radartools/pulse_compression Summary

- generated_at: 2026-06-26 09:58:34
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 7.836141e-06
- gpu_vs_cpu max_rel: 1.851013e+22
- gpu_vs_cpu rmse: 1.787594e-06
- reference max_abs: 1.066240e-06
- reference max_rel: 1.851013e+22

## Performance

- cpu median_ms: 90.931
- cpu mean_ms: 90.931
- cpu p95_ms: 90.931
- gpu_e2e median_ms: 1.677
- gpu_e2e mean_ms: 1.677
- gpu_e2e p95_ms: 1.677
- gpu_e2e speedup: 54.209x
- gpu_kernel median_ms: 1.661
- gpu_kernel speedup: 54.744x
- device_cache allocations: 8 calls, 16.003 MiB
- device_cache hits/misses: 70/8
- device_cache recycled: 76 blocks, 576.002 MiB

## Cases

- basic: pass, max_abs=1.066240e-06
- normalize_boxcar_nfft16: pass, max_abs=2.546311e-07
- perf_large: pass, max_abs=7.836141e-06
