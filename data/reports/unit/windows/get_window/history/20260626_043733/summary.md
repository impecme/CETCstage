# windows/get_window Summary

- generated_at: 2026-06-26 04:37:33
- pass: true
- accuracy_cases: 5
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.490116e-07
- gpu_vs_cpu max_rel: 6.924498e-07
- gpu_vs_cpu rmse: 5.065421e-08
- reference max_abs: 8.940697e-08
- reference max_rel: 6.105089e-07

## Performance

- cpu median_ms: 0.131
- cpu mean_ms: 0.131
- cpu p95_ms: 0.131
- gpu_e2e median_ms: 0.077
- gpu_e2e mean_ms: 0.077
- gpu_e2e p95_ms: 0.077
- gpu_e2e speedup: 1.697x
- gpu_kernel median_ms: 0.030
- gpu_kernel speedup: 4.302x
- device_cache allocations: 5 calls, 0.063 MiB
- device_cache hits/misses: 9/5
- device_cache recycled: 14 blocks, 0.563 MiB

## Cases

- string_hann: pass, max_abs=8.940697e-08
- float_kaiser: pass, max_abs=3.725290e-09
- named_pair_general_gaussian: pass, max_abs=5.960464e-08
- named_taylor: pass, max_abs=5.960464e-08
- array_passthrough: pass, max_abs=0.000000e+00
- perf_named_hamming: pass, max_abs=1.490116e-07
