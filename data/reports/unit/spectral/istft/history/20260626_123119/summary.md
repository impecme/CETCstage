# spectral/istft Summary

- generated_at: 2026-06-26 12:31:19
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

- cpu median_ms: 2.663
- cpu mean_ms: 2.663
- cpu p95_ms: 2.663
- gpu_e2e median_ms: 0.714
- gpu_e2e mean_ms: 0.714
- gpu_e2e p95_ms: 0.714
- gpu_e2e speedup: 3.729x
- gpu_kernel median_ms: 0.256
- gpu_kernel speedup: 10.413x
- device_cache allocations: 7 calls, 0.331 MiB
- device_cache hits/misses: 211/7
- device_cache recycled: 217 blocks, 4.557 MiB

## Cases

- onesided_boundary: pass, max_abs=2.384186e-07
- perf_onesided: pass, max_abs=1.490116e-06
