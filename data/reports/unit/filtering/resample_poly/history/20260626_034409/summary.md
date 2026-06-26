# filtering/resample_poly Summary

- generated_at: 2026-06-26 03:44:09
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

- cpu median_ms: 244.099
- cpu mean_ms: 244.099
- cpu p95_ms: 244.099
- gpu_e2e median_ms: 5.516
- gpu_e2e mean_ms: 5.516
- gpu_e2e p95_ms: 5.516
- gpu_e2e speedup: 44.250x
- gpu_kernel median_ms: 5.440
- gpu_kernel speedup: 44.875x
- device_cache allocations: 11 calls, 14.669 MiB
- device_cache hits/misses: 17/11
- device_cache recycled: 25 blocks, 100.002 MiB

## Cases

- up3_down2: pass, max_abs=1.192093e-07
- perf_up4_down3: pass, max_abs=3.576279e-07
