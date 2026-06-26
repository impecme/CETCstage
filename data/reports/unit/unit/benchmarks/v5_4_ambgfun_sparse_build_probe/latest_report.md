# All-Operator Benchmark Report

- run_id: `20260625_161612`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.771 | 0.819 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.2 | 2.27 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.602 | 0.629 |
| correlate/correlate | 8192 | passed | 0 | 13.5 | 26.1 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.52 | 12.7 |
| demod/fm_demod | 1048576 | passed | 0 | 28.5 | 36.8 |
| estimation/kalman_filter | 512 | passed | 0 | 1.14 | 2.32 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 5.29 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.641 | 0.863 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.4 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4 | 4.52 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.723 | 1.85 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.3 | 12.8 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.57 | 3.07 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 10.1 | 18.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.55 | 8.29 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.4 | 23.7 |
| filtering/lfilter_zi | 512 | passed | 0 | 33.3 | 59.7 |
| filtering/resample | 32768 | passed | 3.86e-05 | 5.21 | 5.63 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.7 | 18.6 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.812 | 1.31 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 3.73 | 6.26 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 215 | 229 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.9 | 40.2 |
| radartools/ambgfun | 8192 | passed | 0 | 49.8 | 49.9 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.32 | 4.89 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00257 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 51.5 | 54.2 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.3 | 67.3 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.81 | 1.94 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.87 | 12.1 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.73 | 7.45 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.3 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.3 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 62.4 | 66.9 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.1 | 73.7 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.7 | 43 |
| waveforms/square | 1048576 | passed | 0 | 44.2 | 54 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 22.7 | 131 |
| wavelets/cwt | 32768 | passed | 0 | 215 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 73.3 | 83.3 |
| wavelets/morlet2 | 1048576 | passed | 0 | 32 | 33.5 |
| wavelets/qmf | 1048576 | passed | 0 | 18.9 | 26.9 |
| wavelets/ricker | 1048576 | passed | 0 | 10.6 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 2.62 | 8.94 |
| windows/general_cosine | 1048576 | passed | 0 | 52.2 | 60.5 |
| windows/general_gaussian | 1048576 | passed | 0 | 168 | 235 |
| windows/hamming | 1048576 | passed | 0 | 32.3 | 46.1 |
| windows/kaiser | 1048576 | passed | 0 | 195 | 220 |
| windows/parzen | 1048576 | passed | 0 | 14 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 61.4 | 67.9 |
| windows/triang | 1048576 | passed | 0 | 14.4 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.641 | 0.863 |
| filtering/channelize_poly | 5.7e-05 | 10.4 | 11.7 |
| filtering/resample | 3.86e-05 | 5.21 | 5.63 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.3 |
| filtering/hilbert2 | 1.71e-05 | 23.4 | 23.7 |
| filter_design/firwin | 1.09e-05 | 5.29 | 20.6 |
| spectral/lombscargle | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 7.01e-06 | 6.73 | 7.45 |
| filtering/detrend | 4.59e-06 | 0.723 | 1.85 |
| waveforms/chirp | 3.92e-06 | 62.4 | 66.9 |
| spectral/istft | 3.43e-06 | 3.87 | 12.1 |
| filtering/hilbert | 1.97e-06 | 6.55 | 8.29 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00257 | 0 | 0 |
| bsplines/quadratic | 0.602 | 0.629 | 0 |
| filter_design/firwin2 | 0.641 | 0.863 | 7.58e-05 |
| filtering/detrend | 0.723 | 1.85 | 4.59e-06 |
| bsplines/cubic | 0.771 | 0.819 | 0 |
| filtering/sosfilt | 0.812 | 1.31 | 8.25e-07 |
| estimation/kalman_filter | 1.14 | 2.32 | 0 |
| spectral/csd | 1.81 | 1.94 | 2.22e-07 |
| bsplines/gauss_spline | 2.2 | 2.27 | 0 |
| correlate/correlate2d | 2.52 | 12.7 | 0 |
| filtering/firfilter2 | 2.57 | 3.07 | 8.15e-07 |
| windows/chebwin | 2.62 | 8.94 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00257 | 0 |
| bsplines/quadratic | 0.629 | 0.602 | 0 |
| bsplines/cubic | 0.819 | 0.771 | 0 |
| filter_design/firwin2 | 0.863 | 0.641 | 7.58e-05 |
| filtering/sosfilt | 1.31 | 0.812 | 8.25e-07 |
| filtering/detrend | 1.85 | 0.723 | 4.59e-06 |
| spectral/csd | 1.94 | 1.81 | 2.22e-07 |
| bsplines/gauss_spline | 2.27 | 2.2 | 0 |
| estimation/kalman_filter | 2.32 | 1.14 | 0 |
| filtering/firfilter2 | 3.07 | 2.57 | 8.15e-07 |
| filtering/decimate | 4.52 | 4 | 6.95e-07 |
| radartools/ca_cfar | 4.89 | 4.32 | 0 |
