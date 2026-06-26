# All-Operator Benchmark Report

- run_id: `20260619_055800`
- scale_profile: `default`
- rows: `1`
- operators: `1`
- passed_rows: `1`
- status: passed=1
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| filtering/wiener | 1048576 | passed | 9.76e-07 | 3.03 | 3 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filtering/wiener | 9.76e-07 | 3.03 | 3 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/wiener | 3.03 | 3 | 9.76e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filtering/wiener | 3 | 3.03 | 9.76e-07 |
