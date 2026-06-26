# All-Operator Benchmark Report

- run_id: `20260625_162914`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.781 | 0.821 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.18 | 2.25 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.609 | 0.636 |
| correlate/correlate | 8192 | passed | 0 | 13.2 | 25.5 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.62 | 13.2 |
| demod/fm_demod | 1048576 | passed | 0 | 28.6 | 36.4 |
| estimation/kalman_filter | 512 | passed | 0 | 1.17 | 2.35 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.64 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.638 | 0.868 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.98 | 4.23 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.721 | 1.83 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.2 | 12.8 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.56 | 3.1 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 8.37 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.99 | 8.85 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 32.4 | 33.2 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.1 | 58.5 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.78 | 6.16 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16 | 18.1 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.799 | 1.31 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.68 | 6.26 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 225 | 235 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38 | 40.6 |
| radartools/ambgfun | 8192 | passed | 0 | 49.7 | 49.9 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.1 | 4.64 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00244 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.9 | 57.5 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 26.9 | 52.6 |
| spectral/csd | 32768 | passed | 8.11e-08 | 6.38 | 7.77 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.97 | 11.9 |
| spectral/lombscargle | 8192 | passed | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.75 | 7.49 |
| spectral/stft | 32768 | passed | 1.69e-07 | 12.9 | 16.6 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.3 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 60.1 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 68.4 | 74.7 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37.5 | 43.2 |
| waveforms/square | 1048576 | passed | 0 | 44.1 | 53.4 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 21 | 123 |
| wavelets/cwt | 32768 | passed | 0 | 216 | 224 |
| wavelets/morlet | 1048576 | passed | 0 | 72 | 83.7 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.6 | 32.9 |
| wavelets/qmf | 1048576 | passed | 0 | 19.4 | 26.9 |
| wavelets/ricker | 1048576 | passed | 0 | 10.8 | 11.2 |
| windows/chebwin | 1536 | passed | 0 | 2.3 | 8.89 |
| windows/general_cosine | 1048576 | passed | 0 | 52.1 | 60.5 |
| windows/general_gaussian | 1048576 | passed | 0 | 170 | 235 |
| windows/hamming | 1048576 | passed | 0 | 33.2 | 46.3 |
| windows/kaiser | 1048576 | passed | 0 | 194 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.5 | 20.1 |
| windows/taylor | 1048576 | passed | 0 | 61.2 | 68 |
| windows/triang | 1048576 | passed | 0 | 14.6 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.638 | 0.868 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 4.78 | 6.16 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.3 |
| filtering/hilbert2 | 1.71e-05 | 32.4 | 33.2 |
| filter_design/firwin | 1.09e-05 | 4.64 | 20.6 |
| spectral/lombscargle | 9.62e-06 | 172 | 175 |
| spectral/spectrogram | 7.01e-06 | 6.75 | 7.49 |
| filtering/detrend | 4.59e-06 | 0.721 | 1.83 |
| waveforms/chirp | 3.92e-06 | 60.1 | 67 |
| spectral/istft | 3.43e-06 | 3.97 | 11.9 |
| filtering/hilbert | 1.97e-06 | 6.99 | 8.85 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00244 | 0 | 0 |
| bsplines/quadratic | 0.609 | 0.636 | 0 |
| filter_design/firwin2 | 0.638 | 0.868 | 7.58e-05 |
| filtering/detrend | 0.721 | 1.83 | 4.59e-06 |
| bsplines/cubic | 0.781 | 0.821 | 0 |
| filtering/sosfilt | 0.799 | 1.31 | 8.25e-07 |
| estimation/kalman_filter | 1.17 | 2.35 | 0 |
| bsplines/gauss_spline | 2.18 | 2.25 | 0 |
| windows/chebwin | 2.3 | 8.89 | 0 |
| filtering/firfilter2 | 2.56 | 3.1 | 8.15e-07 |
| correlate/correlate2d | 2.62 | 13.2 | 0 |
| spectral/istft | 3.97 | 11.9 | 3.43e-06 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00244 | 0 |
| bsplines/quadratic | 0.636 | 0.609 | 0 |
| bsplines/cubic | 0.821 | 0.781 | 0 |
| filter_design/firwin2 | 0.868 | 0.638 | 7.58e-05 |
| filtering/sosfilt | 1.31 | 0.799 | 8.25e-07 |
| filtering/detrend | 1.83 | 0.721 | 4.59e-06 |
| bsplines/gauss_spline | 2.25 | 2.18 | 0 |
| estimation/kalman_filter | 2.35 | 1.17 | 0 |
| filtering/firfilter2 | 3.1 | 2.56 | 8.15e-07 |
| filtering/decimate | 4.23 | 3.98 | 6.95e-07 |
| radartools/ca_cfar | 4.64 | 4.1 | 0 |
| filtering/resample | 6.16 | 4.78 | 3.86e-05 |
