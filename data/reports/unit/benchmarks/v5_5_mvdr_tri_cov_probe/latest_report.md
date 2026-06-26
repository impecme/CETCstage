# All-Operator Benchmark Report

- run_id: `20260626_082946`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00603 | 0.0283 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.806 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00285 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00323 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.824 | 1.4 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0544 | 0.164 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.561 | 1.69 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.7 | 4.64 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.74 | 4.68 |
| radartools/mvdr | 1048576 | passed | 0 | 0.674 | 1 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.08 | 392 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 2.34 | 7.66 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.34 | 1.66 |
| windows/barthann | 1048576 | passed | 0 | 31 | 43.8 |
| windows/bartlett | 1048576 | passed | 0 | 9.22 | 14 |
| windows/blackman | 1048576 | passed | 0 | 38.6 | 48.4 |
| windows/blackmanharris | 1048576 | passed | 0 | 41.5 | 48.6 |
| windows/bohman | 1048576 | passed | 0 | 39.4 | 45.8 |
| windows/boxcar | 1048576 | passed | 0 | 0.592 | 1.21 |
| windows/cosine | 1048576 | passed | 0 | 57.5 | 76.4 |
| windows/exponential | 1048576 | passed | 0 | 54.7 | 82 |
| windows/flattop | 1048576 | passed | 0 | 54.5 | 60.5 |
| windows/gaussian | 1048576 | passed | 0 | 79 | 113 |
| windows/general_hamming | 1048576 | passed | 0 | 33.7 | 46.6 |
| windows/get_window | 1048576 | passed | 0 | 33.1 | 46.1 |
| windows/hann | 1048576 | passed | 0 | 32.7 | 46.1 |
| windows/nuttall | 1048576 | passed | 0 | 41.7 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 21.2 | 29.1 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.08 | 392 |
| filtering/lfilter | 1.39e-06 | 0.561 | 1.69 |
| filtering/filtfilt | 7.49e-07 | 0.824 | 1.4 |
| spectral/welch | 3.16e-07 | 1.34 | 1.66 |
| spectral/periodogram | 1.8e-07 | 2.34 | 7.66 |
| correlate/correlation_lags | 0 | 0.00603 | 0.0283 |
| filter_design/cmplx_sort | 0 | 0.806 | 0 |
| filter_design/kaiser_atten | 0 | 0.00285 | 0 |
| filter_design/kaiser_beta | 0 | 0.00323 | 0 |
| filtering/firfilter_zi | 0 | 0.0544 | 0.164 |
| peak_finding/argrelmax | 0 | 3.7 | 4.64 |
| peak_finding/argrelmin | 0 | 3.74 | 4.68 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_atten | 0.00285 | 0 | 0 |
| filter_design/kaiser_beta | 0.00323 | 0 | 0 |
| correlate/correlation_lags | 0.00603 | 0.0283 | 0 |
| filtering/firfilter_zi | 0.0544 | 0.164 | 0 |
| filtering/lfilter | 0.561 | 1.69 | 1.39e-06 |
| windows/boxcar | 0.592 | 1.21 | 0 |
| radartools/mvdr | 0.674 | 1 | 0 |
| filter_design/cmplx_sort | 0.806 | 0 | 0 |
| filtering/filtfilt | 0.824 | 1.4 | 7.49e-07 |
| spectral/welch | 1.34 | 1.66 | 3.16e-07 |
| spectral/coherence | 2.08 | 392 | 0.0127 |
| spectral/periodogram | 2.34 | 7.66 | 1.8e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.806 | 0 |
| filter_design/kaiser_atten | 0 | 0.00285 | 0 |
| filter_design/kaiser_beta | 0 | 0.00323 | 0 |
| correlate/correlation_lags | 0.0283 | 0.00603 | 0 |
| filtering/firfilter_zi | 0.164 | 0.0544 | 0 |
| radartools/mvdr | 1 | 0.674 | 0 |
| windows/boxcar | 1.21 | 0.592 | 0 |
| filtering/filtfilt | 1.4 | 0.824 | 7.49e-07 |
| spectral/welch | 1.66 | 1.34 | 3.16e-07 |
| filtering/lfilter | 1.69 | 0.561 | 1.39e-06 |
| peak_finding/argrelmax | 4.64 | 3.7 | 0 |
| peak_finding/argrelmin | 4.68 | 3.74 | 0 |
