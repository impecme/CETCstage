# spectral/lombscargle Summary

- generated_at: 2026-06-26 12:29:56
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.768372e-06
- gpu_vs_cpu max_rel: 1.087981e-03
- gpu_vs_cpu rmse: 5.311925e-07
- reference max_abs: 3.814697e-06
- reference max_rel: 2.342106e-04

## Performance

- cpu median_ms: 2149.662
- cpu mean_ms: 2149.662
- cpu p95_ms: 2149.662
- gpu_e2e median_ms: 12.516
- gpu_e2e mean_ms: 12.516
- gpu_e2e p95_ms: 12.516
- gpu_e2e speedup: 171.752x
- gpu_kernel median_ms: 12.292
- gpu_kernel speedup: 174.888x
- device_cache allocations: 8 calls, 0.189 MiB
- device_cache hits/misses: 70/8
- device_cache recycled: 75 blocks, 4.439 MiB

## Cases

- normalized_precentered: pass, max_abs=3.784895e-06
- perf_large: pass, max_abs=4.768372e-06
