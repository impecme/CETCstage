# spectral/vectorstrength Summary

- generated_at: 2026-06-26 12:31:53
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.768372e-06
- gpu_vs_cpu max_rel: 1.361563e-03
- gpu_vs_cpu rmse: 1.453480e-06
- reference max_abs: 1.716614e-05
- reference max_rel: 7.192016e-05

## Performance

- cpu median_ms: 665.115
- cpu mean_ms: 665.115
- cpu p95_ms: 665.115
- gpu_e2e median_ms: 9.140
- gpu_e2e mean_ms: 9.140
- gpu_e2e p95_ms: 9.140
- gpu_e2e speedup: 72.770x
- gpu_kernel median_ms: 9.082
- gpu_kernel speedup: 73.235x
- device_cache allocations: 12 calls, 4.001 MiB
- device_cache hits/misses: 140/12
- device_cache recycled: 148 blocks, 4.035 MiB

## Cases

- scalar_period: pass, max_abs=2.384186e-07
- vector_periods: pass, max_abs=9.536743e-07
- perf_vector: pass, max_abs=4.768372e-06
