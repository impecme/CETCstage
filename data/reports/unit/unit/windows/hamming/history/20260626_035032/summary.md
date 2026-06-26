# windows/hamming Summary

- generated_at: 2026-06-26 03:50:32
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

- cpu median_ms: 153.446
- cpu mean_ms: 153.446
- cpu p95_ms: 153.446
- gpu_e2e median_ms: 2.414
- gpu_e2e mean_ms: 2.414
- gpu_e2e p95_ms: 2.414
- gpu_e2e speedup: 63.574x
- gpu_kernel median_ms: 2.320
- gpu_kernel speedup: 66.150x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 576.000 MiB

## Cases

- periodic_small: pass, max_abs=1.192093e-07
- perf_large: pass, max_abs=1.788139e-07
