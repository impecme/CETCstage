# All-Operator Benchmark Report

- run_id: `20260626_062236`
- scale_profile: `default`
- rows: `28`
- operators: `28`
- passed_rows: `28`
- status: passed=28
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| correlate/correlation_lags | 8192 | passed | 0 | 0.00712 | 0.0316 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.807 | 0 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00302 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00297 | 0 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.000619 | 0.000618 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0534 | 0.158 |
| filtering/lfilter | 32768 | passed | 0 | 0.000451 | 0.000452 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 3.85 | 4.72 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 3.81 | 4.71 |
| radartools/mvdr | 1048576 | passed | 0 | 0.406 | 0.505 |
| spectral/coherence | 32768 | passed | 0.0127 | 2.1 | 401 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0194 | 0.0196 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.33 | 1.66 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.34 |
| windows/bartlett | 1048576 | passed | 0 | 0.224 | 0.229 |
| windows/blackman | 1048576 | passed | 0 | 38.6 | 48.4 |
| windows/blackmanharris | 1048576 | passed | 0 | 42 | 48.7 |
| windows/bohman | 1048576 | passed | 0 | 2.4 | 2.44 |
| windows/boxcar | 1048576 | passed | 0 | 0.0126 | 0.013 |
| windows/cosine | 1048576 | passed | 0 | 0.275 | 0.275 |
| windows/exponential | 1048576 | passed | 0 | 1.64 | 1.66 |
| windows/flattop | 1048576 | passed | 0 | 43.6 | 48.1 |
| windows/gaussian | 1048576 | passed | 0 | 2.21 | 2.24 |
| windows/general_hamming | 1048576 | passed | 0 | 33.5 | 46.1 |
| windows/get_window | 1048576 | passed | 0 | 34 | 46.2 |
| windows/hann | 1048576 | passed | 0 | 33.6 | 46.2 |
| windows/nuttall | 1048576 | passed | 0 | 40.3 | 48.7 |
| windows/tukey | 1048576 | passed | 0 | 0.881 | 0.895 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.0127 | 2.1 | 401 |
| spectral/welch | 3.16e-07 | 1.33 | 1.66 |
| filtering/filtfilt | 1.97e-07 | 0.000619 | 0.000618 |
| spectral/periodogram | 1.8e-07 | 0.0194 | 0.0196 |
| correlate/correlation_lags | 0 | 0.00712 | 0.0316 |
| filter_design/cmplx_sort | 0 | 0.807 | 0 |
| filter_design/kaiser_atten | 0 | 0.00302 | 0 |
| filter_design/kaiser_beta | 0 | 0.00297 | 0 |
| filtering/firfilter_zi | 0 | 0.0534 | 0.158 |
| filtering/lfilter | 0 | 0.000451 | 0.000452 |
| peak_finding/argrelmax | 0 | 3.85 | 4.72 |
| peak_finding/argrelmin | 0 | 3.81 | 4.71 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.000451 | 0.000452 | 0 |
| filtering/filtfilt | 0.000619 | 0.000618 | 1.97e-07 |
| filter_design/kaiser_beta | 0.00297 | 0 | 0 |
| filter_design/kaiser_atten | 0.00302 | 0 | 0 |
| correlate/correlation_lags | 0.00712 | 0.0316 | 0 |
| windows/boxcar | 0.0126 | 0.013 | 0 |
| spectral/periodogram | 0.0194 | 0.0196 | 1.8e-07 |
| filtering/firfilter_zi | 0.0534 | 0.158 | 0 |
| windows/bartlett | 0.224 | 0.229 | 0 |
| windows/cosine | 0.275 | 0.275 | 0 |
| radartools/mvdr | 0.406 | 0.505 | 0 |
| filter_design/cmplx_sort | 0.807 | 0 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.807 | 0 |
| filter_design/kaiser_atten | 0 | 0.00302 | 0 |
| filter_design/kaiser_beta | 0 | 0.00297 | 0 |
| filtering/lfilter | 0.000452 | 0.000451 | 0 |
| filtering/filtfilt | 0.000618 | 0.000619 | 1.97e-07 |
| windows/boxcar | 0.013 | 0.0126 | 0 |
| spectral/periodogram | 0.0196 | 0.0194 | 1.8e-07 |
| correlate/correlation_lags | 0.0316 | 0.00712 | 0 |
| filtering/firfilter_zi | 0.158 | 0.0534 | 0 |
| windows/bartlett | 0.229 | 0.224 | 0 |
| windows/cosine | 0.275 | 0.275 | 0 |
| radartools/mvdr | 0.505 | 0.406 | 0 |
