# windows/hann Summary

- generated_at: 2026-06-26 09:54:26
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.490116e-07
- gpu_vs_cpu max_rel: 1.096011e-04
- gpu_vs_cpu rmse: 4.420399e-08
- reference max_abs: 1.788139e-07
- reference max_rel: 7.643072e-07

## Performance

- cpu median_ms: 0.132
- cpu mean_ms: 0.132
- cpu p95_ms: 0.132
- gpu_e2e median_ms: 0.077
- gpu_e2e mean_ms: 0.077
- gpu_e2e p95_ms: 0.077
- gpu_e2e speedup: 1.720x
- gpu_kernel median_ms: 0.029
- gpu_kernel speedup: 4.547x
- device_cache allocations: 2 calls, 0.063 MiB
- device_cache hits/misses: 70/2
- device_cache recycled: 72 blocks, 4.438 MiB

## Cases

- sym_small: pass, max_abs=1.192093e-07
- perf_large: pass, max_abs=1.490116e-07
