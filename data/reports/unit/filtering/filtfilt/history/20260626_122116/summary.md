# filtering/filtfilt Summary

- generated_at: 2026-06-26 12:21:16
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.172325e-07
- gpu_vs_cpu max_rel: 4.854955e-05
- gpu_vs_cpu rmse: 6.523781e-08
- reference max_abs: 2.980232e-08
- reference max_rel: 2.051114e-07

## Performance

- cpu median_ms: 0.561
- cpu mean_ms: 0.561
- cpu p95_ms: 0.561
- gpu_e2e median_ms: 0.655
- gpu_e2e mean_ms: 0.655
- gpu_e2e p95_ms: 0.655
- gpu_e2e speedup: 0.856x
- gpu_kernel median_ms: 0.403
- gpu_kernel speedup: 1.393x
- device_cache allocations: 11 calls, 0.753 MiB
- device_cache hits/misses: 565/11
- device_cache recycled: 571 blocks, 62.149 MiB

## Cases

- iir_gust: pass, max_abs=0.000000e+00
- perf_iir_pad: pass, max_abs=4.172325e-07
