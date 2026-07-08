# V5.2-04 算子类型契约

- status: `passed`
- operators: `81`
- policies: `14`
- compatibility gaps: `0`
- real types: `float16,float32,int16,int32,int8`
- complex types: `complex64`
- forbidden types: `complex128,complex32,complex_int16,complex_int32,complex_int8,float64`
- native direct operators: `12`
- compatibility-converted operators: `69`
- upstream complex64 supported operators: `21`
- upstream complex64 planned public gaps: `8`

结论：81 个算子的目标输入/输出类型均有兼容路径；复数类型仅支持 `complex64`。 `current_types` 表示当前原生直达类型，`compatibility_types` 表示允许通过 FP32/complex64 中间计算、整数扩展累加或受控转换覆盖的兼容类型。

| 类型 | 需兼容转换的算子数 |
| --- | ---: |
| `complex64` | `0` |
| `float16` | `69` |
| `float32` | `0` |
| `int16` | `5` |
| `int32` | `2` |
| `int8` | `5` |

## 原 cuSignal complex64 对齐

下表列出原 cuSignal/SciPy 语义中涉及复数输出、复数输入或复数 dtype-preserving 的算子在本项目中的 complex64 对齐状态。已支持项进入公共算子契约；待公共化项是当前仍只有实数公共接口或任务级 helper 的后续兼容计划。

| 状态 | 类别 | 算子 |
| --- | --- | --- |
| supported | `complex_pipeline_or_dtype_preserving` | `correlate/correlate` |
| supported | `complex_pipeline_or_dtype_preserving` | `correlate/correlate2d` |
| supported | `complex_input_to_real_outputs` | `demod/fm_demod` |
| supported | `complex_pipeline_or_dtype_preserving` | `filter_design/cmplx_sort` |
| supported | `complex_pipeline_or_dtype_preserving` | `filtering/channelize_poly` |
| supported | `complex_pipeline_or_dtype_preserving` | `filtering/firfilter` |
| supported | `complex_pipeline_or_dtype_preserving` | `filtering/freq_shift` |
| supported | `real_to_complex_outputs` | `filtering/hilbert` |
| supported | `real_to_complex_outputs` | `filtering/hilbert2` |
| supported | `complex_pipeline_or_dtype_preserving` | `radartools/ambgfun` |
| supported | `complex_pipeline_or_dtype_preserving` | `radartools/mvdr` |
| supported | `complex_pipeline_or_dtype_preserving` | `radartools/pulse_compression` |
| supported | `complex_pipeline_or_dtype_preserving` | `radartools/pulse_doppler` |
| supported | `mode_selectable_complex_outputs` | `spectral/csd` |
| supported | `complex_input_to_real_outputs` | `spectral/istft` |
| supported | `mode_selectable_complex_outputs` | `spectral/spectrogram` |
| supported | `real_to_complex_outputs` | `spectral/stft` |
| supported | `complex_generators` | `waveforms/chirp` |
| supported | `real_to_complex_outputs` | `wavelets/cwt` |
| supported | `complex_generators` | `wavelets/morlet` |
| supported | `complex_generators` | `wavelets/morlet2` |
| planned_public_gap | `complex64_dtype_preserving_filtering` | `filtering/decimate` |
| planned_public_gap | `complex64_dtype_preserving_filtering` | `filtering/filtfilt` |
| planned_public_gap | `complex64_dtype_preserving_filtering` | `filtering/firfilter2` |
| planned_public_gap | `complex64_dtype_preserving_filtering` | `filtering/lfilter` |
| planned_public_gap | `complex64_dtype_preserving_filtering` | `filtering/resample` |
| planned_public_gap | `complex64_dtype_preserving_filtering` | `filtering/resample_poly` |
| planned_public_gap | `complex64_dtype_preserving_filtering` | `filtering/sosfilt` |
| planned_public_gap | `complex64_dtype_preserving_filtering` | `filtering/upfirdn` |

