# All-Operator Benchmark Report

- run_id: `20260626_085316`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.006 | 0.0288 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00285 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00481 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.863 | 1.41 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0535 | 0.16 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.616 | 1.69 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.76 | 4.6 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.78 | 4.61 |
| radartools/mvdr | 1048576 | passed | 0 | 1.92 | 25.1 |
| spectral/coherence | 32768 | passed | 0.00294 | 14.9 | 30.6 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 2.15 | 7.35 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.33 | 1.67 |
| windows/barthann | 1048576 | passed | 0 | 31.2 | 43.8 |
| windows/bartlett | 1048576 | passed | 0 | 7.12 | 13.9 |
| windows/blackman | 1048576 | passed | 0 | 38.2 | 48.3 |
| windows/blackmanharris | 1048576 | passed | 0 | 41.7 | 48.6 |
| windows/bohman | 1048576 | passed | 0 | 39.3 | 45.7 |
| windows/boxcar | 1048576 | passed | 0 | 0.573 | 1.21 |
| windows/cosine | 1048576 | passed | 0 | 59.4 | 77.4 |
| windows/exponential | 1048576 | passed | 0 | 59 | 83.2 |
| windows/flattop | 1048576 | passed | 0 | 39.1 | 48 |
| windows/gaussian | 1048576 | passed | 0 | 81.5 | 112 |
| windows/general_hamming | 1048576 | passed | 0 | 33.1 | 46.2 |
| windows/get_window | 1048576 | passed | 0 | 33 | 46.2 |
| windows/hann | 1048576 | passed | 0 | 46.5 | 64.5 |
| windows/nuttall | 1048576 | passed | 0 | 42 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 20.8 | 29 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00294 | 14.9 | 30.6 |
| filtering/lfilter | 1.39e-06 | 0.616 | 1.69 |
| filtering/filtfilt | 7.49e-07 | 0.863 | 1.41 |
| spectral/welch | 3.16e-07 | 1.33 | 1.67 |
| spectral/periodogram | 1.8e-07 | 2.15 | 7.35 |
| correlate/correlation_lags | 0 | 0.006 | 0.0288 |
| filter_design/cmplx_sort | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 0 | 0.00285 | 0 |
| filter_design/kaiser_beta | 0 | 0.00481 | 0 |
| filtering/firfilter_zi | 0 | 0.0535 | 0.16 |
| peak_finding/argrelmax | 0 | 3.76 | 4.6 |
| peak_finding/argrelmin | 0 | 3.78 | 4.61 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_atten | 0.00285 | 0 | 0 |
| filter_design/kaiser_beta | 0.00481 | 0 | 0 |
| correlate/correlation_lags | 0.006 | 0.0288 | 0 |
| filtering/firfilter_zi | 0.0535 | 0.16 | 0 |
| windows/boxcar | 0.573 | 1.21 | 0 |
| filtering/lfilter | 0.616 | 1.69 | 1.39e-06 |
| filter_design/cmplx_sort | 0.812 | 0 | 0 |
| filtering/filtfilt | 0.863 | 1.41 | 7.49e-07 |
| spectral/welch | 1.33 | 1.67 | 3.16e-07 |
| radartools/mvdr | 1.92 | 25.1 | 0 |
| spectral/periodogram | 2.15 | 7.35 | 1.8e-07 |
| peak_finding/argrelmax | 3.76 | 4.6 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 0 | 0.00285 | 0 |
| filter_design/kaiser_beta | 0 | 0.00481 | 0 |
| correlate/correlation_lags | 0.0288 | 0.006 | 0 |
| filtering/firfilter_zi | 0.16 | 0.0535 | 0 |
| windows/boxcar | 1.21 | 0.573 | 0 |
| filtering/filtfilt | 1.41 | 0.863 | 7.49e-07 |
| spectral/welch | 1.67 | 1.33 | 3.16e-07 |
| filtering/lfilter | 1.69 | 0.616 | 1.39e-06 |
| peak_finding/argrelmax | 4.6 | 3.76 | 0 |
| peak_finding/argrelmin | 4.61 | 3.78 | 0 |
| spectral/periodogram | 7.35 | 2.15 | 1.8e-07 |
