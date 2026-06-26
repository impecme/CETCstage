# filtering/freq_shift Summary

- generated_at: 2026-06-26 04:30:12
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 2.425733e-07
- gpu_vs_cpu max_rel: 2.317870e-07
- gpu_vs_cpu rmse: 3.842732e-08
- reference max_abs: 4.915125e-07
- reference max_rel: 4.915125e-07

## Performance

- cpu median_ms: 37.659
- cpu mean_ms: 37.659
- cpu p95_ms: 37.659
- gpu_e2e median_ms: 1.929
- gpu_e2e mean_ms: 1.929
- gpu_e2e p95_ms: 1.929
- gpu_e2e speedup: 19.520x
- gpu_kernel median_ms: 1.849
- gpu_kernel speedup: 20.364x
- device_cache allocations: 4 calls, 16.000 MiB
- device_cache hits/misses: 8/4
- device_cache recycled: 11 blocks, 80.000 MiB

## Cases

- shift_complex_1d: pass, max_abs=8.429370e-08
- perf_shift: pass, max_abs=2.425733e-07
