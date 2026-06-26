# All-Operator Benchmark Report

- run_id: `20260625_153127`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.775 | 0.821 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.2 | 2.25 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.606 | 0.638 |
| correlate/correlate | 8192 | passed | 0 | 13.8 | 26.6 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.66 | 13.1 |
| demod/fm_demod | 1048576 | passed | 0 | 28.3 | 36.8 |
| estimation/kalman_filter | 512 | passed | 0 | 1.15 | 2.02 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.28 | 20.7 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.667 | 0.868 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4.09 | 4.65 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.709 | 1.83 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.2 | 12.8 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.57 | 3.07 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.83 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.71 | 8.55 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.1 | 23.5 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.9 | 59.6 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.66 | 5.9 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.4 | 18.3 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.8 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.77 | 6.26 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 217 | 228 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 36.3 | 38.5 |
| radartools/ambgfun | 8192 | passed | 0 | 47.5 | 47.7 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.3 | 5.54 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00263 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.5 | 57.9 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 29.7 | 68.1 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.81 | 1.95 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.89 | 12.1 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 172 | 176 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.69 | 7.43 |
| spectral/stft | 32768 | passed | 1.69e-07 | 12.9 | 16.3 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 27.9 | 30.1 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 61.3 | 66.1 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.8 | 73.3 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 35.5 | 43 |
| waveforms/square | 1048576 | passed | 0 | 43.1 | 53.1 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 22.8 | 129 |
| wavelets/cwt | 32768 | passed | 0 | 214 | 223 |
| wavelets/morlet | 1048576 | passed | 0 | 73.9 | 84.1 |
| wavelets/morlet2 | 1048576 | passed | 0 | 32.1 | 33.4 |
| wavelets/qmf | 1048576 | passed | 0 | 19 | 26.7 |
| wavelets/ricker | 1048576 | passed | 0 | 10.7 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 1.89 | 9.05 |
| windows/general_cosine | 1048576 | passed | 0 | 52.1 | 60.5 |
| windows/general_gaussian | 1048576 | passed | 0 | 162 | 237 |
| windows/hamming | 1048576 | passed | 0 | 33.4 | 46.4 |
| windows/kaiser | 1048576 | passed | 0 | 196 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.4 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 62.3 | 67.8 |
| windows/triang | 1048576 | passed | 0 | 14.1 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.667 | 0.868 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 4.66 | 5.9 |
| spectral/vectorstrength | 3.6e-05 | 27.9 | 30.1 |
| filtering/hilbert2 | 1.71e-05 | 23.1 | 23.5 |
| filter_design/firwin | 1.09e-05 | 4.28 | 20.7 |
| spectral/lombscargle | 9.62e-06 | 172 | 176 |
| spectral/spectrogram | 7.01e-06 | 6.69 | 7.43 |
| filtering/detrend | 4.59e-06 | 0.709 | 1.83 |
| waveforms/chirp | 3.92e-06 | 61.3 | 66.1 |
| spectral/istft | 3.43e-06 | 3.89 | 12.1 |
| filtering/hilbert | 1.97e-06 | 6.71 | 8.55 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00263 | 0 | 0 |
| bsplines/quadratic | 0.606 | 0.638 | 0 |
| filter_design/firwin2 | 0.667 | 0.868 | 7.58e-05 |
| filtering/detrend | 0.709 | 1.83 | 4.59e-06 |
| bsplines/cubic | 0.775 | 0.821 | 0 |
| filtering/sosfilt | 0.8 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.15 | 2.02 | 0 |
| spectral/csd | 1.81 | 1.95 | 2.22e-07 |
| windows/chebwin | 1.89 | 9.05 | 0 |
| bsplines/gauss_spline | 2.2 | 2.25 | 0 |
| filtering/firfilter2 | 2.57 | 3.07 | 8.15e-07 |
| correlate/correlate2d | 2.66 | 13.1 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00263 | 0 |
| bsplines/quadratic | 0.638 | 0.606 | 0 |
| bsplines/cubic | 0.821 | 0.775 | 0 |
| filter_design/firwin2 | 0.868 | 0.667 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.8 | 8.25e-07 |
| filtering/detrend | 1.83 | 0.709 | 4.59e-06 |
| spectral/csd | 1.95 | 1.81 | 2.22e-07 |
| estimation/kalman_filter | 2.02 | 1.15 | 0 |
| bsplines/gauss_spline | 2.25 | 2.2 | 0 |
| filtering/firfilter2 | 3.07 | 2.57 | 8.15e-07 |
| filtering/decimate | 4.65 | 4.09 | 6.95e-07 |
| radartools/ca_cfar | 5.54 | 4.3 | 0 |
