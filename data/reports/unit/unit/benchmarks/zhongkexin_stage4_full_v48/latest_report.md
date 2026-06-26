# All-Operator Benchmark Report

- run_id: `20260618_095751`
- scale_profile: `default`
- rows: `486`
- operators: `81`
- passed_rows: `486`
- status: passed=486
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.78 | 0.814 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.9 | 2.97 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.593 | 0.618 |
| correlate/correlate | 8192 | passed | 0 | 12 | 23.4 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.62 | 13.1 |
| correlate/correlation_lags | 8192 | passed | 0 | 0.00601 | 0.0278 |
| demod/fm_demod | 1048576 | passed | 0 | 28.6 | 36.6 |
| estimation/kalman_filter | 512 | passed | 0 | 1.11 | 2.98 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.814 | 0 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.65 | 13.7 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.696 | 0.904 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.000941 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.000953 | 0 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 9.84 | 11.6 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.9 | 4.42 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.738 | 1.85 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.00062 | 0.000621 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.6 | 3.06 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0444 | 0.133 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 8.26 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.44 | 8 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 28.2 | 28.7 |
| filtering/lfilter | 32768 | passed | 0 | 0.00045 | 0.00045 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.7 | 54.4 |
| filtering/resample | 32768 | passed | 3.85e-05 | 5.46 | 7.1 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.1 | 18.3 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.819 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.7 | 6.24 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 3.31 | 3.32 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.2 | 40.9 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 38.6 | 41.3 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 38.8 | 41.6 |
| radartools/ambgfun | 8192 | passed | 0 | 47.4 | 47.5 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.17 | 4.71 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00232 | 0 |
| radartools/mvdr | 1048576 | passed | 0 | 0.407 | 0.505 |
| radartools/pulse_compression | 1048576 | passed | 0 | 53.4 | 57.7 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 30.9 | 66.9 |
| spectral/coherence | 32768 | passed | 0.00326 | 1.46 | 403 |
| spectral/csd | 32768 | passed | 3.95e-07 | 1.84 | 1.96 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.7 | 12.3 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.8 | 68.3 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0251 | 0.0254 |
| spectral/spectrogram | 32768 | passed | 7.17e-06 | 6.74 | 7.39 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.4 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.1 |
| spectral/welch | 32768 | passed | 3.63e-07 | 1.28 | 1.65 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.6 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67 | 73.2 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 38.4 | 44.2 |
| waveforms/square | 1048576 | passed | 0 | 45.4 | 53.3 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 20.8 | 115 |
| wavelets/cwt | 32768 | passed | 0 | 213 | 222 |
| wavelets/morlet | 1048576 | passed | 0 | 1.6 | 1.61 |
| wavelets/morlet2 | 1048576 | passed | 0 | 3.13 | 3.15 |
| wavelets/qmf | 1048576 | passed | 0 | 19.7 | 26.9 |
| wavelets/ricker | 1048576 | passed | 0 | 0.447 | 0.448 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.33 |
| windows/bartlett | 1048576 | passed | 0 | 0.224 | 0.227 |
| windows/blackman | 1048576 | passed | 0 | 5.92 | 6.04 |
| windows/blackmanharris | 1048576 | passed | 0 | 8.73 | 8.94 |
| windows/bohman | 1048576 | passed | 0 | 2.41 | 2.45 |
| windows/boxcar | 1048576 | passed | 0 | 0.0132 | 0.0131 |
| windows/chebwin | 1536 | passed | 0 | 2.26 | 8.54 |
| windows/cosine | 1048576 | passed | 0 | 0.272 | 0.273 |
| windows/exponential | 1048576 | passed | 0 | 1.65 | 1.67 |
| windows/flattop | 1048576 | passed | 0 | 11.5 | 11.8 |
| windows/gaussian | 1048576 | passed | 0 | 2.3 | 2.33 |
| windows/general_cosine | 1048576 | passed | 0 | 9.47 | 9.67 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.04 | 6.14 |
| windows/general_hamming | 1048576 | passed | 0 | 3.47 | 3.53 |
| windows/get_window | 1048576 | passed | 0 | 3.47 | 3.53 |
| windows/hamming | 1048576 | passed | 0 | 3.47 | 3.55 |
| windows/hann | 1048576 | passed | 0 | 3.47 | 3.53 |
| windows/kaiser | 1048576 | passed | 0 | 196 | 219 |
| windows/nuttall | 1048576 | passed | 0 | 8.8 | 8.98 |
| windows/parzen | 1048576 | passed | 0 | 0.416 | 0.423 |
| windows/taylor | 1048576 | passed | 0 | 3.18 | 3.19 |
| windows/triang | 1048576 | passed | 0 | 0.0841 | 0.0845 |
| windows/tukey | 1048576 | passed | 0 | 0.875 | 0.883 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00326 | 1.46 | 403 |
| filter_design/firwin2 | 7.58e-05 | 0.696 | 0.904 |
| filtering/channelize_poly | 5.7e-05 | 9.84 | 11.6 |
| filtering/resample | 3.85e-05 | 5.46 | 7.1 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.1 |
| filtering/hilbert2 | 1.71e-05 | 28.2 | 28.7 |
| filter_design/firwin | 1.09e-05 | 4.65 | 13.7 |
| spectral/lombscargle | 8.72e-06 | 67.8 | 68.3 |
| spectral/spectrogram | 7.17e-06 | 6.74 | 7.39 |
| filtering/detrend | 4.59e-06 | 0.738 | 1.85 |
| waveforms/chirp | 3.92e-06 | 63.6 | 67 |
| spectral/istft | 3.43e-06 | 3.7 | 12.3 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.00045 | 0.00045 | 0 |
| filtering/filtfilt | 0.00062 | 0.000621 | 1.97e-07 |
| filter_design/kaiser_atten | 0.000941 | 0 | 0 |
| filter_design/kaiser_beta | 0.000953 | 0 | 0 |
| radartools/cfar_alpha | 0.00232 | 0 | 0 |
| correlate/correlation_lags | 0.00601 | 0.0278 | 0 |
| windows/boxcar | 0.0132 | 0.0131 | 0 |
| spectral/periodogram | 0.0251 | 0.0254 | 1.8e-07 |
| filtering/firfilter_zi | 0.0444 | 0.133 | 0 |
| windows/triang | 0.0841 | 0.0845 | 0 |
| windows/bartlett | 0.224 | 0.227 | 0 |
| windows/cosine | 0.272 | 0.273 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.814 | 0 |
| filter_design/kaiser_atten | 0 | 0.000941 | 0 |
| filter_design/kaiser_beta | 0 | 0.000953 | 0 |
| radartools/cfar_alpha | 0 | 0.00232 | 0 |
| filtering/lfilter | 0.00045 | 0.00045 | 0 |
| filtering/filtfilt | 0.000621 | 0.00062 | 1.97e-07 |
| windows/boxcar | 0.0131 | 0.0132 | 0 |
| spectral/periodogram | 0.0254 | 0.0251 | 1.8e-07 |
| correlate/correlation_lags | 0.0278 | 0.00601 | 0 |
| windows/triang | 0.0845 | 0.0841 | 0 |
| filtering/firfilter_zi | 0.133 | 0.0444 | 0 |
| windows/bartlett | 0.227 | 0.224 | 0 |
