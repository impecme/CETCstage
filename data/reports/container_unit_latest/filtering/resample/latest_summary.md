# filtering/resample Summary

- generated_at: 2026-06-26 04:30:21
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 8.344650e-07
- gpu_vs_cpu max_rel: 1.000000e+00
- gpu_vs_cpu rmse: 1.503314e-07
- reference max_abs: 1.192093e-07
- reference max_rel: 3.454027e-01

## Performance

- cpu median_ms: 322.183
- cpu mean_ms: 322.183
- cpu p95_ms: 322.183
- gpu_e2e median_ms: 6.904
- gpu_e2e mean_ms: 6.904
- gpu_e2e p95_ms: 6.904
- gpu_e2e speedup: 46.664x
- gpu_kernel median_ms: 6.813
- gpu_kernel speedup: 47.291x
- device_cache allocations: 11 calls, 34.000 MiB
- device_cache hits/misses: 9/11
- device_cache recycled: 16 blocks, 58.001 MiB

## Cases

- time_domain_no_t: pass, max_abs=2.980232e-07
- time_domain_with_t: pass, max_abs=1.192093e-07
- perf_time_domain: pass, max_abs=8.344650e-07
