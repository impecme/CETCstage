# spectral/csd Summary

- generated_at: 2026-06-26 12:30:24
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 4.165001e-09
- gpu_vs_cpu max_rel: 3.331824e-01
- gpu_vs_cpu rmse: 5.571920e-10
- reference max_abs: 5.268356e-09
- reference max_rel: 4.214416e-01

## Performance

- cpu median_ms: 192.811
- cpu mean_ms: 192.811
- cpu p95_ms: 192.811
- gpu_e2e median_ms: 19.311
- gpu_e2e mean_ms: 19.311
- gpu_e2e p95_ms: 19.311
- gpu_e2e speedup: 9.985x
- gpu_kernel median_ms: 18.790
- gpu_kernel speedup: 10.261x
- device_cache allocations: 10 calls, 8.008 MiB
- device_cache hits/misses: 70/10
- device_cache recycled: 76 blocks, 8.071 MiB

## Cases

- mean_hann: pass, max_abs=4.165001e-09
- perf_mean_hann: pass, max_abs=9.313226e-10
