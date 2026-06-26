# spectral/welch Summary

- generated_at: 2026-06-26 03:46:01
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 3.725290e-09
- gpu_vs_cpu max_rel: 3.905944e-01
- gpu_vs_cpu rmse: 4.658885e-10
- reference max_abs: 7.450581e-09
- reference max_rel: 5.933893e-01

## Performance

- cpu median_ms: 2.729
- cpu mean_ms: 2.729
- cpu p95_ms: 2.729
- gpu_e2e median_ms: 2.043
- gpu_e2e mean_ms: 2.043
- gpu_e2e p95_ms: 2.043
- gpu_e2e speedup: 1.336x
- gpu_kernel median_ms: 1.647
- gpu_kernel speedup: 1.656x
- device_cache allocations: 7 calls, 0.129 MiB
- device_cache hits/misses: 25/7
- device_cache recycled: 31 blocks, 0.029 MiB

## Cases

- mean_hann: pass, max_abs=3.725290e-09
- perf_mean_hann: pass, max_abs=2.793968e-09
