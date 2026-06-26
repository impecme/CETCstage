# All-Operator Benchmark Report

- run_id: `20260625_163634`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 7.6 | 10.8 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 41.2 | 57.6 |
| bsplines/quadratic | 1048576 | passed | 0 | 4.75 | 8.2 |
| correlate/correlate | 8192 | passed | 0 | 13.2 | 25.4 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.54 | 12.9 |
| demod/fm_demod | 1048576 | passed | 0 | 29 | 37.8 |
| estimation/kalman_filter | 512 | passed | 0 | 1.17 | 2.2 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.53 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.655 | 0.861 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.85 | 4.32 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.726 | 1.85 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 11.8 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.59 | 3.09 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.47 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.34 | 7.74 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23 | 23.5 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.5 | 59.6 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.63 | 5.74 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 13.7 | 17 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.819 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.76 | 6.34 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 223 | 239 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.5 | 39.5 |
| radartools/ambgfun | 8192 | passed | 0 | 50.8 | 51 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.37 | 4.92 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00275 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.3 | 57.6 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 30.7 | 67 |
| spectral/csd | 32768 | passed | 8.11e-08 | 6.17 | 7.76 |
| spectral/istft | 257 | passed | 3.43e-06 | 4.03 | 12.3 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.71 | 7.4 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.5 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.3 | 30.3 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 62.5 | 67.2 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.7 | 73.4 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 34.8 | 42.9 |
| waveforms/square | 1048576 | passed | 0 | 44.6 | 54.1 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 19.7 | 122 |
| wavelets/cwt | 32768 | passed | 0 | 216 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 72.8 | 83.4 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.8 | 33.2 |
| wavelets/qmf | 1048576 | passed | 0 | 19.6 | 26.8 |
| wavelets/ricker | 1048576 | passed | 0 | 10.8 | 11.3 |
| windows/chebwin | 1536 | passed | 0 | 2.35 | 8.79 |
| windows/general_cosine | 1048576 | passed | 0 | 51.7 | 60.6 |
| windows/general_gaussian | 1048576 | passed | 0 | 174 | 236 |
| windows/hamming | 1048576 | passed | 0 | 33.6 | 46.4 |
| windows/kaiser | 1048576 | passed | 0 | 196 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 60.7 | 67.9 |
| windows/triang | 1048576 | passed | 0 | 14.1 | 21.8 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.655 | 0.861 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 4.63 | 5.74 |
| spectral/vectorstrength | 3.6e-05 | 28.3 | 30.3 |
| filtering/hilbert2 | 1.71e-05 | 23 | 23.5 |
| filter_design/firwin | 1.09e-05 | 4.53 | 20.6 |
| spectral/lombscargle | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 7.01e-06 | 6.71 | 7.4 |
| filtering/detrend | 4.59e-06 | 0.726 | 1.85 |
| waveforms/chirp | 3.92e-06 | 62.5 | 67.2 |
| spectral/istft | 3.43e-06 | 4.03 | 12.3 |
| filtering/hilbert | 1.97e-06 | 6.34 | 7.74 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00275 | 0 | 0 |
| filter_design/firwin2 | 0.655 | 0.861 | 7.58e-05 |
| filtering/detrend | 0.726 | 1.85 | 4.59e-06 |
| filtering/sosfilt | 0.819 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.17 | 2.2 | 0 |
| windows/chebwin | 2.35 | 8.79 | 0 |
| correlate/correlate2d | 2.54 | 12.9 | 0 |
| filtering/firfilter2 | 2.59 | 3.09 | 8.15e-07 |
| filtering/decimate | 3.85 | 4.32 | 6.95e-07 |
| spectral/istft | 4.03 | 12.3 | 3.43e-06 |
| radartools/ca_cfar | 4.37 | 4.92 | 0 |
| filter_design/firwin | 4.53 | 20.6 | 1.09e-05 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00275 | 0 |
| filter_design/firwin2 | 0.861 | 0.655 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.819 | 8.25e-07 |
| filtering/detrend | 1.85 | 0.726 | 4.59e-06 |
| estimation/kalman_filter | 2.2 | 1.17 | 0 |
| filtering/firfilter2 | 3.09 | 2.59 | 8.15e-07 |
| filtering/decimate | 4.32 | 3.85 | 6.95e-07 |
| radartools/ca_cfar | 4.92 | 4.37 | 0 |
| filtering/resample | 5.74 | 4.63 | 3.86e-05 |
| filtering/upfirdn | 6.34 | 4.76 | 2.87e-07 |
| spectral/spectrogram | 7.4 | 6.71 | 7.01e-06 |
| filtering/hilbert | 7.74 | 6.34 | 1.97e-06 |
