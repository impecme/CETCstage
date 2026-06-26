# All-Operator Benchmark Report

- run_id: `20260626_084751`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00636 | 0.0287 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00291 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00286 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.855 | 1.41 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0536 | 0.161 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.562 | 1.69 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.69 | 4.51 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.77 | 4.49 |
| radartools/mvdr | 1048576 | passed | 0 | 1.92 | 25.1 |
| spectral/coherence | 32768 | passed | 0.00294 | 14.7 | 30.6 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 2.19 | 7.47 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.33 | 1.67 |
| windows/barthann | 1048576 | passed | 0 | 31.2 | 43.9 |
| windows/bartlett | 1048576 | passed | 0 | 8.78 | 14 |
| windows/blackman | 1048576 | passed | 0 | 38.5 | 48.3 |
| windows/blackmanharris | 1048576 | passed | 0 | 41.6 | 48.6 |
| windows/bohman | 1048576 | passed | 0 | 39.9 | 45.8 |
| windows/boxcar | 1048576 | passed | 0 | 0.598 | 1.21 |
| windows/cosine | 1048576 | passed | 0 | 56 | 77.5 |
| windows/exponential | 1048576 | passed | 0 | 53.8 | 81.8 |
| windows/flattop | 1048576 | passed | 0 | 43.2 | 48 |
| windows/gaussian | 1048576 | passed | 0 | 80.5 | 112 |
| windows/general_hamming | 1048576 | passed | 0 | 33.2 | 46 |
| windows/get_window | 1048576 | passed | 0 | 32.8 | 46.9 |
| windows/hann | 1048576 | passed | 0 | 33.3 | 46 |
| windows/nuttall | 1048576 | passed | 0 | 40.3 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 21 | 28.9 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00294 | 14.7 | 30.6 |
| filtering/lfilter | 1.39e-06 | 0.562 | 1.69 |
| filtering/filtfilt | 7.49e-07 | 0.855 | 1.41 |
| spectral/welch | 3.16e-07 | 1.33 | 1.67 |
| spectral/periodogram | 1.8e-07 | 2.19 | 7.47 |
| correlate/correlation_lags | 0 | 0.00636 | 0.0287 |
| filter_design/cmplx_sort | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 0 | 0.00291 | 0 |
| filter_design/kaiser_beta | 0 | 0.00286 | 0 |
| filtering/firfilter_zi | 0 | 0.0536 | 0.161 |
| peak_finding/argrelmax | 0 | 3.69 | 4.51 |
| peak_finding/argrelmin | 0 | 3.77 | 4.49 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_beta | 0.00286 | 0 | 0 |
| filter_design/kaiser_atten | 0.00291 | 0 | 0 |
| correlate/correlation_lags | 0.00636 | 0.0287 | 0 |
| filtering/firfilter_zi | 0.0536 | 0.161 | 0 |
| filtering/lfilter | 0.562 | 1.69 | 1.39e-06 |
| windows/boxcar | 0.598 | 1.21 | 0 |
| filter_design/cmplx_sort | 0.812 | 0 | 0 |
| filtering/filtfilt | 0.855 | 1.41 | 7.49e-07 |
| spectral/welch | 1.33 | 1.67 | 3.16e-07 |
| radartools/mvdr | 1.92 | 25.1 | 0 |
| spectral/periodogram | 2.19 | 7.47 | 1.8e-07 |
| peak_finding/argrelmax | 3.69 | 4.51 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 0 | 0.00291 | 0 |
| filter_design/kaiser_beta | 0 | 0.00286 | 0 |
| correlate/correlation_lags | 0.0287 | 0.00636 | 0 |
| filtering/firfilter_zi | 0.161 | 0.0536 | 0 |
| windows/boxcar | 1.21 | 0.598 | 0 |
| filtering/filtfilt | 1.41 | 0.855 | 7.49e-07 |
| spectral/welch | 1.67 | 1.33 | 3.16e-07 |
| filtering/lfilter | 1.69 | 0.562 | 1.39e-06 |
| peak_finding/argrelmin | 4.49 | 3.77 | 0 |
| peak_finding/argrelmax | 4.51 | 3.69 | 0 |
| spectral/periodogram | 7.47 | 2.19 | 1.8e-07 |
