# radartools/pulse_doppler Summary

- generated_at: 2026-06-26 04:30:56
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

- cpu median_ms: 9.287
- cpu mean_ms: 9.287
- cpu p95_ms: 9.287
- gpu_e2e median_ms: 0.297
- gpu_e2e mean_ms: 0.297
- gpu_e2e p95_ms: 0.297
- gpu_e2e speedup: 31.273x
- gpu_kernel median_ms: 0.150
- gpu_kernel speedup: 61.944x
- device_cache allocations: 6 calls, 8.251 MiB
- device_cache hits/misses: 8/6
- device_cache recycled: 13 blocks, 10.251 MiB

## Cases

- basic: pass, max_abs=2.384186e-07
- boxcar_nfft8: pass, max_abs=2.384186e-07
- perf_large: pass, max_abs=1.078959e-05
