# filtering/lfilter_zi Summary

- generated_at: 2026-06-26 04:29:43
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 0.000000e+00
- gpu_vs_cpu max_rel: 0.000000e+00
- gpu_vs_cpu rmse: 0.000000e+00
- reference max_abs: 2.980232e-08
- reference max_rel: 8.984524e-08

## Performance

- cpu median_ms: 15.722
- cpu mean_ms: 15.722
- cpu p95_ms: 15.722
- gpu_e2e median_ms: 0.485
- gpu_e2e mean_ms: 0.485
- gpu_e2e p95_ms: 0.485
- gpu_e2e speedup: 32.439x
- gpu_kernel median_ms: 0.266
- gpu_kernel speedup: 59.149x
- device_cache allocations: 8 calls, 0.008 MiB
- device_cache hits/misses: 16/8
- device_cache recycled: 22 blocks, 0.035 MiB

## Cases

- stable_iir: pass, max_abs=0.000000e+00
- perf_stable_iir: pass, max_abs=0.000000e+00
