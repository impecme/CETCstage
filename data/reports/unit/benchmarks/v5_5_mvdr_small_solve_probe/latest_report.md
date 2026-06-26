# All-Operator Benchmark Report

- run_id: `20260626_081958`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00621 | 0.0279 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.818 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00238 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00302 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.875 | 1.43 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0537 | 0.161 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.567 | 1.69 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.68 | 4.62 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.72 | 4.58 |
| radartools/mvdr | 1048576 | passed | 0 | 0.672 | 0.993 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.08 | 393 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 2.24 | 7.68 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.33 | 1.65 |
| windows/barthann | 1048576 | passed | 0 | 31.5 | 43.8 |
| windows/bartlett | 1048576 | passed | 0 | 8.92 | 14 |
| windows/blackman | 1048576 | passed | 0 | 39.1 | 48.3 |
| windows/blackmanharris | 1048576 | passed | 0 | 40.5 | 48.7 |
| windows/bohman | 1048576 | passed | 0 | 39.8 | 45.8 |
| windows/boxcar | 1048576 | passed | 0 | 0.568 | 1.21 |
| windows/cosine | 1048576 | passed | 0 | 57.6 | 77.4 |
| windows/exponential | 1048576 | passed | 0 | 57.1 | 82.8 |
| windows/flattop | 1048576 | passed | 0 | 42.9 | 47.9 |
| windows/gaussian | 1048576 | passed | 0 | 79.9 | 111 |
| windows/general_hamming | 1048576 | passed | 0 | 33.3 | 46.7 |
| windows/get_window | 1048576 | passed | 0 | 33.6 | 46.9 |
| windows/hann | 1048576 | passed | 0 | 33.7 | 46.6 |
| windows/nuttall | 1048576 | passed | 0 | 42.4 | 48.9 |
| windows/tukey | 1048576 | passed | 0 | 20.7 | 29 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.08 | 393 |
| filtering/lfilter | 1.39e-06 | 0.567 | 1.69 |
| filtering/filtfilt | 7.49e-07 | 0.875 | 1.43 |
| spectral/welch | 3.16e-07 | 1.33 | 1.65 |
| spectral/periodogram | 1.8e-07 | 2.24 | 7.68 |
| correlate/correlation_lags | 0 | 0.00621 | 0.0279 |
| filter_design/cmplx_sort | 0 | 0.818 | 0 |
| filter_design/kaiser_atten | 0 | 0.00238 | 0 |
| filter_design/kaiser_beta | 0 | 0.00302 | 0 |
| filtering/firfilter_zi | 0 | 0.0537 | 0.161 |
| peak_finding/argrelmax | 0 | 3.68 | 4.62 |
| peak_finding/argrelmin | 0 | 3.72 | 4.58 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_atten | 0.00238 | 0 | 0 |
| filter_design/kaiser_beta | 0.00302 | 0 | 0 |
| correlate/correlation_lags | 0.00621 | 0.0279 | 0 |
| filtering/firfilter_zi | 0.0537 | 0.161 | 0 |
| filtering/lfilter | 0.567 | 1.69 | 1.39e-06 |
| windows/boxcar | 0.568 | 1.21 | 0 |
| radartools/mvdr | 0.672 | 0.993 | 0 |
| filter_design/cmplx_sort | 0.818 | 0 | 0 |
| filtering/filtfilt | 0.875 | 1.43 | 7.49e-07 |
| spectral/welch | 1.33 | 1.65 | 3.16e-07 |
| spectral/coherence | 2.08 | 393 | 0.0127 |
| spectral/periodogram | 2.24 | 7.68 | 1.8e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.818 | 0 |
| filter_design/kaiser_atten | 0 | 0.00238 | 0 |
| filter_design/kaiser_beta | 0 | 0.00302 | 0 |
| correlate/correlation_lags | 0.0279 | 0.00621 | 0 |
| filtering/firfilter_zi | 0.161 | 0.0537 | 0 |
| radartools/mvdr | 0.993 | 0.672 | 0 |
| windows/boxcar | 1.21 | 0.568 | 0 |
| filtering/filtfilt | 1.43 | 0.875 | 7.49e-07 |
| spectral/welch | 1.65 | 1.33 | 3.16e-07 |
| filtering/lfilter | 1.69 | 0.567 | 1.39e-06 |
| peak_finding/argrelmin | 4.58 | 3.72 | 0 |
| peak_finding/argrelmax | 4.62 | 3.68 | 0 |
