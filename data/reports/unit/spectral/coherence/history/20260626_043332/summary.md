# spectral/coherence Summary

- generated_at: 2026-06-26 04:33:32
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.079638e-01
- gpu_vs_cpu max_rel: 1.228382e-01
- gpu_vs_cpu rmse: 1.389118e-02
- reference max_abs: 1.085783e-01
- reference max_rel: 1.099539e-01

## Performance

- cpu median_ms: 11.005
- cpu mean_ms: 11.005
- cpu p95_ms: 11.005
- gpu_e2e median_ms: 5.281
- gpu_e2e mean_ms: 5.281
- gpu_e2e p95_ms: 5.281
- gpu_e2e speedup: 2.084x
- gpu_kernel median_ms: 0.027
- gpu_kernel speedup: 403.985x
- device_cache allocations: 19 calls, 0.386 MiB
- device_cache hits/misses: 71/19
- device_cache recycled: 85 blocks, 0.089 MiB

## Cases

- hann_mean: pass, max_abs=1.079638e-01
- perf_hann_mean: pass, max_abs=1.253366e-02
