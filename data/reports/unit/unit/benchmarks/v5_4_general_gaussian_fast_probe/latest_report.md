# All-Operator Benchmark Report

- run_id: `20260625_143514`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.771 | 0.817 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.19 | 2.24 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.592 | 0.622 |
| correlate/correlate | 8192 | passed | 0 | 13.5 | 26.6 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.64 | 13.1 |
| demod/fm_demod | 1048576 | passed | 0 | 28.3 | 36.5 |
| estimation/kalman_filter | 512 | passed | 0 | 1.17 | 2.29 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 4.62 | 20.4 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.558 | 0.854 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.3 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 3.88 | 4.42 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.742 | 1.85 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 12.1 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.58 | 3.04 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.83 | 14.6 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 7.15 | 9 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 32.3 | 33 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.9 | 59.6 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.78 | 5.84 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.5 | 18.4 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.838 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.76 | 6.26 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 196 | 206 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 38.1 | 40.4 |
| radartools/ambgfun | 8192 | passed | 0 | 47.4 | 47.6 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.09 | 4.62 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.00259 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.5 | 57.5 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 31.1 | 67.4 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.84 | 1.96 |
| spectral/istft | 257 | passed | 3.43e-06 | 4.22 | 12.9 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.9 | 68.4 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.77 | 7.4 |
| spectral/stft | 32768 | passed | 1.69e-07 | 12.9 | 16.4 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 28.2 | 30.2 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63 | 67.2 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 66.1 | 73.1 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 36.8 | 42.9 |
| waveforms/square | 1048576 | passed | 0 | 42.7 | 53.3 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 21.3 | 120 |
| wavelets/cwt | 32768 | passed | 0 | 216 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 72.7 | 83.9 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.7 | 33.3 |
| wavelets/qmf | 1048576 | passed | 0 | 18.6 | 25.7 |
| wavelets/ricker | 1048576 | passed | 0 | 10.7 | 11.1 |
| windows/chebwin | 1536 | passed | 0 | 2.3 | 8.8 |
| windows/general_cosine | 1048576 | passed | 0 | 3.96 | 4.07 |
| windows/general_gaussian | 1048576 | passed | 0 | 171 | 232 |
| windows/hamming | 1048576 | passed | 0 | 34 | 46.4 |
| windows/kaiser | 1048576 | passed | 0 | 239 | 285 |
| windows/parzen | 1048576 | passed | 0 | 14.2 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 5.83 | 6.01 |
| windows/triang | 1048576 | passed | 0 | 14.1 | 21.5 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.558 | 0.854 |
| filtering/channelize_poly | 5.7e-05 | 10.3 | 11.7 |
| filtering/resample | 3.86e-05 | 4.78 | 5.84 |
| spectral/vectorstrength | 3.6e-05 | 28.2 | 30.2 |
| filtering/hilbert2 | 1.71e-05 | 32.3 | 33 |
| filter_design/firwin | 1.09e-05 | 4.62 | 20.4 |
| spectral/lombscargle | 8.72e-06 | 67.9 | 68.4 |
| spectral/spectrogram | 7.01e-06 | 6.77 | 7.4 |
| filtering/detrend | 4.59e-06 | 0.742 | 1.85 |
| waveforms/chirp | 3.92e-06 | 63 | 67.2 |
| spectral/istft | 3.43e-06 | 4.22 | 12.9 |
| filtering/hilbert | 1.97e-06 | 7.15 | 9 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.00259 | 0 | 0 |
| filter_design/firwin2 | 0.558 | 0.854 | 7.58e-05 |
| bsplines/quadratic | 0.592 | 0.622 | 0 |
| filtering/detrend | 0.742 | 1.85 | 4.59e-06 |
| bsplines/cubic | 0.771 | 0.817 | 0 |
| filtering/sosfilt | 0.838 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.17 | 2.29 | 0 |
| spectral/csd | 1.84 | 1.96 | 2.22e-07 |
| bsplines/gauss_spline | 2.19 | 2.24 | 0 |
| windows/chebwin | 2.3 | 8.8 | 0 |
| filtering/firfilter2 | 2.58 | 3.04 | 8.15e-07 |
| correlate/correlate2d | 2.64 | 13.1 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.00259 | 0 |
| bsplines/quadratic | 0.622 | 0.592 | 0 |
| bsplines/cubic | 0.817 | 0.771 | 0 |
| filter_design/firwin2 | 0.854 | 0.558 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.838 | 8.25e-07 |
| filtering/detrend | 1.85 | 0.742 | 4.59e-06 |
| spectral/csd | 1.96 | 1.84 | 2.22e-07 |
| bsplines/gauss_spline | 2.24 | 2.19 | 0 |
| estimation/kalman_filter | 2.29 | 1.17 | 0 |
| filtering/firfilter2 | 3.04 | 2.58 | 8.15e-07 |
| windows/general_cosine | 4.07 | 3.96 | 0 |
| filtering/decimate | 4.42 | 3.88 | 6.95e-07 |
