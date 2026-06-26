# waveforms/sawtooth Summary

- generated_at: 2026-06-25 16:58:07
- pass: true
- accuracy_cases: 0
- perf_cases: 2

## Errors

- gpu_vs_cpu max_abs: 2.384186e-07
- gpu_vs_cpu max_rel: 3.750000e-01
- gpu_vs_cpu rmse: 1.141789e-07

## Performance

- cpu median_ms: 9.104
- cpu mean_ms: 9.025
- cpu p95_ms: 9.104
- gpu_e2e median_ms: 0.246
- gpu_e2e mean_ms: 0.244
- gpu_e2e p95_ms: 0.246
- gpu_e2e speedup: 36.996x
- gpu_kernel median_ms: 0.209
- gpu_kernel speedup: 43.465x
- device_cache allocations: 2 calls, 8.000 MiB
- device_cache hits/misses: 10/2
- device_cache recycled: 12 blocks, 48.000 MiB

## Cases

- perf_scalar: pass, max_abs=1.192093e-07
- perf_vector: pass, max_abs=2.384186e-07
