# All-Operator Benchmark Report

- run_id: `20260625_140249`
- scale_profile: `default`
- rows: `53`
- operators: `53`
- passed_rows: `53`
- status: passed=53
- data_csv: `latest_all_ops_scale_benchmark.csv`

## Largest-Scale Operator Summary

| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---|---:|---:|---:|
| bsplines/cubic | 1048576 | passed | 0 | 0.778 | 0.817 |
| bsplines/gauss_spline | 1048576 | passed | 0 | 2.18 | 2.24 |
| bsplines/quadratic | 1048576 | passed | 0 | 0.6 | 0.63 |
| correlate/correlate | 8192 | passed | 0 | 13.9 | 26.8 |
| correlate/correlate2d | 1048576 | passed | 0 | 2.6 | 12.9 |
| demod/fm_demod | 1048576 | passed | 0 | 28.1 | 36.6 |
| estimation/kalman_filter | 512 | passed | 0 | 1.21 | 2.43 |
| filter_design/firwin | 4097 | passed | 1.09e-05 | 5 | 20.6 |
| filter_design/firwin2 | 1025 | passed | 7.58e-05 | 0.671 | 0.879 |
| filtering/channelize_poly | 32768 | passed | 5.7e-05 | 10.4 | 11.7 |
| filtering/decimate | 32768 | passed | 6.95e-07 | 4 | 4.4 |
| filtering/detrend | 32768 | passed | 4.59e-06 | 0.72 | 1.85 |
| filtering/firfilter | 1048576 | passed | 9.04e-07 | 11.9 | 12.6 |
| filtering/firfilter2 | 32768 | passed | 8.15e-07 | 2.6 | 3.09 |
| filtering/freq_shift | 32768 | passed | 1.98e-07 | 7.79 | 14.8 |
| filtering/hilbert | 32768 | passed | 1.97e-06 | 6.54 | 7.93 |
| filtering/hilbert2 | 1048576 | passed | 1.71e-05 | 23.5 | 24 |
| filtering/lfilter_zi | 512 | passed | 0 | 32.8 | 59.6 |
| filtering/resample | 32768 | passed | 3.86e-05 | 4.72 | 5.92 |
| filtering/resample_poly | 32768 | passed | 5.4e-07 | 16.7 | 18.5 |
| filtering/sosfilt | 32768 | passed | 8.25e-07 | 0.814 | 1.3 |
| filtering/upfirdn | 32768 | passed | 2.87e-07 | 4.56 | 6.23 |
| filtering/wiener | 1048576 | passed | 9.76e-07 | 198 | 208 |
| peak_finding/argrelextrema | 1048576 | passed | 0 | 37.8 | 40.3 |
| radartools/ambgfun | 8192 | passed | 0 | 48.3 | 48.4 |
| radartools/ca_cfar | 1048576 | passed | 0 | 4.81 | 4.86 |
| radartools/cfar_alpha | 512 | passed | 0 | 0.0025 | 0 |
| radartools/pulse_compression | 1048576 | passed | 0 | 54.1 | 57.2 |
| radartools/pulse_doppler | 1048576 | passed | 0 | 29.9 | 66.6 |
| spectral/csd | 32768 | passed | 2.22e-07 | 1.83 | 1.95 |
| spectral/istft | 257 | passed | 3.43e-06 | 3.53 | 12.3 |
| spectral/lombscargle | 8192 | passed | 8.72e-06 | 67.6 | 68.2 |
| spectral/spectrogram | 32768 | passed | 7.01e-06 | 6.69 | 7.37 |
| spectral/stft | 32768 | passed | 1.69e-07 | 13.1 | 16.6 |
| spectral/vectorstrength | 32768 | passed | 3.6e-05 | 29.5 | 33.1 |
| waveforms/chirp | 1048576 | passed | 3.92e-06 | 63 | 66.8 |
| waveforms/gausspulse | 1048576 | passed | 3.85e-07 | 67.2 | 73.5 |
| waveforms/sawtooth | 1048576 | passed | 2.38e-07 | 37.3 | 43 |
| waveforms/square | 1048576 | passed | 0 | 43.5 | 53.3 |
| waveforms/unit_impulse | 1048576 | passed | 0 | 20.1 | 125 |
| wavelets/cwt | 32768 | passed | 0 | 216 | 225 |
| wavelets/morlet | 1048576 | passed | 0 | 73.1 | 83.7 |
| wavelets/morlet2 | 1048576 | passed | 0 | 31.5 | 33 |
| wavelets/qmf | 1048576 | passed | 0 | 19.3 | 26.8 |
| wavelets/ricker | 1048576 | passed | 0 | 14.1 | 14.7 |
| windows/chebwin | 1536 | passed | 0 | 2.18 | 8.79 |
| windows/general_cosine | 1048576 | passed | 0 | 3.95 | 4.05 |
| windows/general_gaussian | 1048576 | passed | 0 | 5.98 | 6.01 |
| windows/hamming | 1048576 | passed | 0 | 1.39 | 1.41 |
| windows/kaiser | 1048576 | passed | 0 | 193 | 219 |
| windows/parzen | 1048576 | passed | 0 | 14.6 | 20.2 |
| windows/taylor | 1048576 | passed | 0 | 1.6 | 1.61 |
| windows/triang | 1048576 | passed | 0 | 14.5 | 21.7 |

