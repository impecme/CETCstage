# All-Operator Benchmark Report

- run_id: `20260625_164858`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 7.87 | 11 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 41.3 | 57.3 |
| bsplines/quadratic | 1048576 | passed | 0 | 6.11 | 8.57 |
| correlate/correlate | 8192 | passed | 0 | 14.1 | 25.9 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.52 | 12.8 |
| demod/fm_demod | 1048576 | passed | 0 | 28.6 | 36.7 |
| estimation/kalman_filter | 512 | passed | 0 | 1.19 | 2.38 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.64 | 20.8 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.671 | 0.872 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.5 | 11.9 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.97 | 4.52 |
| filtering/detrend | 32768 | passed | 1.66e-05 | 0.734 | 1.91 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.2 | 12.8 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.62 | 3.09 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.33 | 14.8 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.55 | 8.51 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.3 | 23.6 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.8 | 59.2 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.68 | 5.77 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.2 | 18.3 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.839 | 1.31 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 3.89 | 5.55 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 191 | 202 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.9 | 40.1 |
| radartools/ambgfun | 8192 | passed | 0 | 50.9 | 51.1 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.16 | 4.88 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00264 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 51.4 | 53.6 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 29.5 | 67.9 |
| spectral/csd | 32768 | passed | 8.11e-08 | 6.37 | 7.75 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.93 | 12.4 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 173 | 175 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.77 | 7.47 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.3 | 16.7 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.1 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 64.3 | 67.2 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 71 | 81 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37.4 | 43.5 |
| waveforms/square | 1048576 | passed | 0 | 43.5 | 53.6 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 21.3 | 120 |
| wavelets/cwt | 32768 | passed | 0 | 217 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 74.2 | 83.2 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.5 | 33.3 |
| wavelets/qmf | 1048576 | passed | 0 | 19.1 | 27.7 |
| wavelets/ricker | 1048576 | passed | 0 | 10.8 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 1.98 | 8.28 |
| windows/general_cosine | 1048576 | passed | 0 | 52.7 | 60.6 |
| windows/general_gaussian | 1048576 | passed | 0 | 172 | 237 |
| windows/hamming | 1048576 | passed | 0 | 33.6 | 46 |
| windows/kaiser | 1048576 | passed | 0 | 194 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.6 | 20.1 |
| windows/taylor | 1048576 | passed | 0 | 62.4 | 68 |
| windows/triang | 1048576 | passed | 0 | 14.3 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.671 | 0.872 |
| filtering/channelize_poly | 5.7e-05 | 10.5 | 11.9 |
| filtering/resample | 3.86e-05 | 4.68 | 5.77 |
| spectral/vectorstrength | 3.6e-05 | 28.1 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 23.3 | 23.6 |
| filtering/detrend | 1.66e-05 | 0.734 | 1.91 |
| filter_design/firwin | 1.09e-05 | 4.64 | 20.8 |
| spectral/lombscargle | 9.62e-06 | 173 | 175 |
| spectral/spectrogram | 7.01e-06 | 6.77 | 7.47 |
| waveforms/chirp | 3.92e-06 | 64.3 | 67.2 |
| spectral/istft | 3.43e-06 | 3.93 | 12.4 |
| filtering/hilbert | 1.97e-06 | 6.55 | 8.51 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00264 | 0 | 0 |
| filter_design/firwin2 | 0.671 | 0.872 | 7.58e-05 |
| filtering/detrend | 0.734 | 1.91 | 1.66e-05 |
| filtering/sosfilt | 0.839 | 1.31 | 8.25e-07 |
| estimation/kalman_filter | 1.19 | 2.38 | 0 |
| windows/chebwin | 1.98 | 8.28 | 0 |
| correlate/correlate2d | 2.52 | 12.8 | 0 |
| filtering/firfilter2 | 2.62 | 3.09 | 8.15e-07 |
| filtering/upfirdn | 3.89 | 5.55 | 2.87e-07 |
| spectral/istft | 3.93 | 12.4 | 3.43e-06 |
| filtering/decimate | 3.97 | 4.52 | 6.95e-07 |
| radartools/ca_cfar | 4.16 | 4.88 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00264 | 0 |
| filter_design/firwin2 | 0.872 | 0.671 | 7.58e-05 |
| filtering/sosfilt | 1.31 | 0.839 | 8.25e-07 |
| filtering/detrend | 1.91 | 0.734 | 1.66e-05 |
| estimation/kalman_filter | 2.38 | 1.19 | 0 |
| filtering/firfilter2 | 3.09 | 2.62 | 8.15e-07 |
| filtering/decimate | 4.52 | 3.97 | 6.95e-07 |
| radartools/ca_cfar | 4.88 | 4.16 | 0 |
| filtering/upfirdn | 5.55 | 3.89 | 2.87e-07 |
| filtering/resample | 5.77 | 4.68 | 3.86e-05 |
| spectral/spectrogram | 7.47 | 6.77 | 7.01e-06 |
| spectral/csd | 7.75 | 6.37 | 8.11e-08 |
