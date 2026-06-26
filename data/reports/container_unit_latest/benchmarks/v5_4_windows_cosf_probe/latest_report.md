# All-Operator Benchmark Report

- run_id: `20260625_141803`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.797 | 0.834 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.16 | 2.24 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.6 | 0.631 |
| correlate/correlate | 8192 | passed | 0 | 13.6 | 26.7 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.66 | 13.3 |
| demod/fm_demod | 1048576 | passed | 0 | 28.6 | 36.7 |
| estimation/kalman_filter | 512 | passed | 0 | 1.16 | 2.31 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.56 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.658 | 0.866 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.85 | 4.5 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.745 | 1.87 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.59 | 3.07 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.76 | 14.6 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 7.1 | 9.04 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 32.4 | 33 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.7 | 59.2 |
| filtering/resample | 32768 | passed | 3.86e-05 | 5.62 | 6.23 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.6 | 19 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.84 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.69 | 6.31 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 185 | 192 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.6 | 39.7 |
| radartools/ambgfun | 8192 | passed | 0 | 48.1 | 48.3 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.22 | 5.44 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00244 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 50.4 | 53.5 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 29.7 | 58.2 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.81 | 1.93 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.63 | 12.3 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 68.1 | 68.6 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.76 | 7.51 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.6 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.1 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 62.4 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.8 | 73.3 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37.2 | 43.4 |
| waveforms/square | 1048576 | passed | 0 | 43.7 | 53.7 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 19.5 | 126 |
| wavelets/cwt | 32768 | passed | 0 | 215 | 224 |
| wavelets/morlet | 1048576 | passed | 0 | 66.4 | 81.4 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.6 | 33.1 |
| wavelets/qmf | 1048576 | passed | 0 | 18.3 | 26.4 |
| wavelets/ricker | 1048576 | passed | 0 | 10.7 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 1.75 | 8.77 |
| windows/general_cosine | 1048576 | passed | 0 | 3.93 | 4.04 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.07 | 6.14 |
| windows/hamming | 1048576 | passed | 0 | 1.4 | 1.43 |
| windows/kaiser | 1048576 | passed | 0 | 195 | 220 |
| windows/parzen | 1048576 | passed | 0 | 14.4 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 5.83 | 6.01 |
| windows/triang | 1048576 | passed | 0 | 13.8 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.658 | 0.866 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 5.62 | 6.23 |
| spectral/vectorstrength | 3.6e-05 | 28.1 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 32.4 | 33 |
| filter_design/firwin | 1.09e-05 | 4.56 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 68.1 | 68.6 |
| spectral/spectrogram | 7.01e-06 | 6.76 | 7.51 |
| filtering/detrend | 4.59e-06 | 0.745 | 1.87 |
| waveforms/chirp | 3.92e-06 | 62.4 | 67 |
| spectral/istft | 3.43e-06 | 3.63 | 12.3 |
| filtering/hilbert | 1.97e-06 | 7.1 | 9.04 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00244 | 0 | 0 |
| bsplines/quadratic | 0.6 | 0.631 | 0 |
| filter_design/firwin2 | 0.658 | 0.866 | 7.58e-05 |
| filtering/detrend | 0.745 | 1.87 | 4.59e-06 |
| bsplines/cubic | 0.797 | 0.834 | 0 |
| filtering/sosfilt | 0.84 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.16 | 2.31 | 0 |
| windows/hamming | 1.4 | 1.43 | 0 |
| windows/chebwin | 1.75 | 8.77 | 0 |
| spectral/csd | 1.81 | 1.93 | 2.22e-07 |
| bsplines/gauss_spline | 2.16 | 2.24 | 0 |
| filtering/firfilter2 | 2.59 | 3.07 | 8.15e-07 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00244 | 0 |
| bsplines/quadratic | 0.631 | 0.6 | 0 |
| bsplines/cubic | 0.834 | 0.797 | 0 |
| filter_design/firwin2 | 0.866 | 0.658 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.84 | 8.25e-07 |
| windows/hamming | 1.43 | 1.4 | 0 |
| filtering/detrend | 1.87 | 0.745 | 4.59e-06 |
| spectral/csd | 1.93 | 1.81 | 2.22e-07 |
| bsplines/gauss_spline | 2.24 | 2.16 | 0 |
| estimation/kalman_filter | 2.31 | 1.16 | 0 |
| filtering/firfilter2 | 3.07 | 2.59 | 8.15e-07 |
| windows/general_cosine | 4.04 | 3.93 | 0 |
