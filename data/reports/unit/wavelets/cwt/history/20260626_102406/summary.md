# wavelets/cwt Summary

- generated_at: 2026-06-26 10:24:06
- pass: true
- accuracy_cases: 5
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 0.000000e+00
- gpu_vs_cpu max_rel: 0.000000e+00
- gpu_vs_cpu rmse: 0.000000e+00
- reference max_abs: 7.152557e-07
- reference max_rel: 1.129918e-04

## Performance

- cpu median_ms: 24219.568
- cpu mean_ms: 24219.568
- cpu p95_ms: 24219.568
- gpu_e2e median_ms: 105.942
- gpu_e2e mean_ms: 105.942
- gpu_e2e p95_ms: 105.942
- gpu_e2e speedup: 228.612x
- gpu_kernel median_ms: 105.870
- gpu_kernel speedup: 228.767x
- device_cache allocations: 17 calls, 260.043 MiB
- device_cache hits/misses: 75/17
- device_cache recycled: 85 blocks, 18180.004 MiB

## Cases

- ricker_case: pass, max_abs=0.000000e+00
- morlet2_case: pass, max_abs=0.000000e+00
- invalid_empty_widths: pass, max_abs=0.000000e+00
- invalid_wavelet: pass, max_abs=0.000000e+00
- invalid_width_value: pass, max_abs=0.000000e+00
- perf_ricker_large: pass, max_abs=0.000000e+00
