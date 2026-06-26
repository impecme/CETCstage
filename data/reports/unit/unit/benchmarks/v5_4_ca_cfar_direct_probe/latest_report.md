# All-Operator Benchmark Report

- run_id: `20260626_031117`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 7.7 | 10.9 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 41 | 57.5 |
| bsplines/quadratic | 1048576 | passed | 0 | 5.9 | 8.39 |
| correlate/correlate | 8192 | passed | 0 | 13 | 25.5 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.56 | 12.8 |
| demod/fm_demod | 1048576 | passed | 0 | 28.2 | 36.3 |
| estimation/kalman_filter | 512 | passed | 0 | 1.26 | 2.54 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.68 | 20.7 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 2.07 | 12.7 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.6 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.9 | 4.44 |
| filtering/detrend | 32768 | passed | 1.66e-05 | 0.712 | 1.95 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 14.2 | 14.9 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.74 | 3.22 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.92 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.92 | 8.93 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.5 | 23.9 |
| filtering/lfilter_zi | 512 | passed | 0 | 33.2 | 59.8 |
| filtering/resample | 32768 | passed | 3.86e-05 | 5.33 | 6.12 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.2 | 18.1 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.863 | 1.4 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.8 | 6.37 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 182 | 192 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.9 | 40.1 |
| radartools/ambgfun | 8192 | passed | 0 | 51.1 | 51.3 |
| radartools/ca_cfar | 1048576 | passed | 0 | 0.896 | 0.92 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00265 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 53.7 | 57.3 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.7 | 67.2 |
| spectral/csd | 32768 | passed | 8.11e-08 | 6.26 | 7.74 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.98 | 12.4 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.85 | 7.54 |
| spectral/stft | 32768 | passed | 1.69e-07 | 12.9 | 16.7 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 27.8 | 30.3 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.2 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.6 | 70.4 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37.3 | 43.3 |
| waveforms/square | 1048576 | passed | 0 | 43.8 | 53.1 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 24.7 | 142 |
| wavelets/cwt | 32768 | passed | 0 | 217 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 72.1 | 84.3 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.1 | 32.7 |
| wavelets/qmf | 1048576 | passed | 0 | 19.6 | 27.1 |
| wavelets/ricker | 1048576 | passed | 0 | 10.7 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 2.21 | 9.01 |
| windows/general_cosine | 1048576 | passed | 0 | 52.5 | 60.5 |
| windows/general_gaussian | 1048576 | passed | 0 | 179 | 236 |
| windows/hamming | 1048576 | passed | 0 | 33.7 | 46.2 |
| windows/kaiser | 1048576 | passed | 0 | 195 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.2 | 20.3 |
| windows/taylor | 1048576 | passed | 0 | 61.6 | 68 |
| windows/triang | 1048576 | passed | 0 | 14.3 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 2.07 | 12.7 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.6 |
| filtering/resample | 3.86e-05 | 5.33 | 6.12 |
| spectral/vectorstrength | 3.6e-05 | 27.8 | 30.3 |
| filtering/hilbert2 | 1.71e-05 | 23.5 | 23.9 |
| filtering/detrend | 1.66e-05 | 0.712 | 1.95 |
| filter_design/firwin | 1.09e-05 | 4.68 | 20.7 |
| spectral/lombscargle | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 7.01e-06 | 6.85 | 7.54 |
| waveforms/chirp | 3.92e-06 | 63.2 | 67 |
| spectral/istft | 3.43e-06 | 3.98 | 12.4 |
| filtering/hilbert | 1.97e-06 | 6.92 | 8.93 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00265 | 0 | 0 |
| filtering/detrend | 0.712 | 1.95 | 1.66e-05 |
| filtering/sosfilt | 0.863 | 1.4 | 8.25e-07 |
| radartools/ca_cfar | 0.896 | 0.92 | 0 |
| estimation/kalman_filter | 1.26 | 2.54 | 0 |
| filter_design/firwin2 | 2.07 | 12.7 | 7.58e-05 |
| windows/chebwin | 2.21 | 9.01 | 0 |
| correlate/correlate2d | 2.56 | 12.8 | 0 |
| filtering/firfilter2 | 2.74 | 3.22 | 8.15e-07 |
| filtering/decimate | 3.9 | 4.44 | 6.95e-07 |
| spectral/istft | 3.98 | 12.4 | 3.43e-06 |
| filter_design/firwin | 4.68 | 20.7 | 1.09e-05 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00265 | 0 |
| radartools/ca_cfar | 0.92 | 0.896 | 0 |
| filtering/sosfilt | 1.4 | 0.863 | 8.25e-07 |
| filtering/detrend | 1.95 | 0.712 | 1.66e-05 |
| estimation/kalman_filter | 2.54 | 1.26 | 0 |
| filtering/firfilter2 | 3.22 | 2.74 | 8.15e-07 |
| filtering/decimate | 4.44 | 3.9 | 6.95e-07 |
| filtering/resample | 6.12 | 5.33 | 3.86e-05 |
| filtering/upfirdn | 6.37 | 4.8 | 2.87e-07 |
| spectral/spectrogram | 7.54 | 6.85 | 7.01e-06 |
| spectral/csd | 7.74 | 6.26 | 8.11e-08 |
| bsplines/quadratic | 8.39 | 5.9 | 0 |
