# filtering/firfilter Summary

- generated_at: 2026-06-26 09:57:01
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.768372e-07
- gpu_vs_cpu max_rel: 5.288405e-03
- gpu_vs_cpu rmse: 6.529623e-08
- reference max_abs: 1.192093e-07
- reference max_rel: 1.110223e-01

## Performance

- cpu median_ms: 13.951
- cpu mean_ms: 13.951
- cpu p95_ms: 13.951
- gpu_e2e median_ms: 1.173
- gpu_e2e mean_ms: 1.173
- gpu_e2e p95_ms: 1.173
- gpu_e2e speedup: 11.891x
- gpu_kernel median_ms: 1.141
- gpu_kernel speedup: 12.226x
- device_cache allocations: 9 calls, 8.000 MiB
- device_cache hits/misses: 70/9
- device_cache recycled: 75 blocks, 288.000 MiB

## Cases

- with_state_axis_last: pass, max_abs=0.000000e+00
- perf_axis_last: pass, max_abs=4.768372e-07
