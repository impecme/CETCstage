# All-Operator Benchmark Report

- run_id: `20260626_085928`
- scale_profile: `default`
- rows: `81`
- operators: `81`
- passed_rows: `81`
- status: passed=81
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 7.88 | 11 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 41 | 57.4 |
| bsplines/quadratic | 1048576 | passed | 0 | 5.97 | 8.26 |
| correlate/correlate | 8192 | passed | 0 | 13.6 | 26.8 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.71 | 13 |
| correlate/correlation_lags | 8192 | passed | 0 | 0.00626 | 0.0284 |
| demod/fm_demod | 1048576 | passed | 0 | 28.4 | 36.5 |
| estimation/kalman_filter | 512 | passed | 0 | 1.32 | 3.32 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.81 | 0 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.54 | 20.5 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 2.27 | 12.6 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.0054 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00299 | 0 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4 | 4.56 |
| filtering/detrend | 32768 | passed | 1.66e-05 | 0.781 | 1.92 |
| filtering/filtfilt | 32768 | passed | 7.49e-07 | 0.858 | 1.4 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.57 | 3.08 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0539 | 0.16 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.93 | 14.5 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 7.47 | 9.38 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 32.4 | 33 |
| filtering/lfilter | 32768 | passed | 1.39e-06 | 0.568 | 1.7 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.6 | 59.1 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.84 | 5.85 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.5 | 19 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.865 | 1.39 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.62 | 6.25 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 194 | 202 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38 | 39.7 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 37.9 | 40.5 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 38.7 | 41 |
| radartools/ambgfun | 8192 | passed | 0 | 50.6 | 50.8 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.05 | 4.59 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.0024 | 0 |
| radartools/mvdr | 1048576 | passed | 0 | 1.91 | 25.3 |
| radartools/pulse_compression | 1048576 | passed | 0 | 51.3 | 53.7 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 30.9 | 67.9 |
| spectral/coherence | 32768 | passed | 0.00294 | 14.9 | 30.5 |
| spectral/csd | 32768 | passed | 8.11e-08 | 6.41 | 7.84 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.98 | 11.6 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 172 | 175 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 2.13 | 7.48 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.76 | 7.47 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.4 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.3 | 30.4 |
| spectral/welch | 32768 | passed | 3.16e-07 | 1.35 | 1.66 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.4 | 73.5 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 35.9 | 41.8 |
| waveforms/square | 1048576 | passed | 0 | 43.2 | 52.8 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 21.2 | 120 |
| wavelets/cwt | 32768 | passed | 0 | 215 | 223 |
| wavelets/morlet | 1048576 | passed | 0 | 70.9 | 83 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.8 | 33.5 |
| wavelets/qmf | 1048576 | passed | 0 | 18.8 | 25.8 |
| wavelets/ricker | 1048576 | passed | 0 | 12.1 | 12.5 |
| windows/barthann | 1048576 | passed | 0 | 30.3 | 43.8 |
| windows/bartlett | 1048576 | passed | 0 | 8.92 | 13.9 |
| windows/blackman | 1048576 | passed | 0 | 38.6 | 48.5 |
| windows/blackmanharris | 1048576 | passed | 0 | 41.7 | 48.6 |
| windows/bohman | 1048576 | passed | 0 | 39.9 | 45.8 |
| windows/boxcar | 1048576 | passed | 0 | 0.586 | 1.21 |
| windows/chebwin | 1536 | passed | 0 | 2.15 | 8.68 |
| windows/cosine | 1048576 | passed | 0 | 50.2 | 77.2 |
| windows/exponential | 1048576 | passed | 0 | 55.7 | 81.6 |
| windows/flattop | 1048576 | passed | 0 | 43.6 | 47.8 |
| windows/gaussian | 1048576 | passed | 0 | 79.6 | 112 |
| windows/general_cosine | 1048576 | passed | 0 | 51.9 | 60.4 |
| windows/general_gaussian | 1048576 | passed | 0 | 179 | 236 |
| windows/general_hamming | 1048576 | passed | 0 | 33.1 | 46.1 |
| windows/get_window | 1048576 | passed | 0 | 33.2 | 46.8 |
| windows/hamming | 1048576 | passed | 0 | 34 | 46.3 |
| windows/hann | 1048576 | passed | 0 | 33 | 46.1 |
| windows/kaiser | 1048576 | passed | 0 | 196 | 219 |
| windows/nuttall | 1048576 | passed | 0 | 42 | 48.8 |
| windows/parzen | 1048576 | passed | 0 | 14.4 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 61.9 | 68 |
| windows/triang | 1048576 | passed | 0 | 14.3 | 21.6 |
| windows/tukey | 1048576 | passed | 0 | 20.9 | 29.1 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00294 | 14.9 | 30.5 |
| filter_design/firwin2 | 7.58e-05 | 2.27 | 12.6 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 4.84 | 5.85 |
| spectral/vectorstrength | 3.6e-05 | 28.3 | 30.4 |
| filtering/hilbert2 | 1.71e-05 | 32.4 | 33 |
| filtering/detrend | 1.66e-05 | 0.781 | 1.92 |
| filter_design/firwin | 1.09e-05 | 4.54 | 20.5 |
| spectral/lombscargle | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 7.01e-06 | 6.76 | 7.47 |
| waveforms/chirp | 3.92e-06 | 63 | 67 |
| spectral/istft | 3.43e-06 | 3.98 | 11.6 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.0024 | 0 | 0 |
| filter_design/kaiser_beta | 0.00299 | 0 | 0 |
| filter_design/kaiser_atten | 0.0054 | 0 | 0 |
| correlate/correlation_lags | 0.00626 | 0.0284 | 0 |
| filtering/firfilter_zi | 0.0539 | 0.16 | 0 |
| filtering/lfilter | 0.568 | 1.7 | 1.39e-06 |
| windows/boxcar | 0.586 | 1.21 | 0 |
| filtering/detrend | 0.781 | 1.92 | 1.66e-05 |
| filter_design/cmplx_sort | 0.81 | 0 | 0 |
| filtering/filtfilt | 0.858 | 1.4 | 7.49e-07 |
| filtering/sosfilt | 0.865 | 1.39 | 8.25e-07 |
| estimation/kalman_filter | 1.32 | 3.32 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.81 | 0 |
| filter_design/kaiser_atten | 0 | 0.0054 | 0 |
| filter_design/kaiser_beta | 0 | 0.00299 | 0 |
| radartools/cfar_alpha | 0 | 0.0024 | 0 |
| correlate/correlation_lags | 0.0284 | 0.00626 | 0 |
| filtering/firfilter_zi | 0.16 | 0.0539 | 0 |
| windows/boxcar | 1.21 | 0.586 | 0 |
| filtering/sosfilt | 1.39 | 0.865 | 8.25e-07 |
| filtering/filtfilt | 1.4 | 0.858 | 7.49e-07 |
| spectral/welch | 1.66 | 1.35 | 3.16e-07 |
| filtering/lfilter | 1.7 | 0.568 | 1.39e-06 |
| filtering/detrend | 1.92 | 0.781 | 1.66e-05 |
