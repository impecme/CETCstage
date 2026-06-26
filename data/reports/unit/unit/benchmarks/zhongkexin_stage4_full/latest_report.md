# All-Operator Benchmark Report

- run_id: `20260618_021842`
- scale_profile: `default`
- rows: `486`
- operators: `81`
- passed_rows: `486`
- status: passed=486
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.774 | 0.808 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.88 | 2.96 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.602 | 0.634 |
| correlate/correlate | 8192 | passed | 0 | 11.3 | 21.8 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.68 | 13.1 |
| correlate/correlation_lags | 8192 | passed | 0 | 0.00612 | 0.0277 |
| demod/fm_demod | 1048576 | passed | 0 | 28.6 | 36.6 |
| estimation/kalman_filter | 512 | passed | 0 | 1.18 | 2.49 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.814 | 0 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.74 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.702 | 0.915 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00123 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.000947 | 0 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.1 | 11.6 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4.02 | 4.57 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.739 | 1.84 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.00061 | 0.00061 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.5 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.61 | 3.07 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0456 | 0.136 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 8.18 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.36 | 8.1 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 35.9 | 36.7 |
| filtering/lfilter | 32768 | passed | 0 | 0.00045 | 0.000451 |
| filtering/lfilter_zi | 512 | passed | 0 | 33 | 59.2 |
| filtering/resample | 32768 | passed | 3.85e-05 | 5.77 | 7.21 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.2 | 18.4 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.82 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.74 | 6.26 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 3.26 | 3.27 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.5 | 41.1 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 38.7 | 41.4 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 38.9 | 41.7 |
| radartools/ambgfun | 8192 | passed | 0 | 46.5 | 46.6 |
| radartools/ca_cfar | 1048576 | passed | 0 | 3.98 | 4.48 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00236 | 0 |
| radartools/mvdr | 1048576 | passed | 0 | 0.406 | 0.502 |
| radartools/pulse_compression | 1048576 | passed | 0 | 53.5 | 57.5 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31 | 66.6 |
| spectral/coherence | 32768 | passed | 0.00326 | 1.46 | 405 |
| spectral/csd | 32768 | passed | 3.95e-07 | 1.83 | 1.96 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.71 | 12.4 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.9 | 68.4 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0253 | 0.0256 |
| spectral/spectrogram | 32768 | passed | 7.17e-06 | 6.79 | 7.46 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.1 | 16.6 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.3 | 30.2 |
| spectral/welch | 32768 | passed | 3.63e-07 | 1.29 | 1.65 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.7 | 66.8 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.5 | 73.2 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 38.6 | 44.2 |
| waveforms/square | 1048576 | passed | 0 | 44.6 | 53 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 19.8 | 114 |
| wavelets/cwt | 32768 | passed | 0 | 215 | 222 |
| wavelets/morlet | 1048576 | passed | 0 | 1.59 | 1.6 |
| wavelets/morlet2 | 1048576 | passed | 0 | 2.88 | 2.9 |
| wavelets/qmf | 1048576 | passed | 0 | 18 | 24.8 |
| wavelets/ricker | 1048576 | passed | 0 | 0.446 | 0.446 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.33 |
| windows/bartlett | 1048576 | passed | 0 | 0.223 | 0.226 |
| windows/blackman | 1048576 | passed | 0 | 5.91 | 6.04 |
| windows/blackmanharris | 1048576 | passed | 0 | 8.73 | 8.95 |
| windows/bohman | 1048576 | passed | 0 | 2.42 | 2.45 |
| windows/boxcar | 1048576 | passed | 0 | 0.013 | 0.0132 |
| windows/chebwin | 1536 | passed | 0 | 1.71 | 8.92 |
| windows/cosine | 1048576 | passed | 0 | 0.272 | 0.273 |
| windows/exponential | 1048576 | passed | 0 | 1.69 | 1.72 |
| windows/flattop | 1048576 | passed | 0 | 11.4 | 11.6 |
| windows/gaussian | 1048576 | passed | 0 | 2.3 | 2.33 |
| windows/general_cosine | 1048576 | passed | 0 | 9.42 | 9.66 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.05 | 6.14 |
| windows/general_hamming | 1048576 | passed | 0 | 3.46 | 3.54 |
| windows/get_window | 1048576 | passed | 0 | 3.46 | 3.53 |
| windows/hamming | 1048576 | passed | 0 | 3.47 | 3.54 |
| windows/hann | 1048576 | passed | 0 | 3.47 | 3.53 |
| windows/kaiser | 1048576 | passed | 0 | 197 | 219 |
| windows/nuttall | 1048576 | passed | 0 | 8.76 | 8.94 |
| windows/parzen | 1048576 | passed | 0 | 0.416 | 0.421 |
| windows/taylor | 1048576 | passed | 0 | 3.17 | 3.19 |
| windows/triang | 1048576 | passed | 0 | 0.0847 | 0.0844 |
| windows/tukey | 1048576 | passed | 0 | 0.875 | 0.889 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00326 | 1.46 | 405 |
| filter_design/firwin2 | 7.58e-05 | 0.702 | 0.915 |
| filtering/channelize_poly | 5.7e-05 | 10.1 | 11.6 |
| filtering/resample | 3.85e-05 | 5.77 | 7.21 |
| spectral/vectorstrength | 3.6e-05 | 28.3 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 35.9 | 36.7 |
| filter_design/firwin | 1.09e-05 | 4.74 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 67.9 | 68.4 |
| spectral/spectrogram | 7.17e-06 | 6.79 | 7.46 |
| filtering/detrend | 4.59e-06 | 0.739 | 1.84 |
| waveforms/chirp | 3.92e-06 | 63.7 | 66.8 |
| spectral/istft | 3.43e-06 | 3.71 | 12.4 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.00045 | 0.000451 | 0 |
| filtering/filtfilt | 0.00061 | 0.00061 | 1.97e-07 |
| filter_design/kaiser_beta | 0.000947 | 0 | 0 |
| filter_design/kaiser_atten | 0.00123 | 0 | 0 |
| radartools/cfar_alpha | 0.00236 | 0 | 0 |
| correlate/correlation_lags | 0.00612 | 0.0277 | 0 |
| windows/boxcar | 0.013 | 0.0132 | 0 |
| spectral/periodogram | 0.0253 | 0.0256 | 1.8e-07 |
| filtering/firfilter_zi | 0.0456 | 0.136 | 0 |
| windows/triang | 0.0847 | 0.0844 | 0 |
| windows/bartlett | 0.223 | 0.226 | 0 |
| windows/cosine | 0.272 | 0.273 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.814 | 0 |
| filter_design/kaiser_atten | 0 | 0.00123 | 0 |
| filter_design/kaiser_beta | 0 | 0.000947 | 0 |
| radartools/cfar_alpha | 0 | 0.00236 | 0 |
| filtering/lfilter | 0.000451 | 0.00045 | 0 |
| filtering/filtfilt | 0.00061 | 0.00061 | 1.97e-07 |
| windows/boxcar | 0.0132 | 0.013 | 0 |
| spectral/periodogram | 0.0256 | 0.0253 | 1.8e-07 |
| correlate/correlation_lags | 0.0277 | 0.00612 | 0 |
| windows/triang | 0.0844 | 0.0847 | 0 |
| filtering/firfilter_zi | 0.136 | 0.0456 | 0 |
| windows/bartlett | 0.226 | 0.223 | 0 |