| 算子 | 策略 | 目标类型 | 当前原生类型 | 兼容类型 | 需转换类型 | 兼容方式 |
| --- | --- | --- | --- | --- | --- | --- |
| `waveforms/chirp` | `floating_generator_real_or_complex64` | complex64,float16,float32 | complex64,float32 | complex64,float16,float32 | float16 | real mode supports FP32/FP16-compatible output; complex mode remains complex64 |
| `waveforms/gausspulse` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `waveforms/sawtooth` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `waveforms/square` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `waveforms/unit_impulse` | `float32_generator_real` | float32 | float32 | float32 | - | current public API returns RealSignal/ZxGpuRealSignal and only accepts dtype=float32 |
| `bsplines/cubic` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `bsplines/quadratic` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `bsplines/gauss_spline` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `windows/get_window` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/barthann` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/bartlett` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/blackman` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/blackmanharris` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/bohman` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/boxcar` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/chebwin` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/cosine` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/exponential` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/flattop` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/gaussian` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/general_cosine` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/general_gaussian` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/general_hamming` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/hamming` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/hann` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/kaiser` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/nuttall` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/parzen` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/taylor` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/triang` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `windows/tukey` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `filter_design/kaiser_beta` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `filter_design/kaiser_atten` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `filter_design/cmplx_sort` | `sort_real_or_complex` | complex64,float16,float32,int32 | complex64,float32,int32 | complex64,float16,float32,int32 | float16 | FP16-compatible values sort through FP32 magnitude; complex values remain complex64 and indices are int32 |
| `filter_design/firwin` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `filter_design/firwin2` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `filtering/wiener` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/firfilter` | `floating_real_or_complex64` | complex64,float16,float32 | complex64,float32 | complex64,float16,float32 | float16 | real input preserves floating dtype through FP32-compatible accumulation; complex64 input remains complex64 |
| `filtering/lfilter` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/firfilter_zi` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/lfilter_zi` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/firfilter2` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/filtfilt` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/sosfilt` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/hilbert` | `floating_real_to_complex64` | complex64,float16,float32 | complex64,float32 | complex64,float16,float32 | float16 | FP16-compatible real input is widened to FP32 before complex64 output |
| `filtering/hilbert2` | `floating_real_to_complex64` | complex64,float16,float32 | complex64,float32 | complex64,float16,float32 | float16 | FP16-compatible real input is widened to FP32 before complex64 output |
| `filtering/detrend` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/freq_shift` | `complex64_pipeline` | complex64,float32 | complex64,float32 | complex64,float32 | - | native complex64 pipeline with FP32 real diagnostics |
| `filtering/channelize_poly` | `complex64_pipeline` | complex64,float32 | complex64,float32 | complex64,float32 | - | native complex64 pipeline with FP32 real diagnostics |
| `filtering/decimate` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/resample` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/resample_poly` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `filtering/upfirdn` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `radartools/pulse_compression` | `complex64_pipeline` | complex64,float32 | complex64,float32 | complex64,float32 | - | native complex64 pipeline with FP32 real diagnostics |
| `radartools/pulse_doppler` | `complex64_pipeline` | complex64,float32 | complex64,float32 | complex64,float32 | - | native complex64 pipeline with FP32 real diagnostics |
| `radartools/ambgfun` | `complex64_pipeline` | complex64,float32 | complex64,float32 | complex64,float32 | - | native complex64 pipeline with FP32 real diagnostics |
| `radartools/cfar_alpha` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `radartools/ca_cfar` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `radartools/mvdr` | `complex64_pipeline` | complex64,float32 | complex64,float32 | complex64,float32 | - | native complex64 pipeline with FP32 real diagnostics |
| `spectral/lombscargle` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `spectral/periodogram` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `spectral/welch` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `spectral/csd` | `floating_real_to_real_or_complex64` | complex64,float16,float32 | complex64,float32 | complex64,float16,float32 | float16 | real output preserves FP32/FP16-compatible dtype; complex output remains complex64 |
| `spectral/spectrogram` | `floating_real_to_real_or_complex64` | complex64,float16,float32 | complex64,float32 | complex64,float16,float32 | float16 | real output preserves FP32/FP16-compatible dtype; complex output remains complex64 |
| `spectral/stft` | `floating_real_to_complex64` | complex64,float16,float32 | complex64,float32 | complex64,float16,float32 | float16 | FP16-compatible real input is widened to FP32 before complex64 output |
| `spectral/istft` | `complex64_to_real` | complex64,float32 | complex64,float32 | complex64,float32 | - | native complex64 input to FP32 real output |
| `spectral/coherence` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `spectral/vectorstrength` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `wavelets/qmf` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `wavelets/morlet` | `floating_generator_complex64` | complex64 | complex64 | complex64 | - | native complex64 only |
| `wavelets/ricker` | `floating_generator_real` | float16,float32 | float32 | float16,float32 | float16 | dtype selects FP32 output or FP16-compatible output generated through FP32 math |
| `wavelets/morlet2` | `floating_generator_complex64` | complex64 | complex64 | complex64 | - | native complex64 only |
| `wavelets/cwt` | `floating_real_to_complex64` | complex64,float16,float32 | complex64,float32 | complex64,float16,float32 | float16 | FP16-compatible real input is widened to FP32 before complex64 output |
| `correlate/correlate` | `numeric_correlate` | complex64,float16,float32,int16,int32,int8 | complex64,float32 | complex64,float16,float32,int16,int32,int8 | float16,int16,int32,int8 | numeric inputs preserve dtype; FP16 widens for accumulation and integers use widened accumulation before output conversion |
| `correlate/correlate2d` | `numeric_correlate` | complex64,float16,float32,int16,int32,int8 | complex64,float32 | complex64,float16,float32,int16,int32,int8 | float16,int16,int32,int8 | numeric inputs preserve dtype; FP16 widens for accumulation and integers use widened accumulation before output conversion |
| `correlate/correlation_lags` | `index_metadata` | int32 | int32 | int32 | - | native int32 metadata path |
| `demod/fm_demod` | `complex64_to_real` | complex64,float32 | complex64,float32 | complex64,float32 | - | native complex64 input to FP32 real output |
| `estimation/kalman_filter` | `floating_real` | float16,float32 | float32 | float16,float32 | float16 | accept compatible FP16 inputs/outputs with FP32 intermediate accumulation |
| `peak_finding/argrelextrema` | `numeric_to_indices` | float16,float32,int16,int32,int8 | float32,int32 | float16,float32,int16,int32,int8 | float16,int16,int8 | all supported real/integer inputs compare in their value domain and return int32 indices |
| `peak_finding/argrelmin` | `numeric_to_indices` | float16,float32,int16,int32,int8 | float32,int32 | float16,float32,int16,int32,int8 | float16,int16,int8 | all supported real/integer inputs compare in their value domain and return int32 indices |
| `peak_finding/argrelmax` | `numeric_to_indices` | float16,float32,int16,int32,int8 | float32,int32 | float16,float32,int16,int32,int8 | float16,int16,int8 | all supported real/integer inputs compare in their value domain and return int32 indices |
