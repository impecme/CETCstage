# All-Operator Benchmark Report

- run_id: `20260625_134751`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.78 | 0.814 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.19 | 2.24 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.599 | 0.621 |
| correlate/correlate | 8192 | passed | 0 | 13.4 | 26.7 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.68 | 13.2 |
| demod/fm_demod | 1048576 | passed | 0 | 28.3 | 36.5 |
| estimation/kalman_filter | 512 | passed | 0 | 1.24 | 2.58 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.74 | 20.9 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.647 | 0.862 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.4 | 11.8 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4.12 | 4.6 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.731 | 1.82 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 11.9 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.56 | 3.03 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.98 | 14.7 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 7.16 | 9.15 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 30.6 | 31.1 |
| filtering/lfilter_zi | 512 | passed | 0 | 33.1 | 56.3 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.89 | 6.17 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.7 | 19 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.816 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 3.77 | 6.3 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 180 | 190 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.4 | 40 |
| radartools/ambgfun | 8192 | passed | 0 | 48.6 | 48.7 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.1 | 4.63 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00256 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 56.5 | 58.3 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 30.4 | 59.8 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.83 | 1.95 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.69 | 12.3 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.7 | 68.3 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.8 | 7.49 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.2 | 16.7 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63.4 | 67 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 69.3 | 76.9 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.7 | 43.4 |
| waveforms/square | 1048576 | passed | 0 | 43.9 | 53.3 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 20.9 | 120 |
| wavelets/cwt | 32768 | passed | 0 | 212 | 221 |
| wavelets/morlet | 1048576 | passed | 0 | 1.6 | 1.61 |
| wavelets/morlet2 | 1048576 | passed | 0 | 3.34 | 3.34 |
| wavelets/qmf | 1048576 | passed | 0 | 18.5 | 26.1 |
| wavelets/ricker | 1048576 | passed | 0 | 13.8 | 14.5 |
| windows/chebwin | 1536 | passed | 0 | 2.18 | 8.74 |
| windows/general_cosine | 1048576 | passed | 0 | 3.94 | 4.04 |
| windows/general_gaussian | 1048576 | passed | 0 | 5.94 | 6.11 |
| windows/hamming | 1048576 | passed | 0 | 1.4 | 1.43 |
| windows/kaiser | 1048576 | passed | 0 | 253 | 285 |
| windows/parzen | 1048576 | passed | 0 | 0.415 | 0.423 |
| windows/taylor | 1048576 | passed | 0 | 1.59 | 1.6 |
| windows/triang | 1048576 | passed | 0 | 0.0843 | 0.0847 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.647 | 0.862 |
| filtering/channelize_poly | 5.7e-05 | 10.4 | 11.8 |
| filtering/resample | 3.86e-05 | 4.89 | 6.17 |
| spectral/vectorstrength | 3.6e-05 | 28 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 30.6 | 31.1 |
| filter_design/firwin | 1.09e-05 | 4.74 | 20.9 |
| spectral/lombscargle | 8.72e-06 | 67.7 | 68.3 |
| spectral/spectrogram | 7.01e-06 | 6.8 | 7.49 |
| filtering/detrend | 4.59e-06 | 0.731 | 1.82 |
| waveforms/chirp | 3.92e-06 | 63.4 | 67 |
| spectral/istft | 3.43e-06 | 3.69 | 12.3 |
| filtering/hilbert | 1.97e-06 | 7.16 | 9.15 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00256 | 0 | 0 |
| windows/triang | 0.0843 | 0.0847 | 0 |
| windows/parzen | 0.415 | 0.423 | 0 |
| bsplines/quadratic | 0.599 | 0.621 | 0 |
| filter_design/firwin2 | 0.647 | 0.862 | 7.58e-05 |
| filtering/detrend | 0.731 | 1.82 | 4.59e-06 |
| bsplines/cubic | 0.78 | 0.814 | 0 |
| filtering/sosfilt | 0.816 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.24 | 2.58 | 0 |
| windows/hamming | 1.4 | 1.43 | 0 |
| windows/taylor | 1.59 | 1.6 | 0 |
| wavelets/morlet | 1.6 | 1.61 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00256 | 0 |
| windows/triang | 0.0847 | 0.0843 | 0 |
| windows/parzen | 0.423 | 0.415 | 0 |
| bsplines/quadratic | 0.621 | 0.599 | 0 |
| bsplines/cubic | 0.814 | 0.78 | 0 |
| filter_design/firwin2 | 0.862 | 0.647 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.816 | 8.25e-07 |
| windows/hamming | 1.43 | 1.4 | 0 |
| windows/taylor | 1.6 | 1.59 | 0 |
| wavelets/morlet | 1.61 | 1.6 | 0 |
| filtering/detrend | 1.82 | 0.731 | 4.59e-06 |
| spectral/csd | 1.95 | 1.83 | 2.22e-07 |
