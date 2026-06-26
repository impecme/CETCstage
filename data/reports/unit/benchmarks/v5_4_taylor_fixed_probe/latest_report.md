# All-Operator Benchmark Report

- run_id: `20260625_152444`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.785 | 0.824 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.18 | 2.24 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.599 | 0.628 |
| correlate/correlate | 8192 | passed | 0 | 13 | 26.5 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.39 | 12.8 |
| demod/fm_demod | 1048576 | passed | 0 | 28.6 | 36.7 |
| estimation/kalman_filter | 512 | passed | 0 | 1.04 | 2.38 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 5.54 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.535 | 0.829 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4.01 | 4.44 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.731 | 1.84 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 11.8 | 12.8 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.61 | 3.1 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.79 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 7.12 | 9.08 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 32.8 | 33.6 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.7 | 59.2 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.52 | 6.01 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.1 | 18.4 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.823 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.58 | 6.29 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 222 | 230 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.9 | 40.7 |
| radartools/ambgfun | 8192 | passed | 0 | 47.4 | 47.6 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.27 | 4.81 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00283 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.6 | 58.5 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.3 | 67.6 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.8 | 1.94 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.9 | 12 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.9 | 68.4 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.73 | 7.43 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.7 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 59.2 | 63.7 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66 | 73.3 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.8 | 43.2 |
| waveforms/square | 1048576 | passed | 0 | 44.2 | 53.4 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 19.3 | 112 |
| wavelets/cwt | 32768 | passed | 0 | 215 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 73 | 82.9 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.7 | 33.2 |
| wavelets/qmf | 1048576 | passed | 0 | 18.9 | 27.4 |
| wavelets/ricker | 1048576 | passed | 0 | 10.8 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 1.92 | 9.25 |
| windows/general_cosine | 1048576 | passed | 0 | 52.1 | 60.6 |
| windows/general_gaussian | 1048576 | passed | 0 | 176 | 235 |
| windows/hamming | 1048576 | passed | 0 | 32.7 | 46 |
| windows/kaiser | 1048576 | passed | 0 | 191 | 213 |
| windows/parzen | 1048576 | passed | 0 | 14.5 | 20.3 |
| windows/taylor | 1048576 | passed | 0 | 61.7 | 68 |
| windows/triang | 1048576 | passed | 0 | 14.2 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.535 | 0.829 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 4.52 | 6.01 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 32.8 | 33.6 |
| filter_design/firwin | 1.09e-05 | 5.54 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 67.9 | 68.4 |
| spectral/spectrogram | 7.01e-06 | 6.73 | 7.43 |
| filtering/detrend | 4.59e-06 | 0.731 | 1.84 |
| waveforms/chirp | 3.92e-06 | 59.2 | 63.7 |
| spectral/istft | 3.43e-06 | 3.9 | 12 |
| filtering/hilbert | 1.97e-06 | 7.12 | 9.08 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00283 | 0 | 0 |
| filter_design/firwin2 | 0.535 | 0.829 | 7.58e-05 |
| bsplines/quadratic | 0.599 | 0.628 | 0 |
| filtering/detrend | 0.731 | 1.84 | 4.59e-06 |
| bsplines/cubic | 0.785 | 0.824 | 0 |
| filtering/sosfilt | 0.823 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.04 | 2.38 | 0 |
| spectral/csd | 1.8 | 1.94 | 2.22e-07 |
| windows/chebwin | 1.92 | 9.25 | 0 |
| bsplines/gauss_spline | 2.18 | 2.24 | 0 |
| correlate/correlate2d | 2.39 | 12.8 | 0 |
| filtering/firfilter2 | 2.61 | 3.1 | 8.15e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00283 | 0 |
| bsplines/quadratic | 0.628 | 0.599 | 0 |
| bsplines/cubic | 0.824 | 0.785 | 0 |
| filter_design/firwin2 | 0.829 | 0.535 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.823 | 8.25e-07 |
| filtering/detrend | 1.84 | 0.731 | 4.59e-06 |
| spectral/csd | 1.94 | 1.8 | 2.22e-07 |
| bsplines/gauss_spline | 2.24 | 2.18 | 0 |
| estimation/kalman_filter | 2.38 | 1.04 | 0 |
| filtering/firfilter2 | 3.1 | 2.61 | 8.15e-07 |
| filtering/decimate | 4.44 | 4.01 | 6.95e-07 |
| radartools/ca_cfar | 4.81 | 4.27 | 0 |
