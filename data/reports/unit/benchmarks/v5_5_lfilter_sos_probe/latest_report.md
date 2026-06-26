# All-Operator Benchmark Report

- run_id: `20260626_064829`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00636 | 0.0284 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00281 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00299 | 0 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.866 | 1.41 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0554 | 0.163 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.572 | 1.69 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.71 | 4.65 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.88 | 4.78 |
| radartools/mvdr | 1048576 | passed | 0 | 0.406 | 0.505 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.12 | 397 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0202 | 0.0204 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.34 | 1.66 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.33 |
| windows/bartlett | 1048576 | passed | 0 | 0.22 | 0.228 |
| windows/blackman | 1048576 | passed | 0 | 37.9 | 48.5 |
| windows/blackmanharris | 1048576 | passed | 0 | 42.3 | 48.6 |
| windows/bohman | 1048576 | passed | 0 | 2.42 | 2.45 |
| windows/boxcar | 1048576 | passed | 0 | 0.0132 | 0.0132 |
| windows/cosine | 1048576 | passed | 0 | 0.274 | 0.275 |
| windows/exponential | 1048576 | passed | 0 | 1.64 | 1.66 |
| windows/flattop | 1048576 | passed | 0 | 43.4 | 48 |
| windows/gaussian | 1048576 | passed | 0 | 2.2 | 2.25 |
| windows/general_hamming | 1048576 | passed | 0 | 33.8 | 46.2 |
| windows/get_window | 1048576 | passed | 0 | 33.7 | 46.6 |
| windows/hann | 1048576 | passed | 0 | 33.3 | 46.2 |
| windows/nuttall | 1048576 | passed | 0 | 41.3 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 0.868 | 0.886 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.12 | 397 |
| filtering/lfilter | 1.39e-06 | 0.572 | 1.69 |
| filtering/filtfilt | 7.49e-07 | 0.866 | 1.41 |
| spectral/welch | 3.16e-07 | 1.34 | 1.66 |
| spectral/periodogram | 1.8e-07 | 0.0202 | 0.0204 |
| correlate/correlation_lags | 0 | 0.00636 | 0.0284 |
| filter_design/cmplx_sort | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 0 | 0.00281 | 0 |
| filter_design/kaiser_beta | 0 | 0.00299 | 0 |
| filtering/firfilter_zi | 0 | 0.0554 | 0.163 |
| peak_finding/argrelmax | 0 | 3.71 | 4.65 |
| peak_finding/argrelmin | 0 | 3.88 | 4.78 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/kaiser_atten | 0.00281 | 0 | 0 |
| filter_design/kaiser_beta | 0.00299 | 0 | 0 |
| correlate/correlation_lags | 0.00636 | 0.0284 | 0 |
| windows/boxcar | 0.0132 | 0.0132 | 0 |
| spectral/periodogram | 0.0202 | 0.0204 | 1.8e-07 |
| filtering/firfilter_zi | 0.0554 | 0.163 | 0 |
| windows/bartlett | 0.22 | 0.228 | 0 |
| windows/cosine | 0.274 | 0.275 | 0 |
| radartools/mvdr | 0.406 | 0.505 | 0 |
| filtering/lfilter | 0.572 | 1.69 | 1.39e-06 |
| filter_design/cmplx_sort | 0.812 | 0 | 0 |
| filtering/filtfilt | 0.866 | 1.41 | 7.49e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.812 | 0 |
| filter_design/kaiser_atten | 0 | 0.00281 | 0 |
| filter_design/kaiser_beta | 0 | 0.00299 | 0 |
| windows/boxcar | 0.0132 | 0.0132 | 0 |
| spectral/periodogram | 0.0204 | 0.0202 | 1.8e-07 |
| correlate/correlation_lags | 0.0284 | 0.00636 | 0 |
| filtering/firfilter_zi | 0.163 | 0.0554 | 0 |
| windows/bartlett | 0.228 | 0.22 | 0 |
| windows/cosine | 0.275 | 0.274 | 0 |
| radartools/mvdr | 0.505 | 0.406 | 0 |
| windows/tukey | 0.886 | 0.868 | 0 |
| windows/barthann | 1.33 | 1.31 | 0 |
