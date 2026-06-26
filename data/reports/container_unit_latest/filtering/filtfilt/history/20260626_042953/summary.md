# filtering/filtfilt Summary

- generated_at: 2026-06-26 04:29:53
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 8.940697e-08
- gpu_vs_cpu max_rel: 1.967503e-07
- gpu_vs_cpu rmse: 1.416254e-09
- reference max_abs: 2.980232e-08
- reference max_rel: 2.051114e-07

## Performance

- cpu median_ms: 0.566
- cpu mean_ms: 0.566
- cpu p95_ms: 0.566
- gpu_e2e median_ms: 910.461
- gpu_e2e mean_ms: 910.461
- gpu_e2e p95_ms: 910.461
- gpu_e2e speedup: 0.001x
- gpu_kernel median_ms: 910.236
- gpu_kernel speedup: 0.001x
- device_cache allocations: 9 calls, 0.750 MiB
- device_cache hits/misses: 49/9
- device_cache recycled: 55 blocks, 5.627 MiB

## Cases

- iir_gust: pass, max_abs=0.000000e+00
- perf_iir_pad: pass, max_abs=8.940697e-08
