# waveforms/chirp Summary

- generated_at: 2026-06-26 09:50:40
- pass: true
- accuracy_cases: 6
- perf_cases: 2

## Errors

- gpu_vs_cpu max_abs: 7.721275e-06
- gpu_vs_cpu max_rel: 2.077949e+00
- gpu_vs_cpu rmse: 1.648638e-06
- reference max_abs: 2.188392e-06
- reference max_rel: 1.589492e-05

## Performance

- cpu median_ms: 355.471
- cpu mean_ms: 298.850
- cpu p95_ms: 355.471
- gpu_e2e median_ms: 4.144
- gpu_e2e mean_ms: 3.442
- gpu_e2e p95_ms: 4.144
- gpu_e2e speedup: 85.784x
- gpu_kernel median_ms: 4.377
- gpu_kernel speedup: 81.204x
- device_cache allocations: 6 calls, 256.000 MiB
- device_cache hits/misses: 75/6
- device_cache recycled: 80 blocks, 7040.000 MiB

## Cases

- linear_real: pass, max_abs=0.000000e+00
- linear_complex: pass, max_abs=1.922192e-06
- quadratic_zero: pass, max_abs=5.960464e-08
- quadratic_t1: pass, max_abs=1.490116e-08
- logarithmic: pass, max_abs=5.960464e-08
- hyperbolic: pass, max_abs=0.000000e+00
- perf_linear_real: pass, max_abs=3.816560e-06
- perf_linear_complex: pass, max_abs=7.721275e-06
