# filtering/resample_poly Summary

- generated_at: 2026-06-26 04:30:24
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 3.576279e-07
- gpu_vs_cpu max_rel: 1.163396e-03
- gpu_vs_cpu rmse: 9.702349e-08
- reference max_abs: 1.788139e-07
- reference max_rel: 3.104676e+07

## Performance

- cpu median_ms: 245.837
- cpu mean_ms: 245.837
- cpu p95_ms: 245.837
- gpu_e2e median_ms: 5.515
- gpu_e2e mean_ms: 5.515
- gpu_e2e p95_ms: 5.515
- gpu_e2e speedup: 44.572x
- gpu_kernel median_ms: 5.443
- gpu_kernel speedup: 45.167x
- device_cache allocations: 11 calls, 14.669 MiB
- device_cache hits/misses: 17/11
- device_cache recycled: 25 blocks, 100.002 MiB

## Cases

- up3_down2: pass, max_abs=1.192093e-07
- perf_up4_down3: pass, max_abs=3.576279e-07
