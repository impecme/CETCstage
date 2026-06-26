# All-Operator Benchmark Report

- run_id: `20260618_041133`
- scale_profile: `default`
- rows: `486`
- operators: `81`
- passed_rows: `486`
- status: passed=486
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.781 | 0.815 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.89 | 2.96 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.604 | 0.629 |
| correlate/correlate | 8192 | passed | 0 | 11.7 | 22.6 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.64 | 12.8 |
| correlate/correlation_lags | 8192 | passed | 0 | 0.00622 | 0.028 |
| demod/fm_demod | 1048576 | passed | 0 | 28.8 | 36.7 |
| estimation/kalman_filter | 512 | passed | 0 | 1.18 | 2.48 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.825 | 0 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.68 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.696 | 0.909 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00094 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.000944 | 0 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.98 | 4.53 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.745 | 1.83 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.000614 | 0.000615 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.5 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.62 | 3.07 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0459 | 0.138 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 8.27 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.44 | 8.05 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 32.1 | 32.5 |
| filtering/lfilter | 32768 | passed | 0 | 0.000452 | 0.000451 |
| filtering/lfilter_zi | 512 | passed | 0 | 33 | 59.4 |
| filtering/resample | 32768 | passed | 3.85e-05 | 6.11 | 7.18 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.7 | 19 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.824 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 3.86 | 6.27 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 3.32 | 3.32 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.4 | 40.2 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 37.4 | 40 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 38.6 | 41.3 |
| radartools/ambgfun | 8192 | passed | 0 | 47.6 | 47.8 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.27 | 4.83 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00232 | 0 |
| radartools/mvdr | 1048576 | passed | 0 | 0.406 | 0.503 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.7 | 58.8 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.9 | 67.9 |
| spectral/coherence | 32768 | passed | 0.00326 | 1.4 | 238 |
| spectral/csd | 32768 | passed | 3.95e-07 | 1.84 | 1.96 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.72 | 12.3 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.5 | 68.2 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0247 | 0.025 |
| spectral/spectrogram | 32768 | passed | 7.17e-06 | 6.77 | 7.44 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.1 | 16.7 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 27.3 | 30.1 |
| spectral/welch | 32768 | passed | 3.63e-07 | 1.29 | 1.66 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.6 | 67.1 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 68.2 | 73.1 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.6 | 45.4 |
| waveforms/square | 1048576 | passed | 0 | 44.4 | 53 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 21.6 | 120 |
| wavelets/cwt | 32768 | passed | 0 | 215 | 222 |
| wavelets/morlet | 1048576 | passed | 0 | 1.62 | 1.63 |
| wavelets/morlet2 | 1048576 | passed | 0 | 3.15 | 3.17 |
| wavelets/qmf | 1048576 | passed | 0 | 19.4 | 26.7 |
| wavelets/ricker | 1048576 | passed | 0 | 0.448 | 0.448 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.33 |
| windows/bartlett | 1048576 | passed | 0 | 0.225 | 0.227 |
| windows/blackman | 1048576 | passed | 0 | 5.91 | 6.04 |
| windows/blackmanharris | 1048576 | passed | 0 | 8.74 | 8.95 |
| windows/bohman | 1048576 | passed | 0 | 2.41 | 2.45 |
| windows/boxcar | 1048576 | passed | 0 | 0.013 | 0.0132 |
| windows/chebwin | 1536 | passed | 0 | 2.24 | 8.45 |
| windows/cosine | 1048576 | passed | 0 | 0.273 | 0.273 |
| windows/exponential | 1048576 | passed | 0 | 1.65 | 1.67 |
| windows/flattop | 1048576 | passed | 0 | 11.3 | 11.6 |
| windows/gaussian | 1048576 | passed | 0 | 2.31 | 2.33 |
| windows/general_cosine | 1048576 | passed | 0 | 9.4 | 9.67 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.05 | 6.14 |
| windows/general_hamming | 1048576 | passed | 0 | 3.47 | 3.54 |
| windows/get_window | 1048576 | passed | 0 | 3.47 | 3.53 |
| windows/hamming | 1048576 | passed | 0 | 3.46 | 3.53 |
| windows/hann | 1048576 | passed | 0 | 3.47 | 3.54 |
| windows/kaiser | 1048576 | passed | 0 | 199 | 219 |
| windows/nuttall | 1048576 | passed | 0 | 8.8 | 8.97 |
| windows/parzen | 1048576 | passed | 0 | 0.414 | 0.422 |
| windows/taylor | 1048576 | passed | 0 | 3.17 | 3.19 |
| windows/triang | 1048576 | passed | 0 | 0.0846 | 0.0853 |
| windows/tukey | 1048576 | passed | 0 | 0.872 | 0.884 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00326 | 1.4 | 238 |
| filter_design/firwin2 | 7.58e-05 | 0.696 | 0.909 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.85e-05 | 6.11 | 7.18 |
| spectral/vectorstrength | 3.6e-05 | 27.3 | 30.1 |
| filtering/hilbert2 | 1.71e-05 | 32.1 | 32.5 |
| filter_design/firwin | 1.09e-05 | 4.68 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 67.5 | 68.2 |
| spectral/spectrogram | 7.17e-06 | 6.77 | 7.44 |
| filtering/detrend | 4.59e-06 | 0.745 | 1.83 |
| waveforms/chirp | 3.92e-06 | 63.6 | 67.1 |
| spectral/istft | 3.43e-06 | 3.72 | 12.3 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.000452 | 0.000451 | 0 |
| filtering/filtfilt | 0.000614 | 0.000615 | 1.97e-07 |
| filter_design/kaiser_atten | 0.00094 | 0 | 0 |
| filter_design/kaiser_beta | 0.000944 | 0 | 0 |
| radartools/cfar_alpha | 0.00232 | 0 | 0 |
| correlate/correlation_lags | 0.00622 | 0.028 | 0 |
| windows/boxcar | 0.013 | 0.0132 | 0 |
| spectral/periodogram | 0.0247 | 0.025 | 1.8e-07 |
| filtering/firfilter_zi | 0.0459 | 0.138 | 0 |
| windows/triang | 0.0846 | 0.0853 | 0 |
| windows/bartlett | 0.225 | 0.227 | 0 |
| windows/cosine | 0.273 | 0.273 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.825 | 0 |
| filter_design/kaiser_atten | 0 | 0.00094 | 0 |
| filter_design/kaiser_beta | 0 | 0.000944 | 0 |
| radartools/cfar_alpha | 0 | 0.00232 | 0 |
| filtering/lfilter | 0.000451 | 0.000452 | 0 |
| filtering/filtfilt | 0.000615 | 0.000614 | 1.97e-07 |
| windows/boxcar | 0.0132 | 0.013 | 0 |
| spectral/periodogram | 0.025 | 0.0247 | 1.8e-07 |
| correlate/correlation_lags | 0.028 | 0.00622 | 0 |
| windows/triang | 0.0853 | 0.0846 | 0 |
| filtering/firfilter_zi | 0.138 | 0.0459 | 0 |
| windows/bartlett | 0.227 | 0.225 | 0 |
