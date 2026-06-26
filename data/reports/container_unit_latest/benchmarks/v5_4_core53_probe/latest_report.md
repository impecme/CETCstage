# All-Operator Benchmark Report

- run_id: `20260625_124115`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.77 | 0.807 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.19 | 2.24 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.607 | 0.638 |
| correlate/correlate | 8192 | passed | 0 | 13.9 | 26.7 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.79 | 13 |
| demod/fm_demod | 1048576 | passed | 0 | 28.6 | 36.6 |
| estimation/kalman_filter | 512 | passed | 0 | 1.21 | 2.46 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 5.31 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.637 | 0.861 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 9.85 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.84 | 4.33 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.72 | 1.84 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 11.9 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.56 | 3.02 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.94 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 7.58 | 10.1 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 22.8 | 23.5 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.5 | 59.5 |
| filtering/resample | 32768 | passed | 3.86e-05 | 5.04 | 6.14 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 15.9 | 18.1 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.834 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.68 | 6.29 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 182 | 189 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.8 | 40 |
| radartools/ambgfun | 8192 | passed | 0 | 48.1 | 48.2 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.26 | 4.81 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00281 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 56.1 | 59.5 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.8 | 68.2 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.84 | 1.97 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.64 | 12.7 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 68.9 | 69.3 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.74 | 7.42 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.3 | 17 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28 | 30.1 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 62.4 | 66.9 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.6 | 73.8 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36 | 43.4 |
| waveforms/square | 1048576 | passed | 0 | 47.7 | 58.4 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 22.9 | 138 |
| wavelets/cwt | 32768 | passed | 0 | 216 | 224 |
| wavelets/morlet | 1048576 | passed | 0 | 1.59 | 1.6 |
| wavelets/morlet2 | 1048576 | passed | 0 | 3.47 | 3.5 |
| wavelets/qmf | 1048576 | passed | 0 | 19 | 26.8 |
| wavelets/ricker | 1048576 | passed | 0 | 0.4 | 0.4 |
| windows/chebwin | 1536 | passed | 0 | 2.27 | 8.63 |
| windows/general_cosine | 1048576 | passed | 0 | 3.96 | 4.03 |
| windows/general_gaussian | 1048576 | passed | 0 | 5.96 | 6.05 |
| windows/hamming | 1048576 | passed | 0 | 1.39 | 1.42 |
| windows/kaiser | 1048576 | passed | 0 | 252 | 285 |
| windows/parzen | 1048576 | passed | 0 | 0.42 | 0.426 |
| windows/taylor | 1048576 | passed | 0 | 1.59 | 1.61 |
| windows/triang | 1048576 | passed | 0 | 0.0843 | 0.0842 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.637 | 0.861 |
| filtering/channelize_poly | 5.7e-05 | 9.85 | 11.7 |
| filtering/resample | 3.86e-05 | 5.04 | 6.14 |
| spectral/vectorstrength | 3.6e-05 | 28 | 30.1 |
| filtering/hilbert2 | 1.71e-05 | 22.8 | 23.5 |
| filter_design/firwin | 1.09e-05 | 5.31 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 68.9 | 69.3 |
| spectral/spectrogram | 7.01e-06 | 6.74 | 7.42 |
| filtering/detrend | 4.59e-06 | 0.72 | 1.84 |
| waveforms/chirp | 3.92e-06 | 62.4 | 66.9 |
| spectral/istft | 3.43e-06 | 3.64 | 12.7 |
| filtering/hilbert | 1.97e-06 | 7.58 | 10.1 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00281 | 0 | 0 |
| windows/triang | 0.0843 | 0.0842 | 0 |
| wavelets/ricker | 0.4 | 0.4 | 0 |
| windows/parzen | 0.42 | 0.426 | 0 |
| bsplines/quadratic | 0.607 | 0.638 | 0 |
| filter_design/firwin2 | 0.637 | 0.861 | 7.58e-05 |
| filtering/detrend | 0.72 | 1.84 | 4.59e-06 |
| bsplines/cubic | 0.77 | 0.807 | 0 |
| filtering/sosfilt | 0.834 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.21 | 2.46 | 0 |
| windows/hamming | 1.39 | 1.42 | 0 |
| windows/taylor | 1.59 | 1.61 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00281 | 0 |
| windows/triang | 0.0842 | 0.0843 | 0 |
| wavelets/ricker | 0.4 | 0.4 | 0 |
| windows/parzen | 0.426 | 0.42 | 0 |
| bsplines/quadratic | 0.638 | 0.607 | 0 |
| bsplines/cubic | 0.807 | 0.77 | 0 |
| filter_design/firwin2 | 0.861 | 0.637 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.834 | 8.25e-07 |
| windows/hamming | 1.42 | 1.39 | 0 |
| wavelets/morlet | 1.6 | 1.59 | 0 |
| windows/taylor | 1.61 | 1.59 | 0 |
| filtering/detrend | 1.84 | 0.72 | 4.59e-06 |
