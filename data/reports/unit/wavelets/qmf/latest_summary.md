# wavelets/qmf Summary

- generated_at: 2026-06-26 12:32:05
- pass: true
- accuracy_cases: 3
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 0.000000e+00
- gpu_vs_cpu max_rel: 0.000000e+00
- gpu_vs_cpu rmse: 0.000000e+00
- reference max_abs: 0.000000e+00
- reference max_rel: 0.000000e+00

## Performance

- cpu median_ms: 80.545
- cpu mean_ms: 80.545
- cpu p95_ms: 80.545
- gpu_e2e median_ms: 1.657
- gpu_e2e mean_ms: 1.657
- gpu_e2e p95_ms: 1.657
- gpu_e2e speedup: 48.601x
- gpu_kernel median_ms: 1.601
- gpu_kernel speedup: 50.315x
- device_cache allocations: 6 calls, 128.000 MiB
- device_cache hits/misses: 70/6
- device_cache recycled: 75 blocks, 4608.000 MiB

## Cases

- even_taps: pass, max_abs=0.000000e+00
- odd_taps: pass, max_abs=0.000000e+00
- empty_taps: pass, max_abs=0.000000e+00
- perf_large_vector: pass, max_abs=0.000000e+00
