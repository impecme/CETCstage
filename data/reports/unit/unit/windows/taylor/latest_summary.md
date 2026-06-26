# windows/taylor Summary

- generated_at: 2026-06-26 03:50:52
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

- cpu median_ms: 578.634
- cpu mean_ms: 578.634
- cpu p95_ms: 578.634
- gpu_e2e median_ms: 7.665
- gpu_e2e mean_ms: 7.665
- gpu_e2e p95_ms: 7.665
- gpu_e2e speedup: 75.489x
- gpu_kernel median_ms: 7.611
- gpu_kernel speedup: 76.026x
- device_cache allocations: 2 calls, 64.000 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 576.000 MiB

## Cases

- nbar5_sll35: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=1.788139e-07
