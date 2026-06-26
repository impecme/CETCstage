# filtering/firfilter2 Summary

- generated_at: 2026-06-26 12:21:15
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 5.364418e-07
- gpu_vs_cpu max_rel: 1.000000e+00
- gpu_vs_cpu rmse: 6.422052e-08
- reference max_abs: 1.192093e-07
- reference max_rel: 1.952754e-07

## Performance

- cpu median_ms: 34.747
- cpu mean_ms: 34.747
- cpu p95_ms: 34.747
- gpu_e2e median_ms: 6.189
- gpu_e2e mean_ms: 6.189
- gpu_e2e p95_ms: 6.189
- gpu_e2e speedup: 5.614x
- gpu_kernel median_ms: 6.112
- gpu_kernel speedup: 5.685x
- device_cache allocations: 14 calls, 24.004 MiB
- device_cache hits/misses: 351/14
- device_cache recycled: 362 blocks, 1424.196 MiB

## Cases

- fir_pad: pass, max_abs=1.192093e-07
- perf_fir_pad: pass, max_abs=5.364418e-07
