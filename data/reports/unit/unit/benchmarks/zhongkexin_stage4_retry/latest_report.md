# All-Operator Benchmark Report

- run_id: `20260617_114340`
- scale_profile: `default`
- rows: `90`
- operators: `15`
- passed_rows: `90`
- status: passed=90
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00619 | 0.028 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.814 | 0 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.692 | 0.901 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00143 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.000943 | 0 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.000613 | 0.000613 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0458 | 0.138 |
| filtering/lfilter | 32768 | passed | 0 | 0.00045 | 0.000451 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.75 | 4.74 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.88 | 4.9 |
| radartools/mvdr | 1048576 | passed | 0 | 0.406 | 0.504 |
| spectral/coherence | 32768 | passed | 0.00326 | 1.46 | 402 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0244 | 0.0247 |
| spectral/welch | 32768 | passed | 3.63e-07 | 1.29 | 1.65 |
| windows/chebwin | 1536 | passed | 0 | 2.28 | 8.6 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00326 | 1.46 | 402 |
| filter_design/firwin2 | 7.58e-05 | 0.692 | 0.901 |
| spectral/welch | 3.63e-07 | 1.29 | 1.65 |
| filtering/filtfilt | 1.97e-07 | 0.000613 | 0.000613 |
| spectral/periodogram | 1.8e-07 | 0.0244 | 0.0247 |
| correlate/correlation_lags | 0 | 0.00619 | 0.028 |
| filter_design/cmplx_sort | 0 | 0.814 | 0 |
| filter_design/kaiser_atten | 0 | 0.00143 | 0 |
| filter_design/kaiser_beta | 0 | 0.000943 | 0 |
| filtering/firfilter_zi | 0 | 0.0458 | 0.138 |
| filtering/lfilter | 0 | 0.00045 | 0.000451 |
| peak_finding/argrelmax | 0 | 3.75 | 4.74 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.00045 | 0.000451 | 0 |
| filtering/filtfilt | 0.000613 | 0.000613 | 1.97e-07 |
| filter_design/kaiser_beta | 0.000943 | 0 | 0 |
| filter_design/kaiser_atten | 0.00143 | 0 | 0 |
| correlate/correlation_lags | 0.00619 | 0.028 | 0 |
| spectral/periodogram | 0.0244 | 0.0247 | 1.8e-07 |
| filtering/firfilter_zi | 0.0458 | 0.138 | 0 |
| radartools/mvdr | 0.406 | 0.504 | 0 |
| filter_design/firwin2 | 0.692 | 0.901 | 7.58e-05 |
| filter_design/cmplx_sort | 0.814 | 0 | 0 |
| spectral/welch | 1.29 | 1.65 | 3.63e-07 |
| spectral/coherence | 1.46 | 402 | 0.00326 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.814 | 0 |
| filter_design/kaiser_atten | 0 | 0.00143 | 0 |
| filter_design/kaiser_beta | 0 | 0.000943 | 0 |
| filtering/lfilter | 0.000451 | 0.00045 | 0 |
| filtering/filtfilt | 0.000613 | 0.000613 | 1.97e-07 |
| spectral/periodogram | 0.0247 | 0.0244 | 1.8e-07 |
| correlate/correlation_lags | 0.028 | 0.00619 | 0 |
| filtering/firfilter_zi | 0.138 | 0.0458 | 0 |
| radartools/mvdr | 0.504 | 0.406 | 0 |
| filter_design/firwin2 | 0.901 | 0.692 | 7.58e-05 |
| spectral/welch | 1.65 | 1.29 | 3.63e-07 |
| peak_finding/argrelmax | 4.74 | 3.75 | 0 |
