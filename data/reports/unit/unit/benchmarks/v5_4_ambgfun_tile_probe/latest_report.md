# All-Operator Benchmark Report

- run_id: `20260625_160732`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.79 | 0.828 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.2 | 2.25 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.606 | 0.637 |
| correlate/correlate | 8192 | passed | 0 | 13.7 | 26.9 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.59 | 12.9 |
| demod/fm_demod | 1048576 | passed | 0 | 28.3 | 36.7 |
| estimation/kalman_filter | 512 | passed | 0 | 1.22 | 2.38 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.68 | 20.7 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.651 | 0.865 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.86 | 4.38 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.716 | 1.83 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.2 | 12.8 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.62 | 3.09 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.88 | 14.6 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.14 | 7.78 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.2 | 23.6 |
| filtering/lfilter_zi | 512 | passed | 0 | 33 | 59.7 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.65 | 5.79 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.1 | 18.1 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.819 | 1.31 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.67 | 6.22 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 223 | 233 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.6 | 40.2 |
| radartools/ambgfun | 8192 | passed | 0 | 47.8 | 47.9 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.43 | 5 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00253 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.2 | 57.6 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.3 | 67.6 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.9 | 2.01 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.68 | 11.1 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 171 | 174 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.69 | 7.38 |
| spectral/stft | 32768 | passed | 1.69e-07 | 12.7 | 16.4 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 27.7 | 30.3 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 64.6 | 66.9 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.5 | 73.4 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37 | 43.2 |
| waveforms/square | 1048576 | passed | 0 | 44.6 | 53.4 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 23.1 | 133 |
| wavelets/cwt | 32768 | passed | 0 | 216 | 224 |
| wavelets/morlet | 1048576 | passed | 0 | 72.8 | 84.2 |
| wavelets/morlet2 | 1048576 | passed | 0 | 32.1 | 33.2 |
| wavelets/qmf | 1048576 | passed | 0 | 20.6 | 27.4 |
| wavelets/ricker | 1048576 | passed | 0 | 14.1 | 14.7 |
| windows/chebwin | 1536 | passed | 0 | 2.51 | 8.94 |
| windows/general_cosine | 1048576 | passed | 0 | 52.1 | 60.6 |
| windows/general_gaussian | 1048576 | passed | 0 | 172 | 236 |
| windows/hamming | 1048576 | passed | 0 | 32.3 | 46.3 |
| windows/kaiser | 1048576 | passed | 0 | 192 | 219 |
| windows/parzen | 1048576 | passed | 0 | 13.8 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 62.1 | 67.9 |
| windows/triang | 1048576 | passed | 0 | 14.5 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.651 | 0.865 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 4.65 | 5.79 |
| spectral/vectorstrength | 3.6e-05 | 27.7 | 30.3 |
| filtering/hilbert2 | 1.71e-05 | 23.2 | 23.6 |
| filter_design/firwin | 1.09e-05 | 4.68 | 20.7 |
| spectral/lombscargle | 9.62e-06 | 171 | 174 |
| spectral/spectrogram | 7.01e-06 | 6.69 | 7.38 |
| filtering/detrend | 4.59e-06 | 0.716 | 1.83 |
| waveforms/chirp | 3.92e-06 | 64.6 | 66.9 |
| spectral/istft | 3.43e-06 | 3.68 | 11.1 |
| filtering/hilbert | 1.97e-06 | 6.14 | 7.78 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00253 | 0 | 0 |
| bsplines/quadratic | 0.606 | 0.637 | 0 |
| filter_design/firwin2 | 0.651 | 0.865 | 7.58e-05 |
| filtering/detrend | 0.716 | 1.83 | 4.59e-06 |
| bsplines/cubic | 0.79 | 0.828 | 0 |
| filtering/sosfilt | 0.819 | 1.31 | 8.25e-07 |
| estimation/kalman_filter | 1.22 | 2.38 | 0 |
| spectral/csd | 1.9 | 2.01 | 2.22e-07 |
| bsplines/gauss_spline | 2.2 | 2.25 | 0 |
| windows/chebwin | 2.51 | 8.94 | 0 |
| correlate/correlate2d | 2.59 | 12.9 | 0 |
| filtering/firfilter2 | 2.62 | 3.09 | 8.15e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00253 | 0 |
| bsplines/quadratic | 0.637 | 0.606 | 0 |
| bsplines/cubic | 0.828 | 0.79 | 0 |
| filter_design/firwin2 | 0.865 | 0.651 | 7.58e-05 |
| filtering/sosfilt | 1.31 | 0.819 | 8.25e-07 |
| filtering/detrend | 1.83 | 0.716 | 4.59e-06 |
| spectral/csd | 2.01 | 1.9 | 2.22e-07 |
| bsplines/gauss_spline | 2.25 | 2.2 | 0 |
| estimation/kalman_filter | 2.38 | 1.22 | 0 |
| filtering/firfilter2 | 3.09 | 2.62 | 8.15e-07 |
| filtering/decimate | 4.38 | 3.86 | 6.95e-07 |
| radartools/ca_cfar | 5 | 4.43 | 0 |
