# windows/gaussian Summary

- generated_at: 2026-06-26 03:50:23
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.192093e-07
- gpu_vs_cpu max_rel: 2.105640e-07
- gpu_vs_cpu rmse: 8.378076e-09
- reference max_abs: 0.000000e+00
- reference max_rel: 0.000000e+00

## Performance

- cpu median_ms: 0.163
- cpu mean_ms: 0.163
- cpu p95_ms: 0.163
- gpu_e2e median_ms: 0.161
- gpu_e2e mean_ms: 0.161
- gpu_e2e p95_ms: 0.161
- gpu_e2e speedup: 1.015x
- gpu_kernel median_ms: 0.101
- gpu_kernel speedup: 1.623x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 8/2
- device_cache recycled: 10 blocks, 0.563 MiB

## Cases

- sym_std: pass, max_abs=0.000000e+00
- perf_large: pass, max_abs=1.192093e-07
