# windows/taylor Summary

- generated_at: 2026-06-26 09:56:21
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.788139e-07
- gpu_vs_cpu max_rel: 3.536325e-07
- gpu_vs_cpu rmse: 2.433350e-08
- reference max_abs: 1.192093e-07
- reference max_rel: 2.860482e-07

## Performance

- cpu median_ms: 580.723
- cpu mean_ms: 580.723
- cpu p95_ms: 580.723
- gpu_e2e median_ms: 7.655
- gpu_e2e mean_ms: 7.655
- gpu_e2e p95_ms: 7.655
- gpu_e2e speedup: 75.862x
- gpu_kernel median_ms: 7.594
- gpu_kernel speedup: 76.470x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4544.000 MiB

## Cases

- nbar5_sll35: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=1.788139e-07
