# filtering/decimate Summary

- generated_at: 2026-06-26 09:57:55
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

- cpu median_ms: 59.817
- cpu mean_ms: 59.817
- cpu p95_ms: 59.817
- gpu_e2e median_ms: 3.881
- gpu_e2e mean_ms: 3.881
- gpu_e2e p95_ms: 3.881
- gpu_e2e speedup: 15.412x
- gpu_kernel median_ms: 3.722
- gpu_kernel speedup: 16.072x
- device_cache allocations: 10 calls, 6.002 MiB
- device_cache hits/misses: 140/10
- device_cache recycled: 147 blocks, 146.006 MiB

## Cases

- q3_zero_phase: pass, max_abs=2.384186e-07
- perf_q4: pass, max_abs=3.576279e-07
