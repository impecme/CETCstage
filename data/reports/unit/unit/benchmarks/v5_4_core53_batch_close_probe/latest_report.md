# All-Operator Benchmark Report

- run_id: `20260626_031756`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 7.57 | 10.9 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 41.9 | 57.7 |
| bsplines/quadratic | 1048576 | passed | 0 | 6.04 | 8.45 |
| correlate/correlate | 8192 | passed | 0 | 13.5 | 26 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.6 | 13.3 |
| demod/fm_demod | 1048576 | passed | 0 | 28.6 | 36.6 |
| estimation/kalman_filter | 512 | passed | 0 | 1.21 | 2.55 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.57 | 20.7 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 2.1 | 12.7 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 9.93 | 11.5 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4 | 4.39 |
| filtering/detrend | 32768 | passed | 1.66e-05 | 0.731 | 1.96 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 14 | 14.8 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.66 | 3.16 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.84 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.63 | 7.88 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.2 | 23.7 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.7 | 59.7 |
| filtering/resample | 32768 | passed | 3.86e-05 | 5.5 | 5.88 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.5 | 18.6 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.852 | 1.39 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.61 | 6.31 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 178 | 186 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.7 | 40.1 |
| radartools/ambgfun | 8192 | passed | 0 | 50.7 | 50.9 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.25 | 4.8 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00262 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.1 | 58.1 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 29.9 | 68.1 |
| spectral/csd | 32768 | passed | 8.11e-08 | 6.31 | 6.85 |
| spectral/istft | 257 | passed | 3.43e-06 | 4.05 | 12.4 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 171 | 175 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.91 | 7.58 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.1 | 16.8 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 65.2 | 67.1 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.2 | 73.4 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37.1 | 43.2 |
| waveforms/square | 1048576 | passed | 0 | 43.9 | 53.9 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 23.6 | 135 |
| wavelets/cwt | 32768 | passed | 0 | 215 | 223 |
| wavelets/morlet | 1048576 | passed | 0 | 72.7 | 83.4 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.5 | 32.9 |
| wavelets/qmf | 1048576 | passed | 0 | 20 | 27.4 |
| wavelets/ricker | 1048576 | passed | 0 | 10.7 | 11.3 |
| windows/chebwin | 1536 | passed | 0 | 2.51 | 8.88 |
| windows/general_cosine | 1048576 | passed | 0 | 52 | 60.6 |
| windows/general_gaussian | 1048576 | passed | 0 | 178 | 236 |
| windows/hamming | 1048576 | passed | 0 | 32.7 | 46.1 |
| windows/kaiser | 1048576 | passed | 0 | 203 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.3 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 62 | 67.9 |
| windows/triang | 1048576 | passed | 0 | 14.1 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 2.1 | 12.7 |
| filtering/channelize_poly | 5.7e-05 | 9.93 | 11.5 |
| filtering/resample | 3.86e-05 | 5.5 | 5.88 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 23.2 | 23.7 |
| filtering/detrend | 1.66e-05 | 0.731 | 1.96 |
| filter_design/firwin | 1.09e-05 | 4.57 | 20.7 |
| spectral/lombscargle | 9.62e-06 | 171 | 175 |
| spectral/spectrogram | 7.01e-06 | 6.91 | 7.58 |
| waveforms/chirp | 3.92e-06 | 65.2 | 67.1 |
| spectral/istft | 3.43e-06 | 4.05 | 12.4 |
| filtering/hilbert | 1.97e-06 | 6.63 | 7.88 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00262 | 0 | 0 |
| filtering/detrend | 0.731 | 1.96 | 1.66e-05 |
| filtering/sosfilt | 0.852 | 1.39 | 8.25e-07 |
| estimation/kalman_filter | 1.21 | 2.55 | 0 |
| filter_design/firwin2 | 2.1 | 12.7 | 7.58e-05 |
| windows/chebwin | 2.51 | 8.88 | 0 |
| correlate/correlate2d | 2.6 | 13.3 | 0 |
| filtering/firfilter2 | 2.66 | 3.16 | 8.15e-07 |
| filtering/decimate | 4 | 4.39 | 6.95e-07 |
| spectral/istft | 4.05 | 12.4 | 3.43e-06 |
| radartools/ca_cfar | 4.25 | 4.8 | 0 |
| filter_design/firwin | 4.57 | 20.7 | 1.09e-05 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00262 | 0 |
| filtering/sosfilt | 1.39 | 0.852 | 8.25e-07 |
| filtering/detrend | 1.96 | 0.731 | 1.66e-05 |
| estimation/kalman_filter | 2.55 | 1.21 | 0 |
| filtering/firfilter2 | 3.16 | 2.66 | 8.15e-07 |
| filtering/decimate | 4.39 | 4 | 6.95e-07 |
| radartools/ca_cfar | 4.8 | 4.25 | 0 |
| filtering/resample | 5.88 | 5.5 | 3.86e-05 |
| filtering/upfirdn | 6.31 | 4.61 | 2.87e-07 |
| spectral/csd | 6.85 | 6.31 | 8.11e-08 |
| spectral/spectrogram | 7.58 | 6.91 | 7.01e-06 |
| filtering/hilbert | 7.88 | 6.63 | 1.97e-06 |
