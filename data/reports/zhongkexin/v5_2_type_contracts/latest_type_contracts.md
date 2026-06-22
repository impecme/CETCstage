# V5.2-04 算子类型契约

- status: `passed`
- operators: `81`
- policies: `13`
- integer-enabled operators: `8`
- complex64 operators: `20`

| 算子 | 策略 | 输入类型 | 输出类型 | 当前类型 | 累加 | 整数规则 |
| --- | --- | --- | --- | --- | --- | --- |
| `waveforms/chirp` | `floating_generator_real_or_complex64` | - | float32,float16,complex64 | float32,complex64 | float32 | not_applicable |
| `waveforms/gausspulse` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `waveforms/sawtooth` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `waveforms/square` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `waveforms/unit_impulse` | `numeric_identity` | - | float32,float16,int32,int16,int8 | float32 | none | exact representable constants |
| `bsplines/cubic` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `bsplines/quadratic` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `bsplines/gauss_spline` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `windows/get_window` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/barthann` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/bartlett` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/blackman` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/blackmanharris` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/bohman` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/boxcar` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/chebwin` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/cosine` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/exponential` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/flattop` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/gaussian` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/general_cosine` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/general_gaussian` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/general_hamming` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/hamming` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/hann` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/kaiser` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/nuttall` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/parzen` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/taylor` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/triang` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `windows/tukey` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `filter_design/kaiser_beta` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `filter_design/kaiser_atten` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `filter_design/cmplx_sort` | `sort_real_or_complex` | float32,float16,complex64 | float32,float16,complex64,int32 | float32,complex64,int32 | float32 magnitude | not_applicable |
| `filter_design/firwin` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `filter_design/firwin2` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `filtering/wiener` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/firfilter` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/lfilter` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/firfilter_zi` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/lfilter_zi` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/firfilter2` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/filtfilt` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/sosfilt` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/hilbert` | `floating_real_to_complex64` | float32,float16 | complex64 | float32,complex64 | float32 | not_applicable |
| `filtering/hilbert2` | `floating_real_to_complex64` | float32,float16 | complex64 | float32,complex64 | float32 | not_applicable |
| `filtering/detrend` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/freq_shift` | `complex64_pipeline` | complex64 | complex64,float32 | complex64,float32 | float32 | not_applicable |
| `filtering/channelize_poly` | `complex64_pipeline` | complex64 | complex64,float32 | complex64,float32 | float32 | not_applicable |
| `filtering/decimate` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/resample` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/resample_poly` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `filtering/upfirdn` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `radartools/pulse_compression` | `complex64_pipeline` | complex64 | complex64,float32 | complex64,float32 | float32 | not_applicable |
| `radartools/pulse_doppler` | `complex64_pipeline` | complex64 | complex64,float32 | complex64,float32 | float32 | not_applicable |
| `radartools/ambgfun` | `complex64_pipeline` | complex64 | complex64,float32 | complex64,float32 | float32 | not_applicable |
| `radartools/cfar_alpha` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `radartools/ca_cfar` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `radartools/mvdr` | `complex64_pipeline` | complex64 | complex64,float32 | complex64,float32 | float32 | not_applicable |
| `spectral/lombscargle` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `spectral/periodogram` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `spectral/welch` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `spectral/csd` | `floating_real_to_real_or_complex64` | float32,float16 | float32,float16,complex64 | float32,complex64 | float32 | not_applicable |
| `spectral/spectrogram` | `floating_real_to_real_or_complex64` | float32,float16 | float32,float16,complex64 | float32,complex64 | float32 | not_applicable |
| `spectral/stft` | `floating_real_to_complex64` | float32,float16 | complex64 | float32,complex64 | float32 | not_applicable |
| `spectral/istft` | `complex64_to_real` | complex64 | float32 | complex64,float32 | float32 | not_applicable |
| `spectral/coherence` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `spectral/vectorstrength` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `wavelets/qmf` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `wavelets/morlet` | `floating_generator_complex64` | - | complex64 | complex64 | float32 | not_applicable |
| `wavelets/ricker` | `floating_generator_real` | - | float32,float16 | float32 | float32 | not_applicable |
| `wavelets/morlet2` | `floating_generator_complex64` | - | complex64 | complex64 | float32 | not_applicable |
| `wavelets/cwt` | `floating_real_to_complex64` | float32,float16 | complex64 | float32,complex64 | float32 | not_applicable |
| `correlate/correlate` | `numeric_correlate` | float32,float16,int32,int16,int8,complex64 | float32,float16,int32,int16,int8,complex64 | float32,complex64 | float32 for FP16; int64 for INT32; int32 for INT16/INT8 | widened accumulation then saturating cast to input type |
| `correlate/correlate2d` | `numeric_correlate` | float32,float16,int32,int16,int8,complex64 | float32,float16,int32,int16,int8,complex64 | float32,complex64 | float32 for FP16; int64 for INT32; int32 for INT16/INT8 | widened accumulation then saturating cast to input type |
| `correlate/correlation_lags` | `index_metadata` | int32 | int32 | int32 | int64 for length arithmetic | range-check before int32 output |
| `demod/fm_demod` | `complex64_to_real` | complex64 | float32 | complex64,float32 | float32 | not_applicable |
| `estimation/kalman_filter` | `floating_real` | float32,float16 | float32,float16 | float32 | float32 | not_applicable |
| `peak_finding/argrelextrema` | `numeric_to_indices` | float32,float16,int32,int16,int8 | int32 | float32,int32 | none | exact comparisons without conversion |
| `peak_finding/argrelmin` | `numeric_to_indices` | float32,float16,int32,int16,int8 | int32 | float32,int32 | none | exact comparisons without conversion |
| `peak_finding/argrelmax` | `numeric_to_indices` | float32,float16,int32,int16,int8 | int32 | float32,int32 | none | exact comparisons without conversion |
