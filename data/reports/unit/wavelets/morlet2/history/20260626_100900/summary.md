# wavelets/morlet2 Summary

- generated_at: 2026-06-26 10:09:00
- pass: true
- accuracy_cases: 3
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 5.960464e-08
- gpu_vs_cpu max_rel: 2.921779e-07
- gpu_vs_cpu rmse: 3.181607e-08
- reference max_abs: 5.424105e-08
- reference max_rel: 2.723456e-07

## Performance

- cpu median_ms: 1023.943
- cpu mean_ms: 1023.943
- cpu p95_ms: 1023.943
- gpu_e2e median_ms: 30.388
- gpu_e2e mean_ms: 30.388
- gpu_e2e p95_ms: 30.388
- gpu_e2e speedup: 33.696x
- gpu_kernel median_ms: 30.349
- gpu_kernel speedup: 33.739x
- device_cache allocations: 3 calls, 128.000 MiB
- device_cache hits/misses: 70/3
- device_cache recycled: 73 blocks, 9088.000 MiB

## Cases

- default_w: pass, max_abs=2.980596e-08
- custom_w: pass, max_abs=5.960464e-08
- invalid_s: pass, max_abs=0.000000e+00
- perf_large: pass, max_abs=1.666000e-08
