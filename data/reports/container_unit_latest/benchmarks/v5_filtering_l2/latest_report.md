# All-Operator Benchmark Report

- run_id: `20260619_060229`
- scale_profile: `default`
- rows: `17`
- operators: `17`
- passed_rows: `17`
- status: passed=17
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.43 | 4.45 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.73 | 1.84 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.000616 | 0.000616 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.5 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.6 | 3.08 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0532 | 0.157 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 8.03 | 14.6 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.63 | 8.29 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23 | 23.4 |
| filtering/lfilter | 32768 | passed | 0 | 0.000451 | 0.000451 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.7 | 59.5 |
| filtering/resample | 32768 | passed | 3.85e-05 | 5.53 | 7.19 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16 | 18.3 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.823 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.75 | 6.24 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 3.11 | 3.1 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.85e-05 | 5.53 | 7.19 |
| filtering/hilbert2 | 1.71e-05 | 23 | 23.4 |
| filtering/detrend | 4.59e-06 | 0.73 | 1.84 |
| filtering/hilbert | 1.97e-06 | 6.63 | 8.29 |
| filtering/wiener | 9.76e-07 | 3.11 | 3.1 |
| filtering/firfilter | 9.04e-07 | 12 | 12.5 |
| filtering/sosfilt | 8.25e-07 | 0.823 | 1.3 |
| filtering/firfilter2 | 8.15e-07 | 2.6 | 3.08 |
| filtering/decimate | 6.95e-07 | 3.43 | 4.45 |
| filtering/resample_poly | 5.4e-07 | 16 | 18.3 |
| filtering/upfirdn | 2.87e-07 | 4.75 | 6.24 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.000451 | 0.000451 | 0 |
| filtering/filtfilt | 0.000616 | 0.000616 | 1.97e-07 |
| filtering/firfilter_zi | 0.0532 | 0.157 | 0 |
| filtering/detrend | 0.73 | 1.84 | 4.59e-06 |
| filtering/sosfilt | 0.823 | 1.3 | 8.25e-07 |
| filtering/firfilter2 | 2.6 | 3.08 | 8.15e-07 |
| filtering/wiener | 3.11 | 3.1 | 9.76e-07 |
| filtering/decimate | 3.43 | 4.45 | 6.95e-07 |
| filtering/upfirdn | 4.75 | 6.24 | 2.87e-07 |
| filtering/resample | 5.53 | 7.19 | 3.85e-05 |
| filtering/hilbert | 6.63 | 8.29 | 1.97e-06 |
| filtering/freq_shift | 8.03 | 14.6 | 1.98e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.000451 | 0.000451 | 0 |
| filtering/filtfilt | 0.000616 | 0.000616 | 1.97e-07 |
| filtering/firfilter_zi | 0.157 | 0.0532 | 0 |
| filtering/sosfilt | 1.3 | 0.823 | 8.25e-07 |
| filtering/detrend | 1.84 | 0.73 | 4.59e-06 |
| filtering/firfilter2 | 3.08 | 2.6 | 8.15e-07 |
| filtering/wiener | 3.1 | 3.11 | 9.76e-07 |
| filtering/decimate | 4.45 | 3.43 | 6.95e-07 |
| filtering/upfirdn | 6.24 | 4.75 | 2.87e-07 |
| filtering/resample | 7.19 | 5.53 | 3.85e-05 |
| filtering/hilbert | 8.29 | 6.63 | 1.97e-06 |
| filtering/channelize_poly | 11.7 | 10.3 | 5.7e-05 |
