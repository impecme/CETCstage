# All-Operator Benchmark Report

- run_id: `20260625_132101`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.773 | 0.819 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.18 | 2.25 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.609 | 0.64 |
| correlate/correlate | 8192 | passed | 0 | 13.1 | 25.4 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.65 | 13.1 |
| demod/fm_demod | 1048576 | passed | 0 | 28.5 | 36.7 |
| estimation/kalman_filter | 512 | passed | 0 | 1.39 | 2.61 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.67 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.643 | 0.866 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.2 | 11.5 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.89 | 4.57 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.74 | 1.87 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.1 | 12.7 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.62 | 3.08 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.99 | 14.5 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.66 | 8.35 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.4 | 23.8 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.8 | 59.2 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.8 | 6.21 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.6 | 18.4 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.814 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.69 | 6.24 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 187 | 196 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.4 | 40.8 |
| radartools/ambgfun | 8192 | passed | 0 | 47.7 | 47.8 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.2 | 4.76 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00267 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.3 | 58 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 30.8 | 59.8 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.82 | 1.95 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.62 | 12.3 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 68 | 68.4 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.7 | 7.42 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.4 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 62.4 | 67.1 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.8 | 73.4 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.8 | 43 |
| waveforms/square | 1048576 | passed | 0 | 44 | 53.5 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 23.4 | 131 |
| wavelets/cwt | 32768 | passed | 0 | 211 | 223 |
| wavelets/morlet | 1048576 | passed | 0 | 1.64 | 1.64 |
| wavelets/morlet2 | 1048576 | passed | 0 | 3.5 | 3.53 |
| wavelets/qmf | 1048576 | passed | 0 | 19.2 | 26.5 |
| wavelets/ricker | 1048576 | passed | 0 | 0.4 | 0.4 |
| windows/chebwin | 1536 | passed | 0 | 2.36 | 9.01 |
| windows/general_cosine | 1048576 | passed | 0 | 3.96 | 4.04 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.05 | 6.14 |
| windows/hamming | 1048576 | passed | 0 | 1.39 | 1.41 |
| windows/kaiser | 1048576 | passed | 0 | 193 | 219 |
| windows/parzen | 1048576 | passed | 0 | 0.423 | 0.438 |
| windows/taylor | 1048576 | passed | 0 | 1.59 | 1.6 |
| windows/triang | 1048576 | passed | 0 | 0.0849 | 0.0857 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.643 | 0.866 |
| filtering/channelize_poly | 5.7e-05 | 10.2 | 11.5 |
| filtering/resample | 3.86e-05 | 4.8 | 6.21 |
| spectral/vectorstrength | 3.6e-05 | 28 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 23.4 | 23.8 |
| filter_design/firwin | 1.09e-05 | 4.67 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 68 | 68.4 |
| spectral/spectrogram | 7.01e-06 | 6.7 | 7.42 |
| filtering/detrend | 4.59e-06 | 0.74 | 1.87 |
| waveforms/chirp | 3.92e-06 | 62.4 | 67.1 |
| spectral/istft | 3.43e-06 | 3.62 | 12.3 |
| filtering/hilbert | 1.97e-06 | 6.66 | 8.35 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00267 | 0 | 0 |
| windows/triang | 0.0849 | 0.0857 | 0 |
| wavelets/ricker | 0.4 | 0.4 | 0 |
| windows/parzen | 0.423 | 0.438 | 0 |
| bsplines/quadratic | 0.609 | 0.64 | 0 |
| filter_design/firwin2 | 0.643 | 0.866 | 7.58e-05 |
| filtering/detrend | 0.74 | 1.87 | 4.59e-06 |
| bsplines/cubic | 0.773 | 0.819 | 0 |
| filtering/sosfilt | 0.814 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.39 | 2.61 | 0 |
| windows/hamming | 1.39 | 1.41 | 0 |
| windows/taylor | 1.59 | 1.6 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00267 | 0 |
| windows/triang | 0.0857 | 0.0849 | 0 |
| wavelets/ricker | 0.4 | 0.4 | 0 |
| windows/parzen | 0.438 | 0.423 | 0 |
| bsplines/quadratic | 0.64 | 0.609 | 0 |
| bsplines/cubic | 0.819 | 0.773 | 0 |
| filter_design/firwin2 | 0.866 | 0.643 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.814 | 8.25e-07 |
| windows/hamming | 1.41 | 1.39 | 0 |
| windows/taylor | 1.6 | 1.59 | 0 |
| wavelets/morlet | 1.64 | 1.64 | 0 |
| filtering/detrend | 1.87 | 0.74 | 4.59e-06 |
