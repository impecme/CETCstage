# spectral/istft Summary

- generated_at: 2026-06-26 03:46:37
- pass: true
- accuracy_cases: 1
- perf_cases: 1

## Errors

- gpu_vs_cpu max_abs: 1.490116e-06
- gpu_vs_cpu max_rel: 1.017474e-02
- gpu_vs_cpu rmse: 2.315216e-07
- reference max_abs: 2.384186e-07
- reference max_rel: 3.098314e-05

## Performance

- cpu median_ms: 2.680
- cpu mean_ms: 2.680
- cpu p95_ms: 2.680
- gpu_e2e median_ms: 0.676
- gpu_e2e mean_ms: 0.676
- gpu_e2e p95_ms: 0.676
- gpu_e2e speedup: 3.962x
- gpu_kernel median_ms: 0.212
- gpu_kernel speedup: 12.628x
- device_cache allocations: 7 calls, 0.331 MiB
- device_cache hits/misses: 25/7
- device_cache recycled: 31 blocks, 0.591 MiB

## Cases

- onesided_boundary: pass, max_abs=2.384186e-07
- perf_onesided: pass, max_abs=1.490116e-06
