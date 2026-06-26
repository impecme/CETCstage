# All-Operator Benchmark Report

- run_id: `20260625_135527`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.767 | 0.809 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.18 | 2.24 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.613 | 0.643 |
| correlate/correlate | 8192 | passed | 0 | 13.3 | 26.1 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.57 | 12.8 |
| demod/fm_demod | 1048576 | passed | 0 | 28.5 | 36.5 |
| estimation/kalman_filter | 512 | passed | 0 | 1.2 | 2.42 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.72 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.653 | 0.866 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.4 | 11.8 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.94 | 4.54 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.718 | 1.84 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.1 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.56 | 3.03 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.8 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.28 | 7.96 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.1 | 23.6 |
| filtering/lfilter_zi | 512 | passed | 0 | 33 | 59.5 |
| filtering/resample | 32768 | passed | 3.86e-05 | 5.31 | 6.03 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.5 | 18.9 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.803 | 1.31 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.7 | 6.3 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 184 | 192 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.3 | 40.2 |
| radartools/ambgfun | 8192 | passed | 0 | 47.6 | 47.8 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.25 | 4.78 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00274 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.2 | 57.7 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 30.7 | 66.8 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.84 | 1.96 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.62 | 12.3 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.7 | 68.4 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.74 | 7.44 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.6 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 64.4 | 67.1 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.1 | 73.3 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.4 | 43.3 |
| waveforms/square | 1048576 | passed | 0 | 44.5 | 53.2 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 21.4 | 123 |
| wavelets/cwt | 32768 | passed | 0 | 224 | 231 |
| wavelets/morlet | 1048576 | passed | 0 | 69.8 | 83.9 |
| wavelets/morlet2 | 1048576 | passed | 0 | 32.1 | 33.4 |
| wavelets/qmf | 1048576 | passed | 0 | 19.2 | 27 |
| wavelets/ricker | 1048576 | passed | 0 | 14 | 14.8 |
| windows/chebwin | 1536 | passed | 0 | 2.22 | 8.2 |
| windows/general_cosine | 1048576 | passed | 0 | 3.96 | 4.05 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.03 | 6.07 |
| windows/hamming | 1048576 | passed | 0 | 1.4 | 1.42 |
| windows/kaiser | 1048576 | passed | 0 | 254 | 285 |
| windows/parzen | 1048576 | passed | 0 | 0.416 | 0.422 |
| windows/taylor | 1048576 | passed | 0 | 1.6 | 1.61 |
| windows/triang | 1048576 | passed | 0 | 0.0833 | 0.084 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.653 | 0.866 |
| filtering/channelize_poly | 5.7e-05 | 10.4 | 11.8 |
| filtering/resample | 3.86e-05 | 5.31 | 6.03 |
| spectral/vectorstrength | 3.6e-05 | 28 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 23.1 | 23.6 |
| filter_design/firwin | 1.09e-05 | 4.72 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 67.7 | 68.4 |
| spectral/spectrogram | 7.01e-06 | 6.74 | 7.44 |
| filtering/detrend | 4.59e-06 | 0.718 | 1.84 |
| waveforms/chirp | 3.92e-06 | 64.4 | 67.1 |
| spectral/istft | 3.43e-06 | 3.62 | 12.3 |
| filtering/hilbert | 1.97e-06 | 6.28 | 7.96 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00274 | 0 | 0 |
| windows/triang | 0.0833 | 0.084 | 0 |
| windows/parzen | 0.416 | 0.422 | 0 |
| bsplines/quadratic | 0.613 | 0.643 | 0 |
| filter_design/firwin2 | 0.653 | 0.866 | 7.58e-05 |
| filtering/detrend | 0.718 | 1.84 | 4.59e-06 |
| bsplines/cubic | 0.767 | 0.809 | 0 |
| filtering/sosfilt | 0.803 | 1.31 | 8.25e-07 |
| estimation/kalman_filter | 1.2 | 2.42 | 0 |
| windows/hamming | 1.4 | 1.42 | 0 |
| windows/taylor | 1.6 | 1.61 | 0 |
| spectral/csd | 1.84 | 1.96 | 2.22e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00274 | 0 |
| windows/triang | 0.084 | 0.0833 | 0 |
| windows/parzen | 0.422 | 0.416 | 0 |
| bsplines/quadratic | 0.643 | 0.613 | 0 |
| bsplines/cubic | 0.809 | 0.767 | 0 |
| filter_design/firwin2 | 0.866 | 0.653 | 7.58e-05 |
| filtering/sosfilt | 1.31 | 0.803 | 8.25e-07 |
| windows/hamming | 1.42 | 1.4 | 0 |
| windows/taylor | 1.61 | 1.6 | 0 |
| filtering/detrend | 1.84 | 0.718 | 4.59e-06 |
| spectral/csd | 1.96 | 1.84 | 2.22e-07 |
| bsplines/gauss_spline | 2.24 | 2.18 | 0 |
