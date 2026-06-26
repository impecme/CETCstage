# windows/cosine Summary

- generated_at: 2026-06-26 09:53:40
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 2.384186e-07
- gpu_vs_cpu max_rel: 2.471616e-04
- gpu_vs_cpu rmse: 5.414822e-08
- reference max_abs: 1.192093e-07
- reference max_rel: 2.625810e-07

## Performance

- cpu median_ms: 0.224
- cpu mean_ms: 0.224
- cpu p95_ms: 0.224
- gpu_e2e median_ms: 0.075
- gpu_e2e mean_ms: 0.075
- gpu_e2e p95_ms: 0.075
- gpu_e2e speedup: 2.998x
- gpu_kernel median_ms: 0.030
- gpu_kernel speedup: 7.403x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4.438 MiB

## Cases

- periodic_small: pass, max_abs=5.960464e-08
- perf_large: pass, max_abs=2.384186e-07
