# All-Operator Benchmark Report

- run_id: `20260625_144623`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.775 | 0.814 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.18 | 2.25 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.603 | 0.631 |
| correlate/correlate | 8192 | passed | 0 | 13.7 | 26.8 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.59 | 13.3 |
| demod/fm_demod | 1048576 | passed | 0 | 28.1 | 36.6 |
| estimation/kalman_filter | 512 | passed | 0 | 1.43 | 2.81 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.66 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.633 | 0.864 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.6 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.99 | 4.61 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.733 | 1.83 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.1 | 12.7 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.57 | 3.04 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.82 | 14.6 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.55 | 8.37 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 32.2 | 33 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.8 | 59.4 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.88 | 5.81 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16 | 18.3 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.819 | 1.31 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.73 | 6.25 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 292 | 302 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.1 | 40.4 |
| radartools/ambgfun | 8192 | passed | 0 | 47.6 | 47.7 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.14 | 4.68 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00229 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.6 | 57.3 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 30.4 | 67.1 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.83 | 1.95 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.96 | 12.2 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.7 | 68.3 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.71 | 7.41 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13 | 16.6 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.8 | 67.3 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.3 | 73.1 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 35.3 | 44.5 |
| waveforms/square | 1048576 | passed | 0 | 41.2 | 53.3 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 20 | 113 |
| wavelets/cwt | 32768 | passed | 0 | 214 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 74 | 83.8 |
| wavelets/morlet2 | 1048576 | passed | 0 | 29 | 30.2 |
| wavelets/qmf | 1048576 | passed | 0 | 19 | 26.8 |
| wavelets/ricker | 1048576 | passed | 0 | 10.9 | 11.5 |
| windows/chebwin | 1536 | passed | 0 | 2.27 | 8.78 |
| windows/general_cosine | 1048576 | passed | 0 | 52.3 | 60.5 |
| windows/general_gaussian | 1048576 | passed | 0 | 143 | 234 |
| windows/hamming | 1048576 | passed | 0 | 30.3 | 46.1 |
| windows/kaiser | 1048576 | passed | 0 | 190 | 220 |
| windows/parzen | 1048576 | passed | 0 | 14.7 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 5.87 | 6.03 |
| windows/triang | 1048576 | passed | 0 | 14.3 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.633 | 0.864 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.6 |
| filtering/resample | 3.86e-05 | 4.88 | 5.81 |
| spectral/vectorstrength | 3.6e-05 | 28 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 32.2 | 33 |
| filter_design/firwin | 1.09e-05 | 4.66 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 67.7 | 68.3 |
| spectral/spectrogram | 7.01e-06 | 6.71 | 7.41 |
| filtering/detrend | 4.59e-06 | 0.733 | 1.83 |
| waveforms/chirp | 3.92e-06 | 63.8 | 67.3 |
| spectral/istft | 3.43e-06 | 3.96 | 12.2 |
| filtering/hilbert | 1.97e-06 | 6.55 | 8.37 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00229 | 0 | 0 |
| bsplines/quadratic | 0.603 | 0.631 | 0 |
| filter_design/firwin2 | 0.633 | 0.864 | 7.58e-05 |
| filtering/detrend | 0.733 | 1.83 | 4.59e-06 |
| bsplines/cubic | 0.775 | 0.814 | 0 |
| filtering/sosfilt | 0.819 | 1.31 | 8.25e-07 |
| estimation/kalman_filter | 1.43 | 2.81 | 0 |
| spectral/csd | 1.83 | 1.95 | 2.22e-07 |
| bsplines/gauss_spline | 2.18 | 2.25 | 0 |
| windows/chebwin | 2.27 | 8.78 | 0 |
| filtering/firfilter2 | 2.57 | 3.04 | 8.15e-07 |
| correlate/correlate2d | 2.59 | 13.3 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00229 | 0 |
| bsplines/quadratic | 0.631 | 0.603 | 0 |
| bsplines/cubic | 0.814 | 0.775 | 0 |
| filter_design/firwin2 | 0.864 | 0.633 | 7.58e-05 |
| filtering/sosfilt | 1.31 | 0.819 | 8.25e-07 |
| filtering/detrend | 1.83 | 0.733 | 4.59e-06 |
| spectral/csd | 1.95 | 1.83 | 2.22e-07 |
| bsplines/gauss_spline | 2.25 | 2.18 | 0 |
| estimation/kalman_filter | 2.81 | 1.43 | 0 |
| filtering/firfilter2 | 3.04 | 2.57 | 8.15e-07 |
| filtering/decimate | 4.61 | 3.99 | 6.95e-07 |
| radartools/ca_cfar | 4.68 | 4.14 | 0 |
