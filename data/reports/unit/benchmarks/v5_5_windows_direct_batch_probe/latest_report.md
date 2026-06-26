# All-Operator Benchmark Report

- run_id: `20260626_074211`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00619 | 0.028 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.811 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00295 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00299 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.872 | 1.43 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0561 | 0.169 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.526 | 1.68 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.57 | 4.34 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 8.23 | 9.99 |
| radartools/mvdr | 1048576 | passed | 0 | 0.405 | 0.505 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.1 | 395 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0206 | 0.0208 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.32 | 1.66 |
| windows/barthann | 1048576 | passed | 0 | 31.6 | 43.9 |
| windows/bartlett | 1048576 | passed | 0 | 9.34 | 14 |
| windows/blackman | 1048576 | passed | 0 | 38.8 | 48.4 |
| windows/blackmanharris | 1048576 | passed | 0 | 41.8 | 48.7 |
| windows/bohman | 1048576 | passed | 0 | 39.1 | 45.9 |
| windows/boxcar | 1048576 | passed | 0 | 0.585 | 1.21 |
| windows/cosine | 1048576 | passed | 0 | 57.5 | 77.4 |
| windows/exponential | 1048576 | passed | 0 | 54.2 | 82.2 |
| windows/flattop | 1048576 | passed | 0 | 42.6 | 47.8 |
| windows/gaussian | 1048576 | passed | 0 | 81.2 | 111 |
| windows/general_hamming | 1048576 | passed | 0 | 33.1 | 46.1 |
| windows/get_window | 1048576 | passed | 0 | 34.1 | 46.6 |
| windows/hann | 1048576 | passed | 0 | 33.1 | 46 |
| windows/nuttall | 1048576 | passed | 0 | 42 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 20.7 | 29 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.1 | 395 |
| filtering/lfilter | 1.39e-06 | 0.526 | 1.68 |
| filtering/filtfilt | 7.49e-07 | 0.872 | 1.43 |
| spectral/welch | 3.16e-07 | 1.32 | 1.66 |
| spectral/periodogram | 1.8e-07 | 0.0206 | 0.0208 |
| correlate/correlation_lags | 0 | 0.00619 | 0.028 |
| filter_design/cmplx_sort | 0 | 0.811 | 0 |
| filter_design/kaiser_atten | 0 | 0.00295 | 0 |
| filter_design/kaiser_beta | 0 | 0.00299 | 0 |
| filtering/firfilter_zi | 0 | 0.0561 | 0.169 |
| peak_finding/argrelmax | 0 | 3.57 | 4.34 |
| peak_finding/argrelmin | 0 | 8.23 | 9.99 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_atten | 0.00295 | 0 | 0 |
| filter_design/kaiser_beta | 0.00299 | 0 | 0 |
| correlate/correlation_lags | 0.00619 | 0.028 | 0 |
| spectral/periodogram | 0.0206 | 0.0208 | 1.8e-07 |
| filtering/firfilter_zi | 0.0561 | 0.169 | 0 |
| radartools/mvdr | 0.405 | 0.505 | 0 |
| filtering/lfilter | 0.526 | 1.68 | 1.39e-06 |
| windows/boxcar | 0.585 | 1.21 | 0 |
| filter_design/cmplx_sort | 0.811 | 0 | 0 |
| filtering/filtfilt | 0.872 | 1.43 | 7.49e-07 |
| spectral/welch | 1.32 | 1.66 | 3.16e-07 |
| spectral/coherence | 2.1 | 395 | 0.0127 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.811 | 0 |
| filter_design/kaiser_atten | 0 | 0.00295 | 0 |
| filter_design/kaiser_beta | 0 | 0.00299 | 0 |
| spectral/periodogram | 0.0208 | 0.0206 | 1.8e-07 |
| correlate/correlation_lags | 0.028 | 0.00619 | 0 |
| filtering/firfilter_zi | 0.169 | 0.0561 | 0 |
| radartools/mvdr | 0.505 | 0.405 | 0 |
| windows/boxcar | 1.21 | 0.585 | 0 |
| filtering/filtfilt | 1.43 | 0.872 | 7.49e-07 |
| spectral/welch | 1.66 | 1.32 | 3.16e-07 |
| filtering/lfilter | 1.68 | 0.526 | 1.39e-06 |
| peak_finding/argrelmax | 4.34 | 3.57 | 0 |
