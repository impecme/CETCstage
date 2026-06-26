# radartools/pulse_doppler Summary

- generated_at: 2026-06-26 09:58:39
- pass: true
- accuracy_cases: 2
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.078959e-05
- gpu_vs_cpu max_rel: 8.634969e-06
- gpu_vs_cpu rmse: 1.284953e-06
- reference max_abs: 2.384186e-07
- reference max_rel: 1.874494e-07

## Performance

- cpu median_ms: 9.090
- cpu mean_ms: 9.090
- cpu p95_ms: 9.090
- gpu_e2e median_ms: 0.291
- gpu_e2e mean_ms: 0.291
- gpu_e2e p95_ms: 0.291
- gpu_e2e speedup: 31.204x
- gpu_kernel median_ms: 0.135
- gpu_kernel speedup: 67.220x
- device_cache allocations: 6 calls, 8.251 MiB
- device_cache hits/misses: 70/6
- device_cache recycled: 75 blocks, 25.751 MiB

## Cases

- basic: pass, max_abs=2.384186e-07
- boxcar_nfft8: pass, max_abs=2.384186e-07
- perf_large: pass, max_abs=1.078959e-05
