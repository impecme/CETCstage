# wavelets/cwt Summary

- generated_at: 2026-06-26 03:50:08
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

- cpu median_ms: 24348.463
- cpu mean_ms: 24348.463
- cpu p95_ms: 24348.463
- gpu_e2e median_ms: 105.827
- gpu_e2e mean_ms: 105.827
- gpu_e2e p95_ms: 105.827
- gpu_e2e speedup: 230.078x
- gpu_kernel median_ms: 105.910
- gpu_kernel speedup: 229.897x
- device_cache allocations: 17 calls, 260.043 MiB
- device_cache hits/misses: 13/17
- device_cache recycled: 23 blocks, 2308.004 MiB

## Cases

- ricker_case: pass, max_abs=0.000000e+00
- morlet2_case: pass, max_abs=0.000000e+00
- invalid_empty_widths: pass, max_abs=0.000000e+00
- invalid_wavelet: pass, max_abs=0.000000e+00
- invalid_width_value: pass, max_abs=0.000000e+00
- perf_ricker_large: pass, max_abs=0.000000e+00
