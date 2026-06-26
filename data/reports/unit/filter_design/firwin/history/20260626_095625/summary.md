# filter_design/firwin Summary

- generated_at: 2026-06-26 09:56:25
- pass: true
- accuracy_cases: 3
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 9.965152e-08
- gpu_vs_cpu max_rel: 1.085144e-05
- gpu_vs_cpu rmse: 1.452477e-08
- reference max_abs: 2.980232e-08
- reference max_rel: 6.808744e+06

## Performance

- cpu median_ms: 1.758
- cpu mean_ms: 1.758
- cpu p95_ms: 1.758
- gpu_e2e median_ms: 0.380
- gpu_e2e mean_ms: 0.380
- gpu_e2e p95_ms: 0.380
- gpu_e2e speedup: 4.628x
- gpu_kernel median_ms: 0.085
- gpu_kernel speedup: 20.572x
- device_cache allocations: 9 calls, 0.047 MiB
- device_cache hits/misses: 139/9
- device_cache recycled: 147 blocks, 2.204 MiB

## Cases

- lowpass_scalar: pass, max_abs=1.490116e-08
- bandpass_multi: pass, max_abs=2.980232e-08
- width_override: pass, max_abs=1.490116e-08
- perf_lowpass_large: pass, max_abs=9.965152e-08
