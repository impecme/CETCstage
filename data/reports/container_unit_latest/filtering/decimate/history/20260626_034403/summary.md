# filtering/decimate Summary

- generated_at: 2026-06-26 03:44:03
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 3.576279e-07
- gpu_vs_cpu max_rel: 3.447957e-04
- gpu_vs_cpu rmse: 8.750592e-08
- reference max_abs: 1.788139e-07
- reference max_rel: 7.005583e-07

## Performance

- cpu median_ms: 59.422
- cpu mean_ms: 59.422
- cpu p95_ms: 59.422
- gpu_e2e median_ms: 3.824
- gpu_e2e mean_ms: 3.824
- gpu_e2e p95_ms: 3.824
- gpu_e2e speedup: 15.539x
- gpu_kernel median_ms: 3.739
- gpu_kernel speedup: 15.891x
- device_cache allocations: 10 calls, 6.002 MiB
- device_cache hits/misses: 16/10
- device_cache recycled: 23 blocks, 22.001 MiB

## Cases

- q3_zero_phase: pass, max_abs=2.384186e-07
- perf_q4: pass, max_abs=3.576279e-07
