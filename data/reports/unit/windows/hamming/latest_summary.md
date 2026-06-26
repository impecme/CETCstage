# windows/hamming Summary

- generated_at: 2026-06-26 12:18:34
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.788139e-07
- gpu_vs_cpu max_rel: 8.193718e-07
- gpu_vs_cpu rmse: 4.805480e-08
- reference max_abs: 1.192093e-07
- reference max_rel: 5.587935e-07

## Performance

- cpu median_ms: 157.802
- cpu mean_ms: 157.802
- cpu p95_ms: 157.802
- gpu_e2e median_ms: 2.370
- gpu_e2e mean_ms: 2.370
- gpu_e2e p95_ms: 2.370
- gpu_e2e speedup: 66.592x
- gpu_kernel median_ms: 2.317
- gpu_kernel speedup: 68.098x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4544.000 MiB

## Cases

- periodic_small: pass, max_abs=1.192093e-07
- perf_large: pass, max_abs=1.788139e-07
