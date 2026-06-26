# All-Operator Benchmark Report

- run_id: `20260626_075853`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00636 | 0.0283 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00475 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.003 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.849 | 1.4 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0552 | 0.166 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.55 | 1.7 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.52 | 3.47 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.8 | 4.71 |
| radartools/mvdr | 1048576 | passed | 0 | 0.406 | 0.505 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.09 | 399 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 2.14 | 7.41 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.24 | 1.63 |
| windows/barthann | 1048576 | passed | 0 | 31.2 | 43.8 |
| windows/bartlett | 1048576 | passed | 0 | 9.08 | 14 |
| windows/blackman | 1048576 | passed | 0 | 38.5 | 48.3 |
| windows/blackmanharris | 1048576 | passed | 0 | 42 | 48.8 |
| windows/bohman | 1048576 | passed | 0 | 39.6 | 45.7 |
| windows/boxcar | 1048576 | passed | 0 | 0.588 | 1.21 |
| windows/cosine | 1048576 | passed | 0 | 57 | 77.6 |
| windows/exponential | 1048576 | passed | 0 | 57.5 | 81.7 |
| windows/flattop | 1048576 | passed | 0 | 43.1 | 47.8 |
| windows/gaussian | 1048576 | passed | 0 | 81 | 111 |
| windows/general_hamming | 1048576 | passed | 0 | 33.3 | 46.8 |
| windows/get_window | 1048576 | passed | 0 | 33.1 | 46.9 |
| windows/hann | 1048576 | passed | 0 | 29.3 | 46.5 |
| windows/nuttall | 1048576 | passed | 0 | 41.6 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 20.2 | 29.1 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.09 | 399 |
| filtering/lfilter | 1.39e-06 | 0.55 | 1.7 |
| filtering/filtfilt | 7.49e-07 | 0.849 | 1.4 |
| spectral/welch | 3.16e-07 | 1.24 | 1.63 |
| spectral/periodogram | 1.8e-07 | 2.14 | 7.41 |
| correlate/correlation_lags | 0 | 0.00636 | 0.0283 |
| filter_design/cmplx_sort | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 0 | 0.00475 | 0 |
| filter_design/kaiser_beta | 0 | 0.003 | 0 |
| filtering/firfilter_zi | 0 | 0.0552 | 0.166 |
| peak_finding/argrelmax | 0 | 3.52 | 3.47 |
| peak_finding/argrelmin | 0 | 3.8 | 4.71 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_beta | 0.003 | 0 | 0 |
| filter_design/kaiser_atten | 0.00475 | 0 | 0 |
| correlate/correlation_lags | 0.00636 | 0.0283 | 0 |
| filtering/firfilter_zi | 0.0552 | 0.166 | 0 |
| radartools/mvdr | 0.406 | 0.505 | 0 |
| filtering/lfilter | 0.55 | 1.7 | 1.39e-06 |
| windows/boxcar | 0.588 | 1.21 | 0 |
| filter_design/cmplx_sort | 0.812 | 0 | 0 |
| filtering/filtfilt | 0.849 | 1.4 | 7.49e-07 |
| spectral/welch | 1.24 | 1.63 | 3.16e-07 |
| spectral/coherence | 2.09 | 399 | 0.0127 |
| spectral/periodogram | 2.14 | 7.41 | 1.8e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 0 | 0.00475 | 0 |
| filter_design/kaiser_beta | 0 | 0.003 | 0 |
| correlate/correlation_lags | 0.0283 | 0.00636 | 0 |
| filtering/firfilter_zi | 0.166 | 0.0552 | 0 |
| radartools/mvdr | 0.505 | 0.406 | 0 |
| windows/boxcar | 1.21 | 0.588 | 0 |
| filtering/filtfilt | 1.4 | 0.849 | 7.49e-07 |
| spectral/welch | 1.63 | 1.24 | 3.16e-07 |
| filtering/lfilter | 1.7 | 0.55 | 1.39e-06 |
| peak_finding/argrelmax | 3.47 | 3.52 | 0 |
| peak_finding/argrelmin | 4.71 | 3.8 | 0 |
