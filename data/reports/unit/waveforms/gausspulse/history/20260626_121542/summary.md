# waveforms/gausspulse Summary

- generated_at: 2026-06-26 12:15:42
- pass: true
- accuracy_cases: 4
- perf_cases: 2

## Errors

- gpu_vs_cpu max_abs: 1.788139e-07
- gpu_vs_cpu max_rel: 4.340048e-07
- gpu_vs_cpu rmse: 1.671672e-08
- reference max_abs: 5.960464e-08
- reference max_rel: 1.186018e-07

## Performance

- cpu median_ms: 545.493
- cpu mean_ms: 369.502
- cpu p95_ms: 545.493
- gpu_e2e median_ms: 5.387
- gpu_e2e mean_ms: 4.012
- gpu_e2e p95_ms: 5.387
- gpu_e2e speedup: 101.261x
- gpu_kernel median_ms: 5.357
- gpu_kernel speedup: 101.830x
- device_cache allocations: 8 calls, 256.000 MiB
- device_cache hits/misses: 147/8
- device_cache recycled: 154 blocks, 9344.000 MiB

## Cases

- real: pass, max_abs=0.000000e+00
- iq: pass, max_abs=0.000000e+00
- ienv: pass, max_abs=0.000000e+00
- bundle: pass, max_abs=0.000000e+00
- perf_real: pass, max_abs=1.788139e-07
- perf_bundle: pass, max_abs=1.788139e-07
