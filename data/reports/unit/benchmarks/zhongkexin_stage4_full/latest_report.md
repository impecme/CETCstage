# All-Operator Benchmark Report

- run_id: `20260617_122207`
- scale_profile: `default`
- rows: `486`
- operators: `81`
- passed_rows: `486`
- status: passed=486
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.779 | 0.813 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.89 | 2.97 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.591 | 0.617 |
| correlate/correlate | 8192 | passed | 0 | 11.3 | 22 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.69 | 13.1 |
| correlate/correlation_lags | 8192 | passed | 0 | 0.00599 | 0.0275 |
| demod/fm_demod | 1048576 | passed | 0 | 28.9 | 36.9 |
| estimation/kalman_filter | 512 | passed | 0 | 1.18 | 2.51 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.815 | 0 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.65 | 13.8 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.535 | 0.862 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.000936 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.000945 | 0 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.6 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.91 | 4.39 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.733 | 1.85 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.000615 | 0.000615 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.5 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.61 | 3.08 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0444 | 0.134 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 8.11 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.35 | 8.01 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 33.9 | 34.5 |
| filtering/lfilter | 32768 | passed | 0 | 0.000451 | 0.00045 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.7 | 59.1 |
| filtering/resample | 32768 | passed | 3.85e-05 | 6.66 | 7.57 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.3 | 18.3 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.82 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 3.8 | 6.27 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 3.54 | 3.54 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.7 | 41.3 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 38.8 | 41.4 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 38.8 | 41.6 |
| radartools/ambgfun | 8192 | passed | 0 | 47.7 | 47.8 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.01 | 4.53 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00236 | 0 |
| radartools/mvdr | 1048576 | passed | 0 | 0.406 | 0.504 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.1 | 57.3 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.4 | 66.8 |
| spectral/coherence | 32768 | passed | 0.00326 | 1.46 | 402 |
| spectral/csd | 32768 | passed | 3.95e-07 | 1.82 | 1.95 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.65 | 12.1 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.9 | 68.4 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0251 | 0.0254 |
| spectral/spectrogram | 32768 | passed | 7.17e-06 | 6.71 | 7.38 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.5 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.2 |
| spectral/welch | 32768 | passed | 3.63e-07 | 1.29 | 1.64 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.8 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.2 | 73.1 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.9 | 42.4 |
| waveforms/square | 1048576 | passed | 0 | 44.6 | 53 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 20.6 | 114 |
| wavelets/cwt | 32768 | passed | 0 | 216 | 222 |
| wavelets/morlet | 1048576 | passed | 0 | 1.6 | 1.6 |
| wavelets/morlet2 | 1048576 | passed | 0 | 3.17 | 3.19 |
| wavelets/qmf | 1048576 | passed | 0 | 18.5 | 25.3 |
| wavelets/ricker | 1048576 | passed | 0 | 0.444 | 0.445 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.33 |
| windows/bartlett | 1048576 | passed | 0 | 0.224 | 0.227 |
| windows/blackman | 1048576 | passed | 0 | 5.99 | 6.09 |
| windows/blackmanharris | 1048576 | passed | 0 | 8.83 | 8.98 |
| windows/bohman | 1048576 | passed | 0 | 2.4 | 2.45 |
| windows/boxcar | 1048576 | passed | 0 | 0.0131 | 0.0132 |
| windows/chebwin | 1536 | passed | 0 | 2.3 | 8.56 |
| windows/cosine | 1048576 | passed | 0 | 0.272 | 0.273 |
| windows/exponential | 1048576 | passed | 0 | 1.69 | 1.71 |
| windows/flattop | 1048576 | passed | 0 | 11.3 | 11.6 |
| windows/gaussian | 1048576 | passed | 0 | 2.3 | 2.33 |
| windows/general_cosine | 1048576 | passed | 0 | 9.48 | 9.68 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.04 | 6.14 |
| windows/general_hamming | 1048576 | passed | 0 | 3.46 | 3.53 |
| windows/get_window | 1048576 | passed | 0 | 3.46 | 3.53 |
| windows/hamming | 1048576 | passed | 0 | 3.47 | 3.53 |
| windows/hann | 1048576 | passed | 0 | 3.46 | 3.54 |
| windows/kaiser | 1048576 | passed | 0 | 199 | 219 |
| windows/nuttall | 1048576 | passed | 0 | 8.74 | 8.95 |
| windows/parzen | 1048576 | passed | 0 | 0.418 | 0.422 |
| windows/taylor | 1048576 | passed | 0 | 3.17 | 3.19 |
| windows/triang | 1048576 | passed | 0 | 0.0845 | 0.085 |
| windows/tukey | 1048576 | passed | 0 | 0.879 | 0.886 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00326 | 1.46 | 402 |
| filter_design/firwin2 | 7.58e-05 | 0.535 | 0.862 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.6 |
| filtering/resample | 3.85e-05 | 6.66 | 7.57 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 33.9 | 34.5 |
| filter_design/firwin | 1.09e-05 | 4.65 | 13.8 |
| spectral/lombscargle | 8.72e-06 | 67.9 | 68.4 |
| spectral/spectrogram | 7.17e-06 | 6.71 | 7.38 |
| filtering/detrend | 4.59e-06 | 0.733 | 1.85 |
| waveforms/chirp | 3.92e-06 | 63.8 | 67 |
| spectral/istft | 3.43e-06 | 3.65 | 12.1 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.000451 | 0.00045 | 0 |
| filtering/filtfilt | 0.000615 | 0.000615 | 1.97e-07 |
| filter_design/kaiser_atten | 0.000936 | 0 | 0 |
| filter_design/kaiser_beta | 0.000945 | 0 | 0 |
| radartools/cfar_alpha | 0.00236 | 0 | 0 |
| correlate/correlation_lags | 0.00599 | 0.0275 | 0 |
| windows/boxcar | 0.0131 | 0.0132 | 0 |
| spectral/periodogram | 0.0251 | 0.0254 | 1.8e-07 |
| filtering/firfilter_zi | 0.0444 | 0.134 | 0 |
| windows/triang | 0.0845 | 0.085 | 0 |
| windows/bartlett | 0.224 | 0.227 | 0 |
| windows/cosine | 0.272 | 0.273 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.815 | 0 |
| filter_design/kaiser_atten | 0 | 0.000936 | 0 |
| filter_design/kaiser_beta | 0 | 0.000945 | 0 |
| radartools/cfar_alpha | 0 | 0.00236 | 0 |
| filtering/lfilter | 0.00045 | 0.000451 | 0 |
| filtering/filtfilt | 0.000615 | 0.000615 | 1.97e-07 |
| windows/boxcar | 0.0132 | 0.0131 | 0 |
| spectral/periodogram | 0.0254 | 0.0251 | 1.8e-07 |
| correlate/correlation_lags | 0.0275 | 0.00599 | 0 |
| windows/triang | 0.085 | 0.0845 | 0 |
| filtering/firfilter_zi | 0.134 | 0.0444 | 0 |
| windows/bartlett | 0.227 | 0.224 | 0 |
