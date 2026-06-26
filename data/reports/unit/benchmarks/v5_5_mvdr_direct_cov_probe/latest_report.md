# All-Operator Benchmark Report

- run_id: `20260626_080913`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00619 | 0.0287 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.817 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00288 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00352 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.846 | 1.39 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0534 | 0.163 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.562 | 1.69 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.69 | 4.64 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.8 | 4.74 |
| radartools/mvdr | 1048576 | passed | 0 | 0.66 | 0.968 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.06 | 231 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 2.18 | 7.58 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.34 | 1.65 |
| windows/barthann | 1048576 | passed | 0 | 30.1 | 43.8 |
| windows/bartlett | 1048576 | passed | 0 | 9.08 | 14 |
| windows/blackman | 1048576 | passed | 0 | 39.1 | 48.3 |
| windows/blackmanharris | 1048576 | passed | 0 | 42 | 48.6 |
| windows/bohman | 1048576 | passed | 0 | 40.1 | 45.6 |
| windows/boxcar | 1048576 | passed | 0 | 0.586 | 1.22 |
| windows/cosine | 1048576 | passed | 0 | 56.9 | 77.4 |
| windows/exponential | 1048576 | passed | 0 | 58.6 | 82 |
| windows/flattop | 1048576 | passed | 0 | 43.2 | 47.9 |
| windows/gaussian | 1048576 | passed | 0 | 78.8 | 112 |
| windows/general_hamming | 1048576 | passed | 0 | 33.2 | 46 |
| windows/get_window | 1048576 | passed | 0 | 33.2 | 46.2 |
| windows/hann | 1048576 | passed | 0 | 33.2 | 46.2 |
| windows/nuttall | 1048576 | passed | 0 | 42.3 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 20.9 | 29.1 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.06 | 231 |
| filtering/lfilter | 1.39e-06 | 0.562 | 1.69 |
| filtering/filtfilt | 7.49e-07 | 0.846 | 1.39 |
| spectral/welch | 3.16e-07 | 1.34 | 1.65 |
| spectral/periodogram | 1.8e-07 | 2.18 | 7.58 |
| correlate/correlation_lags | 0 | 0.00619 | 0.0287 |
| filter_design/cmplx_sort | 0 | 0.817 | 0 |
| filter_design/kaiser_atten | 0 | 0.00288 | 0 |
| filter_design/kaiser_beta | 0 | 0.00352 | 0 |
| filtering/firfilter_zi | 0 | 0.0534 | 0.163 |
| peak_finding/argrelmax | 0 | 3.69 | 4.64 |
| peak_finding/argrelmin | 0 | 3.8 | 4.74 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_atten | 0.00288 | 0 | 0 |
| filter_design/kaiser_beta | 0.00352 | 0 | 0 |
| correlate/correlation_lags | 0.00619 | 0.0287 | 0 |
| filtering/firfilter_zi | 0.0534 | 0.163 | 0 |
| filtering/lfilter | 0.562 | 1.69 | 1.39e-06 |
| windows/boxcar | 0.586 | 1.22 | 0 |
| radartools/mvdr | 0.66 | 0.968 | 0 |
| filter_design/cmplx_sort | 0.817 | 0 | 0 |
| filtering/filtfilt | 0.846 | 1.39 | 7.49e-07 |
| spectral/welch | 1.34 | 1.65 | 3.16e-07 |
| spectral/coherence | 2.06 | 231 | 0.0127 |
| spectral/periodogram | 2.18 | 7.58 | 1.8e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.817 | 0 |
| filter_design/kaiser_atten | 0 | 0.00288 | 0 |
| filter_design/kaiser_beta | 0 | 0.00352 | 0 |
| correlate/correlation_lags | 0.0287 | 0.00619 | 0 |
| filtering/firfilter_zi | 0.163 | 0.0534 | 0 |
| radartools/mvdr | 0.968 | 0.66 | 0 |
| windows/boxcar | 1.22 | 0.586 | 0 |
| filtering/filtfilt | 1.39 | 0.846 | 7.49e-07 |
| spectral/welch | 1.65 | 1.34 | 3.16e-07 |
| filtering/lfilter | 1.69 | 0.562 | 1.39e-06 |
| peak_finding/argrelmax | 4.64 | 3.69 | 0 |
| peak_finding/argrelmin | 4.74 | 3.8 | 0 |
