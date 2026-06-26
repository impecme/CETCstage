# filtering/firfilter2 Summary

- generated_at: 2026-06-26 00:39:28
- pass: true
- accuracy_cases: 0
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.172325e-07
- gpu_vs_cpu max_rel: 2.789343e-04
- gpu_vs_cpu rmse: 6.452495e-08

## Performance

- cpu median_ms: 1.012
- cpu mean_ms: 1.012
- cpu p95_ms: 1.012
- gpu_e2e median_ms: 0.354
- gpu_e2e mean_ms: 0.354
- gpu_e2e p95_ms: 0.354
- gpu_e2e speedup: 2.863x
- gpu_kernel median_ms: 0.290
- gpu_kernel speedup: 3.494x
- device_cache allocations: 8 calls, 0.753 MiB
- device_cache hits/misses: 40/8
- device_cache recycled: 47 blocks, 5.775 MiB

## Cases

- perf_fir_pad: pass, max_abs=4.172325e-07
