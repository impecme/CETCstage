# All-Operator Benchmark Report

- run_id: `20260625_142722`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.774 | 0.808 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.2 | 2.25 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.594 | 0.627 |
| correlate/correlate | 8192 | passed | 0 | 13.9 | 26.9 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.68 | 13.1 |
| demod/fm_demod | 1048576 | passed | 0 | 28.1 | 36.7 |
| estimation/kalman_filter | 512 | passed | 0 | 1.21 | 2.38 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.56 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.552 | 0.85 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.91 | 4.44 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.737 | 1.89 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.63 | 3.11 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.87 | 14.8 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.79 | 8.78 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.1 | 23.7 |
| filtering/lfilter_zi | 512 | passed | 0 | 33.1 | 57.3 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.89 | 6.12 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.3 | 18.4 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.82 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.6 | 6.28 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 195 | 206 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.1 | 40.6 |
| radartools/ambgfun | 8192 | passed | 0 | 47.1 | 47.2 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.24 | 4.8 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00244 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.2 | 57.4 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.3 | 69.2 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.83 | 1.96 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.96 | 12 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.9 | 68.4 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.72 | 7.43 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.1 | 16.5 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.3 | 30.3 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.2 | 74.3 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37 | 43.1 |
| waveforms/square | 1048576 | passed | 0 | 44.3 | 53.5 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 21 | 125 |
| wavelets/cwt | 32768 | passed | 0 | 216 | 224 |
| wavelets/morlet | 1048576 | passed | 0 | 73.1 | 83.3 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.1 | 32.7 |
| wavelets/qmf | 1048576 | passed | 0 | 19.2 | 27.4 |
| wavelets/ricker | 1048576 | passed | 0 | 10.8 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 2.52 | 8.8 |
| windows/general_cosine | 1048576 | passed | 0 | 3.95 | 4.05 |
| windows/general_gaussian | 1048576 | passed | 0 | 6.08 | 6.14 |
| windows/hamming | 1048576 | passed | 0 | 33.5 | 46.2 |
| windows/kaiser | 1048576 | passed | 0 | 195 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.4 | 20.1 |
| windows/taylor | 1048576 | passed | 0 | 5.91 | 5.99 |
| windows/triang | 1048576 | passed | 0 | 14.7 | 21.6 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.552 | 0.85 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 4.89 | 6.12 |
| spectral/vectorstrength | 3.6e-05 | 28.3 | 30.3 |
| filtering/hilbert2 | 1.71e-05 | 23.1 | 23.7 |
| filter_design/firwin | 1.09e-05 | 4.56 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 67.9 | 68.4 |
| spectral/spectrogram | 7.01e-06 | 6.72 | 7.43 |
| filtering/detrend | 4.59e-06 | 0.737 | 1.89 |
| waveforms/chirp | 3.92e-06 | 63 | 67 |
| spectral/istft | 3.43e-06 | 3.96 | 12 |
| filtering/hilbert | 1.97e-06 | 6.79 | 8.78 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00244 | 0 | 0 |
| filter_design/firwin2 | 0.552 | 0.85 | 7.58e-05 |
| bsplines/quadratic | 0.594 | 0.627 | 0 |
| filtering/detrend | 0.737 | 1.89 | 4.59e-06 |
| bsplines/cubic | 0.774 | 0.808 | 0 |
| filtering/sosfilt | 0.82 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.21 | 2.38 | 0 |
| spectral/csd | 1.83 | 1.96 | 2.22e-07 |
| bsplines/gauss_spline | 2.2 | 2.25 | 0 |
| windows/chebwin | 2.52 | 8.8 | 0 |
| filtering/firfilter2 | 2.63 | 3.11 | 8.15e-07 |
| correlate/correlate2d | 2.68 | 13.1 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00244 | 0 |
| bsplines/quadratic | 0.627 | 0.594 | 0 |
| bsplines/cubic | 0.808 | 0.774 | 0 |
| filter_design/firwin2 | 0.85 | 0.552 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.82 | 8.25e-07 |
| filtering/detrend | 1.89 | 0.737 | 4.59e-06 |
| spectral/csd | 1.96 | 1.83 | 2.22e-07 |
| bsplines/gauss_spline | 2.25 | 2.2 | 0 |
| estimation/kalman_filter | 2.38 | 1.21 | 0 |
| filtering/firfilter2 | 3.11 | 2.63 | 8.15e-07 |
| windows/general_cosine | 4.05 | 3.95 | 0 |
| filtering/decimate | 4.44 | 3.91 | 6.95e-07 |
