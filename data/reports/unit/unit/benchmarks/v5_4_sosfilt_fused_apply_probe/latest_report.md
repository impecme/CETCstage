# All-Operator Benchmark Report

- run_id: `20260626_003852`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 7.82 | 10.8 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 38.9 | 57.1 |
| bsplines/quadratic | 1048576 | passed | 0 | 5.74 | 8.09 |
| correlate/correlate | 8192 | passed | 0 | 12.9 | 25.5 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.42 | 12.9 |
| demod/fm_demod | 1048576 | passed | 0 | 26 | 35.4 |
| estimation/kalman_filter | 512 | passed | 0 | 1.14 | 2.3 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.58 | 20.5 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.667 | 0.881 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.9 | 4.43 |
| filtering/detrend | 32768 | passed | 1.66e-05 | 0.725 | 1.92 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 14.7 | 15.4 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.86 | 3.49 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.68 | 14.5 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.94 | 8.41 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 42.9 | 43.7 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.9 | 59.1 |
| filtering/resample | 32768 | passed | 3.86e-05 | 5.93 | 7.31 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 17.1 | 19.6 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.839 | 1.4 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 5.05 | 6.64 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 200 | 209 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.2 | 40.9 |
| radartools/ambgfun | 8192 | passed | 0 | 49.9 | 50.1 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.48 | 4.52 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00252 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 51.6 | 54.6 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 22.7 | 45.2 |
| spectral/csd | 32768 | passed | 8.11e-08 | 6.33 | 7.73 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.98 | 12.2 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 170 | 174 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.75 | 7.4 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.6 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.1 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 64.6 | 66.9 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.8 | 73.4 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37.4 | 43.3 |
| waveforms/square | 1048576 | passed | 0 | 44.5 | 53.7 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 20 | 113 |
| wavelets/cwt | 32768 | passed | 0 | 214 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 72.3 | 83 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.1 | 33.5 |
| wavelets/qmf | 1048576 | passed | 0 | 17.9 | 25.2 |
| wavelets/ricker | 1048576 | passed | 0 | 10.6 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 2.44 | 8.85 |
| windows/general_cosine | 1048576 | passed | 0 | 52.5 | 60.5 |
| windows/general_gaussian | 1048576 | passed | 0 | 142 | 236 |
| windows/hamming | 1048576 | passed | 0 | 34 | 46.3 |
| windows/kaiser | 1048576 | passed | 0 | 195 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.6 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 61.7 | 67.9 |
| windows/triang | 1048576 | passed | 0 | 14.7 | 21.6 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.667 | 0.881 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 5.93 | 7.31 |
| spectral/vectorstrength | 3.6e-05 | 28.1 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 42.9 | 43.7 |
| filtering/detrend | 1.66e-05 | 0.725 | 1.92 |
| filter_design/firwin | 1.09e-05 | 4.58 | 20.5 |
| spectral/lombscargle | 9.62e-06 | 170 | 174 |
| spectral/spectrogram | 7.01e-06 | 6.75 | 7.4 |
| waveforms/chirp | 3.92e-06 | 64.6 | 66.9 |
| spectral/istft | 3.43e-06 | 3.98 | 12.2 |
| filtering/hilbert | 1.97e-06 | 6.94 | 8.41 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00252 | 0 | 0 |
| filter_design/firwin2 | 0.667 | 0.881 | 7.58e-05 |
| filtering/detrend | 0.725 | 1.92 | 1.66e-05 |
| filtering/sosfilt | 0.839 | 1.4 | 8.25e-07 |
| estimation/kalman_filter | 1.14 | 2.3 | 0 |
| correlate/correlate2d | 2.42 | 12.9 | 0 |
| windows/chebwin | 2.44 | 8.85 | 0 |
| filtering/firfilter2 | 2.86 | 3.49 | 8.15e-07 |
| filtering/decimate | 3.9 | 4.43 | 6.95e-07 |
| spectral/istft | 3.98 | 12.2 | 3.43e-06 |
| radartools/ca_cfar | 4.48 | 4.52 | 0 |
| filter_design/firwin | 4.58 | 20.5 | 1.09e-05 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00252 | 0 |
| filter_design/firwin2 | 0.881 | 0.667 | 7.58e-05 |
| filtering/sosfilt | 1.4 | 0.839 | 8.25e-07 |
| filtering/detrend | 1.92 | 0.725 | 1.66e-05 |
| estimation/kalman_filter | 2.3 | 1.14 | 0 |
| filtering/firfilter2 | 3.49 | 2.86 | 8.15e-07 |
| filtering/decimate | 4.43 | 3.9 | 6.95e-07 |
| radartools/ca_cfar | 4.52 | 4.48 | 0 |
| filtering/upfirdn | 6.64 | 5.05 | 2.87e-07 |
| filtering/resample | 7.31 | 5.93 | 3.86e-05 |
| spectral/spectrogram | 7.4 | 6.75 | 7.01e-06 |
| spectral/csd | 7.73 | 6.33 | 8.11e-08 |
