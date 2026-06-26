# All-Operator Benchmark Report

- run_id: `20260619_061059`
- scale_profile: `default`
- rows: `81`
- operators: `81`
- passed_rows: `81`
- status: passed=81
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.778 | 0.815 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.88 | 2.97 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.603 | 0.634 |
| correlate/correlate | 8192 | passed | 0 | 11 | 21.4 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.65 | 13.1 |
| correlate/correlation_lags | 8192 | passed | 0 | 0.00637 | 0.0286 |
| demod/fm_demod | 1048576 | passed | 0 | 28.3 | 36.4 |
| estimation/kalman_filter | 512 | passed | 0 | 1.18 | 2.39 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.814 | 0 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.8 | 21.5 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.697 | 0.91 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00308 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00288 | 0 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.87 | 4.43 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.73 | 1.85 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.000616 | 0.000617 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.57 | 3.1 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0549 | 0.166 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.91 | 14.8 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.67 | 8.46 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.5 | 24 |
| filtering/lfilter | 32768 | passed | 0 | 0.00045 | 0.000451 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.3 | 59.4 |
| filtering/resample | 32768 | passed | 3.85e-05 | 5.34 | 6.98 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 17.3 | 19.7 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.815 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.73 | 6.37 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 3.08 | 3.11 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.7 | 40.1 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 36.3 | 38.9 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 38.6 | 41.1 |
| radartools/ambgfun | 8192 | passed | 0 | 47.4 | 47.6 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.69 | 4.75 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00278 | 0 |
| radartools/mvdr | 1048576 | passed | 0 | 0.407 | 0.506 |
| radartools/pulse_compression | 1048576 | passed | 0 | 55.6 | 58.6 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.2 | 68.3 |
| spectral/coherence | 32768 | passed | 0.00326 | 1.47 | 407 |
| spectral/csd | 32768 | passed | 3.95e-07 | 1.84 | 1.96 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.64 | 12.1 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.8 | 68.3 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0248 | 0.025 |
| spectral/spectrogram | 32768 | passed | 7.17e-06 | 6.86 | 7.53 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.1 | 16.7 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 27.5 | 30.4 |
| spectral/welch | 32768 | passed | 3.63e-07 | 1.31 | 1.66 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 60.9 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 68.3 | 73.3 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.6 | 42.3 |
| waveforms/square | 1048576 | passed | 0 | 44.8 | 53.4 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 23.2 | 132 |
| wavelets/cwt | 32768 | passed | 0 | 214 | 222 |
| wavelets/morlet | 1048576 | passed | 0 | 1.61 | 1.62 |
| wavelets/morlet2 | 1048576 | passed | 0 | 3.13 | 3.16 |
| wavelets/qmf | 1048576 | passed | 0 | 18.7 | 26.4 |
| wavelets/ricker | 1048576 | passed | 0 | 0.454 | 0.455 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.33 |
| windows/bartlett | 1048576 | passed | 0 | 0.222 | 0.229 |
| windows/blackman | 1048576 | passed | 0 | 5.92 | 6.03 |
| windows/blackmanharris | 1048576 | passed | 0 | 8.73 | 8.96 |
| windows/bohman | 1048576 | passed | 0 | 2.42 | 2.47 |
| windows/boxcar | 1048576 | passed | 0 | 0.0131 | 0.0121 |
| windows/chebwin | 1536 | passed | 0 | 2.2 | 8.71 |
| windows/cosine | 1048576 | passed | 0 | 0.272 | 0.272 |
| windows/exponential | 1048576 | passed | 0 | 1.64 | 1.66 |
| windows/flattop | 1048576 | passed | 0 | 11.4 | 11.6 |
| windows/gaussian | 1048576 | passed | 0 | 2.29 | 2.34 |
| windows/general_cosine | 1048576 | passed | 0 | 9.5 | 9.72 |
| windows/general_gaussian | 1048576 | passed | 0 | 5.95 | 6.05 |
| windows/general_hamming | 1048576 | passed | 0 | 3.45 | 3.54 |
| windows/get_window | 1048576 | passed | 0 | 3.46 | 3.54 |
| windows/hamming | 1048576 | passed | 0 | 3.45 | 3.55 |
| windows/hann | 1048576 | passed | 0 | 3.49 | 3.53 |
| windows/kaiser | 1048576 | passed | 0 | 193 | 219 |
| windows/nuttall | 1048576 | passed | 0 | 8.8 | 9.01 |
| windows/parzen | 1048576 | passed | 0 | 0.415 | 0.425 |
| windows/taylor | 1048576 | passed | 0 | 3.16 | 3.19 |
| windows/triang | 1048576 | passed | 0 | 0.0838 | 0.0855 |
| windows/tukey | 1048576 | passed | 0 | 0.874 | 0.886 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00326 | 1.47 | 407 |
| filter_design/firwin2 | 7.58e-05 | 0.697 | 0.91 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.85e-05 | 5.34 | 6.98 |
| spectral/vectorstrength | 3.6e-05 | 27.5 | 30.4 |
| filtering/hilbert2 | 1.71e-05 | 23.5 | 24 |
| filter_design/firwin | 1.09e-05 | 4.8 | 21.5 |
| spectral/lombscargle | 8.72e-06 | 67.8 | 68.3 |
| spectral/spectrogram | 7.17e-06 | 6.86 | 7.53 |
| filtering/detrend | 4.59e-06 | 0.73 | 1.85 |
| waveforms/chirp | 3.92e-06 | 60.9 | 67 |
| spectral/istft | 3.43e-06 | 3.64 | 12.1 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.00045 | 0.000451 | 0 |
| filtering/filtfilt | 0.000616 | 0.000617 | 1.97e-07 |
| radartools/cfar_alpha | 0.00278 | 0 | 0 |
| filter_design/kaiser_beta | 0.00288 | 0 | 0 |
| filter_design/kaiser_atten | 0.00308 | 0 | 0 |
| correlate/correlation_lags | 0.00637 | 0.0286 | 0 |
| windows/boxcar | 0.0131 | 0.0121 | 0 |
| spectral/periodogram | 0.0248 | 0.025 | 1.8e-07 |
| filtering/firfilter_zi | 0.0549 | 0.166 | 0 |
| windows/triang | 0.0838 | 0.0855 | 0 |
| windows/bartlett | 0.222 | 0.229 | 0 |
| windows/cosine | 0.272 | 0.272 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.814 | 0 |
| filter_design/kaiser_atten | 0 | 0.00308 | 0 |
| filter_design/kaiser_beta | 0 | 0.00288 | 0 |
| radartools/cfar_alpha | 0 | 0.00278 | 0 |
| filtering/lfilter | 0.000451 | 0.00045 | 0 |
| filtering/filtfilt | 0.000617 | 0.000616 | 1.97e-07 |
| windows/boxcar | 0.0121 | 0.0131 | 0 |
| spectral/periodogram | 0.025 | 0.0248 | 1.8e-07 |
| correlate/correlation_lags | 0.0286 | 0.00637 | 0 |
| windows/triang | 0.0855 | 0.0838 | 0 |
| filtering/firfilter_zi | 0.166 | 0.0549 | 0 |
| windows/bartlett | 0.229 | 0.222 | 0 |
