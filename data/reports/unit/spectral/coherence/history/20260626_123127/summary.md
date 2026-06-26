# spectral/coherence Summary

- generated_at: 2026-06-26 12:31:27
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 6.749463e-02
- gpu_vs_cpu max_rel: 7.341323e-02
- gpu_vs_cpu rmse: 8.708633e-03
- reference max_abs: 6.810910e-02
- reference max_rel: 6.897202e-02

## Performance

- cpu median_ms: 11.098
- cpu mean_ms: 11.098
- cpu p95_ms: 11.098
- gpu_e2e median_ms: 0.737
- gpu_e2e mean_ms: 0.737
- gpu_e2e p95_ms: 0.737
- gpu_e2e speedup: 15.049x
- gpu_kernel median_ms: 0.358
- gpu_kernel speedup: 30.985x
- device_cache allocations: 8 calls, 0.255 MiB
- device_cache hits/misses: 72/8
- device_cache recycled: 76 blocks, 0.040 MiB

## Cases

- hann_mean: pass, max_abs=6.749463e-02
- perf_hann_mean: pass, max_abs=2.938330e-03
