# All-Operator Benchmark Report

- run_id: `20260618_090114`
- scale_profile: `default`
- rows: `486`
- operators: `81`
- passed_rows: `486`
- status: passed=486
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.773 | 0.797 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.9 | 2.97 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.601 | 0.628 |
| correlate/correlate | 8192 | passed | 0 | 12.6 | 23.3 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.87 | 13.4 |
| correlate/correlation_lags | 8192 | passed | 0 | 0.00627 | 0.0287 |
| demod/fm_demod | 1048576 | passed | 0 | 28.9 | 36.8 |
| estimation/kalman_filter | 512 | passed | 0 | 1.38 | 3.31 |
| filter_design/cmplx_sort | 4097 | passed | 0 | 0.832 | 0 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.87 | 21.2 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.686 | 0.905 |
| filter_design/kaiser_atten | 4097 | passed | 0 | 0.00106 | 0 |
| filter_design/kaiser_beta | 4097 | passed | 0 | 0.00102 | 0 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.2 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4.24 | 4.78 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.764 | 1.87 |
| filtering/filtfilt | 32768 | passed | 1.97e-07 | 0.000612 | 0.000613 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.1 | 12.5 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.63 | 3.1 |
| filtering/firfilter_zi | 32768 | passed | 0 | 0.0491 | 0.146 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 8.49 | 14.8 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.65 | 8.36 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 33.3 | 34 |
| filtering/lfilter | 32768 | passed | 0 | 0.000451 | 0.000451 |
| filtering/lfilter_zi | 512 | passed | 0 | 33.8 | 60.5 |
| filtering/resample | 32768 | passed | 3.85e-05 | 5.82 | 6.68 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 17 | 19.1 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.883 | 1.33 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 3.86 | 6.3 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 3.59 | 3.58 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 39.5 | 42.1 |
| peak_finding/argrelmax | 1048576 | passed | 0 | 39.6 | 42.1 |
| peak_finding/argrelmin | 1048576 | passed | 0 | 38.2 | 41 |
| radartools/ambgfun | 8192 | passed | 0 | 46.7 | 46.9 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.05 | 4.53 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00256 | 0 |
| radartools/mvdr | 1048576 | passed | 0 | 0.405 | 0.504 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.9 | 59.4 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 32.4 | 68.7 |
| spectral/coherence | 32768 | passed | 0.00326 | 1.49 | 420 |
| spectral/csd | 32768 | passed | 3.95e-07 | 1.83 | 1.96 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.9 | 12.5 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.8 | 68.3 |
| spectral/periodogram | 32768 | passed | 1.8e-07 | 0.0251 | 0.0254 |
| spectral/spectrogram | 32768 | passed | 7.17e-06 | 6.84 | 7.5 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.4 | 16.7 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.3 |
| spectral/welch | 32768 | passed | 3.63e-07 | 1.32 | 1.66 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.7 | 66.7 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 68.8 | 73.3 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.9 | 42.5 |
| waveforms/square | 1048576 | passed | 0 | 48 | 56.3 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 22.8 | 107 |
| wavelets/cwt | 32768 | passed | 0 | 217 | 223 |
| wavelets/morlet | 1048576 | passed | 0 | 1.59 | 1.6 |
| wavelets/morlet2 | 1048576 | passed | 0 | 3.12 | 3.14 |
| wavelets/qmf | 1048576 | passed | 0 | 18.2 | 25.1 |
| wavelets/ricker | 1048576 | passed | 0 | 0.445 | 0.446 |
| windows/barthann | 1048576 | passed | 0 | 1.31 | 1.32 |
| windows/bartlett | 1048576 | passed | 0 | 0.223 | 0.227 |
| windows/blackman | 1048576 | passed | 0 | 5.93 | 6.05 |
| windows/blackmanharris | 1048576 | passed | 0 | 8.75 | 8.95 |
| windows/bohman | 1048576 | passed | 0 | 2.42 | 2.45 |
| windows/boxcar | 1048576 | passed | 0 | 0.0131 | 0.0133 |
| windows/chebwin | 1536 | passed | 0 | 2.46 | 8.95 |
| windows/cosine | 1048576 | passed | 0 | 0.273 | 0.273 |
| windows/exponential | 1048576 | passed | 0 | 1.66 | 1.68 |
| windows/flattop | 1048576 | passed | 0 | 11.4 | 11.7 |
| windows/gaussian | 1048576 | passed | 0 | 2.3 | 2.34 |
| windows/general_cosine | 1048576 | passed | 0 | 9.42 | 9.67 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.05 | 6.13 |
| windows/general_hamming | 1048576 | passed | 0 | 3.47 | 3.54 |
| windows/get_window | 1048576 | passed | 0 | 3.47 | 3.54 |
| windows/hamming | 1048576 | passed | 0 | 3.47 | 3.54 |
| windows/hann | 1048576 | passed | 0 | 3.47 | 3.54 |
| windows/kaiser | 1048576 | passed | 0 | 197 | 219 |
| windows/nuttall | 1048576 | passed | 0 | 8.72 | 8.94 |
| windows/parzen | 1048576 | passed | 0 | 0.419 | 0.425 |
| windows/taylor | 1048576 | passed | 0 | 3.17 | 3.2 |
| windows/triang | 1048576 | passed | 0 | 0.0844 | 0.085 |
| windows/tukey | 1048576 | passed | 0 | 0.875 | 0.886 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| spectral/coherence | 0.00326 | 1.49 | 420 |
| filter_design/firwin2 | 7.58e-05 | 0.686 | 0.905 |
| filtering/channelize_poly | 5.7e-05 | 10.2 | 11.7 |
| filtering/resample | 3.85e-05 | 5.82 | 6.68 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.3 |
| filtering/hilbert2 | 1.71e-05 | 33.3 | 34 |
| filter_design/firwin | 1.09e-05 | 4.87 | 21.2 |
| spectral/lombscargle | 8.72e-06 | 67.8 | 68.3 |
| spectral/spectrogram | 7.17e-06 | 6.84 | 7.5 |
| filtering/detrend | 4.59e-06 | 0.764 | 1.87 |
| waveforms/chirp | 3.92e-06 | 63.7 | 66.7 |
| spectral/istft | 3.43e-06 | 3.9 | 12.5 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| filtering/lfilter | 0.000451 | 0.000451 | 0 |
| filtering/filtfilt | 0.000612 | 0.000613 | 1.97e-07 |
| filter_design/kaiser_beta | 0.00102 | 0 | 0 |
| filter_design/kaiser_atten | 0.00106 | 0 | 0 |
| radartools/cfar_alpha | 0.00256 | 0 | 0 |
| correlate/correlation_lags | 0.00627 | 0.0287 | 0 |
| windows/boxcar | 0.0131 | 0.0133 | 0 |
| spectral/periodogram | 0.0251 | 0.0254 | 1.8e-07 |
| filtering/firfilter_zi | 0.0491 | 0.146 | 0 |
| windows/triang | 0.0844 | 0.085 | 0 |
| windows/bartlett | 0.223 | 0.227 | 0 |
| windows/cosine | 0.273 | 0.273 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| filter_design/cmplx_sort | 0 | 0.832 | 0 |
| filter_design/kaiser_atten | 0 | 0.00106 | 0 |
| filter_design/kaiser_beta | 0 | 0.00102 | 0 |
| radartools/cfar_alpha | 0 | 0.00256 | 0 |
| filtering/lfilter | 0.000451 | 0.000451 | 0 |
| filtering/filtfilt | 0.000613 | 0.000612 | 1.97e-07 |
| windows/boxcar | 0.0133 | 0.0131 | 0 |
| spectral/periodogram | 0.0254 | 0.0251 | 1.8e-07 |
| correlate/correlation_lags | 0.0287 | 0.00627 | 0 |
| windows/triang | 0.085 | 0.0844 | 0 |
| filtering/firfilter_zi | 0.146 | 0.0491 | 0 |
| windows/bartlett | 0.227 | 0.223 | 0 |
