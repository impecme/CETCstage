# All-Operator Benchmark Report

- run_id: `20260626_023932`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 7.66 | 10.9 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 41.6 | 57.5 |
| bsplines/quadratic | 1048576 | passed | 0 | 5.79 | 8.48 |
| correlate/correlate | 8192 | passed | 0 | 14 | 27.1 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.7 | 13.3 |
| demod/fm_demod | 1048576 | passed | 0 | 28.4 | 36.5 |
| estimation/kalman_filter | 512 | passed | 0 | 1.25 | 2.51 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.52 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 2.08 | 12.7 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.2 | 11.5 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.85 | 4.33 |
| filtering/detrend | 32768 | passed | 1.66e-05 | 0.726 | 1.93 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 14.2 | 14.9 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.58 | 3.09 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.76 | 14.6 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.16 | 8.61 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.3 | 23.8 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.1 | 59.5 |
| filtering/resample | 32768 | passed | 3.86e-05 | 5.44 | 5.95 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 12.2 | 18.4 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.846 | 1.39 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.67 | 6.25 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 181 | 189 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.8 | 39.8 |
| radartools/ambgfun | 8192 | passed | 0 | 51.1 | 51.3 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.22 | 5.45 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00243 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.1 | 57.5 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.2 | 68.7 |
| spectral/csd | 32768 | passed | 8.11e-08 | 6.36 | 7.78 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.92 | 11.7 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.84 | 7.5 |
| spectral/stft | 32768 | passed | 1.69e-07 | 12.9 | 16.5 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.1 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.6 | 67.1 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.3 | 73.3 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.5 | 43.1 |
| waveforms/square | 1048576 | passed | 0 | 43.9 | 53.4 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 20.7 | 124 |
| wavelets/cwt | 32768 | passed | 0 | 214 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 73 | 83.3 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.9 | 33.4 |
| wavelets/qmf | 1048576 | passed | 0 | 19.1 | 26.4 |
| wavelets/ricker | 1048576 | passed | 0 | 10.8 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 2.34 | 9.04 |
| windows/general_cosine | 1048576 | passed | 0 | 51.9 | 60.6 |
| windows/general_gaussian | 1048576 | passed | 0 | 178 | 235 |
| windows/hamming | 1048576 | passed | 0 | 33.6 | 46.2 |
| windows/kaiser | 1048576 | passed | 0 | 191 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.6 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 61.6 | 67.9 |
| windows/triang | 1048576 | passed | 0 | 14.2 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 2.08 | 12.7 |
| filtering/channelize_poly | 5.7e-05 | 10.2 | 11.5 |
| filtering/resample | 3.86e-05 | 5.44 | 5.95 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.1 |
| filtering/hilbert2 | 1.71e-05 | 23.3 | 23.8 |
| filtering/detrend | 1.66e-05 | 0.726 | 1.93 |
| filter_design/firwin | 1.09e-05 | 4.52 | 20.6 |
| spectral/lombscargle | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 7.01e-06 | 6.84 | 7.5 |
| waveforms/chirp | 3.92e-06 | 63.6 | 67.1 |
| spectral/istft | 3.43e-06 | 3.92 | 11.7 |
| filtering/hilbert | 1.97e-06 | 6.16 | 8.61 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00243 | 0 | 0 |
| filtering/detrend | 0.726 | 1.93 | 1.66e-05 |
| filtering/sosfilt | 0.846 | 1.39 | 8.25e-07 |
| estimation/kalman_filter | 1.25 | 2.51 | 0 |
| filter_design/firwin2 | 2.08 | 12.7 | 7.58e-05 |
| windows/chebwin | 2.34 | 9.04 | 0 |
| filtering/firfilter2 | 2.58 | 3.09 | 8.15e-07 |
| correlate/correlate2d | 2.7 | 13.3 | 0 |
| filtering/decimate | 3.85 | 4.33 | 6.95e-07 |
| spectral/istft | 3.92 | 11.7 | 3.43e-06 |
| radartools/ca_cfar | 4.22 | 5.45 | 0 |
| filter_design/firwin | 4.52 | 20.6 | 1.09e-05 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00243 | 0 |
| filtering/sosfilt | 1.39 | 0.846 | 8.25e-07 |
| filtering/detrend | 1.93 | 0.726 | 1.66e-05 |
| estimation/kalman_filter | 2.51 | 1.25 | 0 |
| filtering/firfilter2 | 3.09 | 2.58 | 8.15e-07 |
| filtering/decimate | 4.33 | 3.85 | 6.95e-07 |
| radartools/ca_cfar | 5.45 | 4.22 | 0 |
| filtering/resample | 5.95 | 5.44 | 3.86e-05 |
| filtering/upfirdn | 6.25 | 4.67 | 2.87e-07 |
| spectral/spectrogram | 7.5 | 6.84 | 7.01e-06 |
| spectral/csd | 7.78 | 6.36 | 8.11e-08 |
| bsplines/quadratic | 8.48 | 5.79 | 0 |
