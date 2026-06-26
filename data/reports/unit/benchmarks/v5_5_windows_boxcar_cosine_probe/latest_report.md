# All-Operator Benchmark Report

- run_id: `20260626_065529`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00624 | 0.0286 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.811 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00326 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00289 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.832 | 1.4 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0572 | 0.172 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.57 | 1.7 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.77 | 4.53 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.82 | 4.73 |
| radartools/mvdr | 1048576 | passed | 0 | 0.406 | 0.504 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.08 | 396 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0196 | 0.0198 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.31 | 1.65 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.33 |
| windows/bartlett | 1048576 | passed | 0 | 0.224 | 0.226 |
| windows/blackman | 1048576 | passed | 0 | 39.1 | 48.3 |
| windows/blackmanharris | 1048576 | passed | 0 | 42 | 48.8 |
| windows/bohman | 1048576 | passed | 0 | 2.42 | 2.44 |
| windows/boxcar | 1048576 | passed | 0 | 0.582 | 1.24 |
| windows/cosine | 1048576 | passed | 0 | 57.5 | 77.6 |
| windows/exponential | 1048576 | passed | 0 | 1.65 | 1.67 |
| windows/flattop | 1048576 | passed | 0 | 43.4 | 47.9 |
| windows/gaussian | 1048576 | passed | 0 | 2.18 | 2.23 |
| windows/general_hamming | 1048576 | passed | 0 | 33.5 | 46.1 |
| windows/get_window | 1048576 | passed | 0 | 33.1 | 46.2 |
| windows/hann | 1048576 | passed | 0 | 33.7 | 46.7 |
| windows/nuttall | 1048576 | passed | 0 | 41.4 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 0.88 | 0.892 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.08 | 396 |
| filtering/lfilter | 1.39e-06 | 0.57 | 1.7 |
| filtering/filtfilt | 7.49e-07 | 0.832 | 1.4 |
| spectral/welch | 3.16e-07 | 1.31 | 1.65 |
| spectral/periodogram | 1.8e-07 | 0.0196 | 0.0198 |
| correlate/correlation_lags | 0 | 0.00624 | 0.0286 |
| filter_design/cmplx_sort | 0 | 0.811 | 0 |
| filter_design/kaiser_atten | 0 | 0.00326 | 0 |
| filter_design/kaiser_beta | 0 | 0.00289 | 0 |
| filtering/firfilter_zi | 0 | 0.0572 | 0.172 |
| peak_finding/argrelmax | 0 | 3.77 | 4.53 |
| peak_finding/argrelmin | 0 | 3.82 | 4.73 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_beta | 0.00289 | 0 | 0 |
| filter_design/kaiser_atten | 0.00326 | 0 | 0 |
| correlate/correlation_lags | 0.00624 | 0.0286 | 0 |
| spectral/periodogram | 0.0196 | 0.0198 | 1.8e-07 |
| filtering/firfilter_zi | 0.0572 | 0.172 | 0 |
| windows/bartlett | 0.224 | 0.226 | 0 |
| radartools/mvdr | 0.406 | 0.504 | 0 |
| filtering/lfilter | 0.57 | 1.7 | 1.39e-06 |
| windows/boxcar | 0.582 | 1.24 | 0 |
| filter_design/cmplx_sort | 0.811 | 0 | 0 |
| filtering/filtfilt | 0.832 | 1.4 | 7.49e-07 |
| windows/tukey | 0.88 | 0.892 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.811 | 0 |
| filter_design/kaiser_atten | 0 | 0.00326 | 0 |
| filter_design/kaiser_beta | 0 | 0.00289 | 0 |
| spectral/periodogram | 0.0198 | 0.0196 | 1.8e-07 |
| correlate/correlation_lags | 0.0286 | 0.00624 | 0 |
| filtering/firfilter_zi | 0.172 | 0.0572 | 0 |
| windows/bartlett | 0.226 | 0.224 | 0 |
| radartools/mvdr | 0.504 | 0.406 | 0 |
| windows/tukey | 0.892 | 0.88 | 0 |
| windows/boxcar | 1.24 | 0.582 | 0 |
| windows/barthann | 1.33 | 1.31 | 0 |
| filtering/filtfilt | 1.4 | 0.832 | 7.49e-07 |
