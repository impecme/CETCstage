# waveforms/chirp Summary

- generated_at: 2026-06-25 14:27:42
- pass: true
- accuracy_cases: 0
- perf_cases: 2

## Errors

- gpu_vs_cpu max_abs: 3.919884e-06
- gpu_vs_cpu max_rel: 3.919884e-06
- gpu_vs_cpu rmse: 1.337490e-06

## Performance

- cpu median_ms: 20.686
- cpu mean_ms: 16.688
- cpu p95_ms: 20.686
- gpu_e2e median_ms: 0.328
- gpu_e2e mean_ms: 0.283
- gpu_e2e p95_ms: 0.328
- gpu_e2e speedup: 62.990x
- gpu_kernel median_ms: 0.309
- gpu_kernel speedup: 66.966x
- device_cache allocations: 3 calls, 16.000 MiB
- device_cache hits/misses: 9/3
- device_cache recycled: 12 blocks, 68.000 MiB

## Cases

- perf_linear_real: pass, max_abs=5.960464e-08
- perf_linear_complex: pass, max_abs=3.919884e-06
