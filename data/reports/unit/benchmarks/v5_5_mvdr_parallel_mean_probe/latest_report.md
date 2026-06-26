# All-Operator Benchmark Report

- run_id: `20260626_083932`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00599 | 0.0279 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.809 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00182 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00328 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.881 | 1.44 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0563 | 0.167 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.56 | 1.7 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.67 | 4.57 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.81 | 4.66 |
| radartools/mvdr | 1048576 | passed | 0 | 1.91 | 25.1 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.07 | 394 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 2.2 | 7.55 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.38 | 1.72 |
| windows/barthann | 1048576 | passed | 0 | 31.7 | 43.8 |
| windows/bartlett | 1048576 | passed | 0 | 8.99 | 14 |
| windows/blackman | 1048576 | passed | 0 | 38.7 | 48.4 |
| windows/blackmanharris | 1048576 | passed | 0 | 41.9 | 48.8 |
| windows/bohman | 1048576 | passed | 0 | 39.7 | 45.6 |
| windows/boxcar | 1048576 | passed | 0 | 0.606 | 1.21 |
| windows/cosine | 1048576 | passed | 0 | 55.9 | 77.5 |
| windows/exponential | 1048576 | passed | 0 | 58.5 | 81.7 |
| windows/flattop | 1048576 | passed | 0 | 42.9 | 47.8 |
| windows/gaussian | 1048576 | passed | 0 | 78.8 | 112 |
| windows/general_hamming | 1048576 | passed | 0 | 33.5 | 46.3 |
| windows/get_window | 1048576 | passed | 0 | 33.7 | 46.2 |
| windows/hann | 1048576 | passed | 0 | 33.7 | 46.2 |
| windows/nuttall | 1048576 | passed | 0 | 41.9 | 48.8 |
| windows/tukey | 1048576 | passed | 0 | 21 | 29 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.07 | 394 |
| filtering/lfilter | 1.39e-06 | 0.56 | 1.7 |
| filtering/filtfilt | 7.49e-07 | 0.881 | 1.44 |
| spectral/welch | 3.16e-07 | 1.38 | 1.72 |
| spectral/periodogram | 1.8e-07 | 2.2 | 7.55 |
| correlate/correlation_lags | 0 | 0.00599 | 0.0279 |
| filter_design/cmplx_sort | 0 | 0.809 | 0 |
| filter_design/kaiser_atten | 0 | 0.00182 | 0 |
| filter_design/kaiser_beta | 0 | 0.00328 | 0 |
| filtering/firfilter_zi | 0 | 0.0563 | 0.167 |
| peak_finding/argrelmax | 0 | 3.67 | 4.57 |
| peak_finding/argrelmin | 0 | 3.81 | 4.66 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_atten | 0.00182 | 0 | 0 |
| filter_design/kaiser_beta | 0.00328 | 0 | 0 |
| correlate/correlation_lags | 0.00599 | 0.0279 | 0 |
| filtering/firfilter_zi | 0.0563 | 0.167 | 0 |
| filtering/lfilter | 0.56 | 1.7 | 1.39e-06 |
| windows/boxcar | 0.606 | 1.21 | 0 |
| filter_design/cmplx_sort | 0.809 | 0 | 0 |
| filtering/filtfilt | 0.881 | 1.44 | 7.49e-07 |
| spectral/welch | 1.38 | 1.72 | 3.16e-07 |
| radartools/mvdr | 1.91 | 25.1 | 0 |
| spectral/coherence | 2.07 | 394 | 0.0127 |
| spectral/periodogram | 2.2 | 7.55 | 1.8e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.809 | 0 |
| filter_design/kaiser_atten | 0 | 0.00182 | 0 |
| filter_design/kaiser_beta | 0 | 0.00328 | 0 |
| correlate/correlation_lags | 0.0279 | 0.00599 | 0 |
| filtering/firfilter_zi | 0.167 | 0.0563 | 0 |
| windows/boxcar | 1.21 | 0.606 | 0 |
| filtering/filtfilt | 1.44 | 0.881 | 7.49e-07 |
| filtering/lfilter | 1.7 | 0.56 | 1.39e-06 |
| spectral/welch | 1.72 | 1.38 | 3.16e-07 |
| peak_finding/argrelmax | 4.57 | 3.67 | 0 |
| peak_finding/argrelmin | 4.66 | 3.81 | 0 |
| spectral/periodogram | 7.55 | 2.2 | 1.8e-07 |
