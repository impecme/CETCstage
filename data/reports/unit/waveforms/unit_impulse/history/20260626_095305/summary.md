# waveforms/unit_impulse Summary

- generated_at: 2026-06-26 09:53:05
- pass: true
- accuracy_cases: 4
- perf_cases: 2

## Errors

- gpu_vs_cpu max_abs: 0.000000e+00
- gpu_vs_cpu max_rel: 0.000000e+00
- gpu_vs_cpu rmse: 0.000000e+00
- reference max_abs: 0.000000e+00
- reference max_rel: 0.000000e+00

## Performance

- cpu median_ms: 100.522
- cpu mean_ms: 100.080
- cpu p95_ms: 100.522
- gpu_e2e median_ms: 0.807
- gpu_e2e mean_ms: 0.807
- gpu_e2e p95_ms: 0.807
- gpu_e2e speedup: 124.509x
- gpu_kernel median_ms: 0.027
- gpu_kernel speedup: 3785.867x
- device_cache allocations: 3 calls, 64.000 MiB
- device_cache hits/misses: 73/3
- device_cache recycled: 76 blocks, 4608.000 MiB

## Cases

- one_dim_default: pass, max_abs=0.000000e+00
- one_dim_mid: pass, max_abs=0.000000e+00
- nd_mid: pass, max_abs=0.000000e+00
- nd_shape: pass, max_abs=0.000000e+00
- perf_1d_mid: pass, max_abs=0.000000e+00
- perf_nd_scalar: pass, max_abs=0.000000e+00
