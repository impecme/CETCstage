# filtering/resample_poly Summary

- generated_at: 2026-06-26 12:22:28
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

- cpu median_ms: 246.855
- cpu mean_ms: 246.855
- cpu p95_ms: 246.855
- gpu_e2e median_ms: 5.461
- gpu_e2e mean_ms: 5.461
- gpu_e2e p95_ms: 5.461
- gpu_e2e speedup: 45.204x
- gpu_kernel median_ms: 5.434
- gpu_kernel speedup: 45.424x
- device_cache allocations: 11 calls, 14.669 MiB
- device_cache hits/misses: 141/11
- device_cache recycled: 149 blocks, 761.342 MiB

## Cases

- up3_down2: pass, max_abs=1.192093e-07
- perf_up4_down3: pass, max_abs=3.576279e-07