## Highest Mixed Error

| Operator | Mixed error | E2E speedup | Kernel speedup |
|---|---:|---:|---:|
| filter_design/firwin2 | 7.58e-05 | 0.671 | 0.879 |
| filtering/channelize_poly | 5.7e-05 | 10.4 | 11.7 |
| filtering/resample | 3.86e-05 | 4.72 | 5.92 |
| spectral/vectorstrength | 3.6e-05 | 29.5 | 33.1 |
| filtering/hilbert2 | 1.71e-05 | 23.5 | 24 |
| filter_design/firwin | 1.09e-05 | 5 | 20.6 |
| spectral/lombscargle | 8.72e-06 | 67.6 | 68.2 |
| spectral/spectrogram | 7.01e-06 | 6.69 | 7.37 |
| filtering/detrend | 4.59e-06 | 0.72 | 1.85 |
| waveforms/chirp | 3.92e-06 | 63 | 66.8 |
| spectral/istft | 3.43e-06 | 3.53 | 12.3 |
| filtering/hilbert | 1.97e-06 | 6.54 | 7.93 |

## Lowest E2E Speedup

| Operator | E2E speedup | Kernel speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0.0025 | 0 | 0 |
| bsplines/quadratic | 0.6 | 0.63 | 0 |
| filter_design/firwin2 | 0.671 | 0.879 | 7.58e-05 |
| filtering/detrend | 0.72 | 1.85 | 4.59e-06 |
| bsplines/cubic | 0.778 | 0.817 | 0 |
| filtering/sosfilt | 0.814 | 1.3 | 8.25e-07 |
| estimation/kalman_filter | 1.21 | 2.43 | 0 |
| windows/hamming | 1.39 | 1.41 | 0 |
| windows/taylor | 1.6 | 1.61 | 0 |
| spectral/csd | 1.83 | 1.95 | 2.22e-07 |
| windows/chebwin | 2.18 | 8.79 | 0 |
| bsplines/gauss_spline | 2.18 | 2.24 | 0 |

## Lowest Kernel Speedup

| Operator | Kernel speedup | E2E speedup | Mixed error |
|---|---:|---:|---:|
| radartools/cfar_alpha | 0 | 0.0025 | 0 |
| bsplines/quadratic | 0.63 | 0.6 | 0 |
| bsplines/cubic | 0.817 | 0.778 | 0 |
| filter_design/firwin2 | 0.879 | 0.671 | 7.58e-05 |
| filtering/sosfilt | 1.3 | 0.814 | 8.25e-07 |
| windows/hamming | 1.41 | 1.39 | 0 |
| windows/taylor | 1.61 | 1.6 | 0 |
| filtering/detrend | 1.85 | 0.72 | 4.59e-06 |
| spectral/csd | 1.95 | 1.83 | 2.22e-07 |
| bsplines/gauss_spline | 2.24 | 2.18 | 0 |
| estimation/kalman_filter | 2.43 | 1.21 | 0 |
| filtering/firfilter2 | 3.09 | 2.6 | 8.15e-07 |
