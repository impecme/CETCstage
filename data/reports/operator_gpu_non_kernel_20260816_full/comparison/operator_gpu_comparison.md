# Frozen GPU baseline vs optimized operator report

本报告只运行优化版本；baseline CSV 未重新运行、未修改。CPU reference 取 frozen baseline 的 saved_cpu_median_ms。

- baseline: `/home/usr_04/CETC/operator_gpu_baseline_75a700d_protocol/gpu_baseline.csv`
- baseline commit: `75a700da93eb7ebe6133392273493ef90cf54d82`
- optimized report: `data/reports/operator_gpu_non_kernel_20260816_full/units/benchmarks/operator_scales.csv`
- optimized source: `working-tree+non-kernel-full-cpu-cache`
- protocol: `warmup=5, repeat=30, device=ZQ500`
- rows: `486`

## Summary

| 指标 | 结果 |
| --- | ---: |
| POSITIVE workload rows | 421 |
| NO_GAIN workload rows | 0 |
| REGRESSION workload rows | 65 |
| UNAVAILABLE workload rows | 0 |
| CORRECTNESS_FAIL rows | 0 |
| baseline CPU→GPU E2E speedup median | 0.663x |
| optimized CPU→GPU E2E speedup median | 1.355x |
| GPU E2E before/after ratio of medians | 1.363x |
| GPU E2E before/after row median | 1.337x |
| valid GPU kernel before/after rows | 456 |
| GPU kernel before/after row median | 1.485x |

`optimized_cpu_to_gpu_e2e_speedup > baseline_cpu_to_gpu_e2e_speedup` 才记为 POSITIVE；kernel 缺失时只记 N/A，不用 E2E 替代。

## Per-operator summary

| 算子 | rows | positive | no gain | regression | unavailable | correctness fail | baseline CPU→GPU | optimized CPU→GPU | GPU E2E before/after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| bsplines/cubic | 6 | 6 | 0 | 0 | 0 | 0 | 0.194x | 0.426x | 1.925x |
| bsplines/gauss_spline | 6 | 6 | 0 | 0 | 0 | 0 | 0.727x | 1.707x | 2.006x |
| bsplines/quadratic | 6 | 6 | 0 | 0 | 0 | 0 | 0.148x | 0.339x | 1.930x |
| correlate/correlate | 6 | 6 | 0 | 0 | 0 | 0 | 10.676x | 26.798x | 2.499x |
| correlate/correlate2d | 6 | 6 | 0 | 0 | 0 | 0 | 2.265x | 2.960x | 1.315x |
| correlate/correlation_lags | 6 | 5 | 0 | 1 | 0 | 0 | 0.004x | 0.005x | 1.053x |
| demod/fm_demod | 6 | 3 | 0 | 3 | 0 | 0 | 1.767x | 1.792x | 0.995x |
| estimation/kalman_filter | 6 | 4 | 0 | 2 | 0 | 0 | 3.001x | 3.250x | 1.020x |
| filter_design/cmplx_sort | 6 | 0 | 0 | 6 | 0 | 0 | 439.940x | 0.875x | 0.002x |
| filter_design/firwin | 6 | 4 | 0 | 2 | 0 | 0 | 0.912x | 0.965x | 1.031x |
| filter_design/firwin2 | 6 | 6 | 0 | 0 | 0 | 0 | 0.771x | 1.598x | 1.764x |
| filter_design/kaiser_atten | 6 | 4 | 0 | 2 | 0 | 0 | 0.000x | 0.000x | 1.013x |
| filter_design/kaiser_beta | 6 | 2 | 0 | 4 | 0 | 0 | 0.001x | 0.000x | 0.976x |
| filtering/channelize_poly | 6 | 6 | 0 | 0 | 0 | 0 | 5.779x | 14.758x | 2.597x |
| filtering/decimate | 6 | 6 | 0 | 0 | 0 | 0 | 8.245x | 8.437x | 1.028x |
| filtering/detrend | 6 | 5 | 0 | 1 | 0 | 0 | 0.857x | 1.173x | 1.261x |
| filtering/filtfilt | 6 | 6 | 0 | 0 | 0 | 0 | 0.001x | 1.902x | 2605.106x |
| filtering/firfilter | 6 | 4 | 0 | 2 | 0 | 0 | 1.625x | 1.888x | 1.105x |
| filtering/firfilter2 | 6 | 6 | 0 | 0 | 0 | 0 | 2.699x | 3.349x | 1.191x |
| filtering/firfilter_zi | 6 | 1 | 0 | 5 | 0 | 0 | 0.038x | 0.032x | 0.849x |
| filtering/freq_shift | 6 | 5 | 0 | 1 | 0 | 0 | 1.503x | 1.762x | 1.158x |
| filtering/hilbert | 6 | 6 | 0 | 0 | 0 | 0 | 10.646x | 13.418x | 1.320x |
| filtering/hilbert2 | 6 | 5 | 0 | 1 | 0 | 0 | 5.992x | 8.202x | 1.200x |
| filtering/lfilter | 6 | 6 | 0 | 0 | 0 | 0 | 0.001x | 1.422x | 2029.952x |
| filtering/lfilter_zi | 6 | 3 | 0 | 3 | 0 | 0 | 0.392x | 0.406x | 1.000x |
| filtering/resample | 6 | 6 | 0 | 0 | 0 | 0 | 16.951x | 21.266x | 1.267x |
| filtering/resample_poly | 6 | 6 | 0 | 0 | 0 | 0 | 14.295x | 18.639x | 1.220x |
| filtering/sosfilt | 6 | 6 | 0 | 0 | 0 | 0 | 1.109x | 1.376x | 1.268x |
| filtering/upfirdn | 6 | 6 | 0 | 0 | 0 | 0 | 1.906x | 2.639x | 1.346x |
| filtering/wiener | 6 | 6 | 0 | 0 | 0 | 0 | 3.008x | 59.471x | 19.569x |
| peak_finding/argrelextrema | 6 | 5 | 0 | 1 | 0 | 0 | 5.659x | 7.800x | 1.228x |
| peak_finding/argrelmax | 6 | 4 | 0 | 2 | 0 | 0 | 5.687x | 8.065x | 1.206x |
| peak_finding/argrelmin | 6 | 5 | 0 | 1 | 0 | 0 | 5.760x | 7.893x | 1.293x |
| radartools/ambgfun | 6 | 5 | 0 | 1 | 0 | 0 | 4.135x | 5.804x | 1.350x |
| radartools/ca_cfar | 6 | 5 | 0 | 1 | 0 | 0 | 0.551x | 0.716x | 1.356x |
| radartools/cfar_alpha | 6 | 1 | 0 | 5 | 0 | 0 | 0.001x | 0.001x | 0.933x |
| radartools/mvdr | 6 | 6 | 0 | 0 | 0 | 0 | 0.426x | 2.135x | 4.994x |
| radartools/pulse_compression | 6 | 6 | 0 | 0 | 0 | 0 | 3.433x | 5.590x | 1.582x |
| radartools/pulse_doppler | 6 | 5 | 0 | 1 | 0 | 0 | 0.916x | 1.263x | 1.366x |
| spectral/coherence | 6 | 6 | 0 | 0 | 0 | 0 | 1.792x | 27.680x | 15.399x |
| spectral/csd | 6 | 6 | 0 | 0 | 0 | 0 | 1.990x | 7.785x | 3.966x |
| spectral/istft | 6 | 6 | 0 | 0 | 0 | 0 | 3.138x | 3.764x | 1.176x |
| spectral/lombscargle | 6 | 6 | 0 | 0 | 0 | 0 | 63.979x | 138.869x | 2.128x |
| spectral/periodogram | 6 | 6 | 0 | 0 | 0 | 0 | 0.003x | 6.450x | 3084.732x |
| spectral/spectrogram | 6 | 6 | 0 | 0 | 0 | 0 | 4.857x | 13.086x | 2.709x |
| spectral/stft | 6 | 6 | 0 | 0 | 0 | 0 | 4.493x | 5.810x | 1.347x |
| spectral/vectorstrength | 6 | 6 | 0 | 0 | 0 | 0 | 45.877x | 64.831x | 1.583x |
| spectral/welch | 6 | 6 | 0 | 0 | 0 | 0 | 1.590x | 4.249x | 2.699x |
| waveforms/chirp | 6 | 2 | 0 | 4 | 0 | 0 | 1.907x | 1.804x | 0.916x |
| waveforms/gausspulse | 6 | 4 | 0 | 2 | 0 | 0 | 1.079x | 1.038x | 1.022x |
| waveforms/sawtooth | 6 | 4 | 0 | 2 | 0 | 0 | 0.921x | 0.881x | 1.019x |
| waveforms/square | 6 | 4 | 0 | 2 | 0 | 0 | 0.887x | 0.893x | 1.036x |
| waveforms/unit_impulse | 6 | 3 | 0 | 3 | 0 | 0 | 0.379x | 0.384x | 0.991x |
| wavelets/cwt | 6 | 6 | 0 | 0 | 0 | 0 | 42.443x | 57.027x | 1.344x |
| wavelets/morlet | 6 | 6 | 0 | 0 | 0 | 0 | 0.950x | 3.250x | 3.434x |
| wavelets/morlet2 | 6 | 6 | 0 | 0 | 0 | 0 | 1.822x | 5.496x | 3.214x |
| wavelets/qmf | 6 | 6 | 0 | 0 | 0 | 0 | 0.392x | 0.703x | 1.980x |
| wavelets/ricker | 6 | 6 | 0 | 0 | 0 | 0 | 0.399x | 7.059x | 17.758x |
| windows/barthann | 6 | 5 | 0 | 1 | 0 | 0 | 0.087x | 0.093x | 1.171x |
| windows/bartlett | 6 | 6 | 0 | 0 | 0 | 0 | 0.015x | 0.016x | 1.152x |
| windows/blackman | 6 | 6 | 0 | 0 | 0 | 0 | 0.114x | 0.160x | 1.516x |
| windows/blackmanharris | 6 | 6 | 0 | 0 | 0 | 0 | 0.157x | 0.221x | 1.405x |
| windows/bohman | 6 | 5 | 0 | 1 | 0 | 0 | 0.163x | 0.165x | 1.109x |
| windows/boxcar | 6 | 6 | 0 | 0 | 0 | 0 | 0.002x | 0.002x | 1.101x |
| windows/chebwin | 6 | 4 | 0 | 2 | 0 | 0 | 1.284x | 1.168x | 1.066x |
| windows/cosine | 6 | 6 | 0 | 0 | 0 | 0 | 0.056x | 0.166x | 3.015x |
| windows/exponential | 6 | 5 | 0 | 1 | 0 | 0 | 0.058x | 0.064x | 1.129x |
| windows/flattop | 6 | 6 | 0 | 0 | 0 | 0 | 0.194x | 0.282x | 1.562x |
| windows/gaussian | 6 | 6 | 0 | 0 | 0 | 0 | 0.065x | 0.075x | 1.211x |
| windows/general_cosine | 6 | 6 | 0 | 0 | 0 | 0 | 0.184x | 0.274x | 1.537x |
| windows/general_gaussian | 6 | 6 | 0 | 0 | 0 | 0 | 0.180x | 0.228x | 1.231x |
| windows/general_hamming | 6 | 6 | 0 | 0 | 0 | 0 | 0.063x | 0.096x | 1.584x |
| windows/get_window | 6 | 6 | 0 | 0 | 0 | 0 | 0.066x | 0.101x | 1.518x |
| windows/hamming | 6 | 6 | 0 | 0 | 0 | 0 | 0.069x | 0.097x | 1.548x |
| windows/hann | 6 | 6 | 0 | 0 | 0 | 0 | 0.063x | 0.098x | 1.604x |
| windows/kaiser | 6 | 4 | 0 | 2 | 0 | 0 | 1.180x | 1.172x | 1.050x |
| windows/nuttall | 6 | 6 | 0 | 0 | 0 | 0 | 0.153x | 0.220x | 1.628x |
| windows/parzen | 6 | 6 | 0 | 0 | 0 | 0 | 0.018x | 0.030x | 1.312x |
| windows/taylor | 6 | 6 | 0 | 0 | 0 | 0 | 0.179x | 0.432x | 2.416x |
| windows/triang | 6 | 6 | 0 | 0 | 0 | 0 | 0.013x | 0.025x | 1.999x |
| windows/tukey | 6 | 6 | 0 | 0 | 0 | 0 | 0.048x | 0.062x | 1.277x |

## Acceptance boundary

- 不把历史 baseline 重新测量；只对优化版本执行 `all81 × L1-L6`。
- 优化版本必须保持完整 workload key、输入布局、dtype、warmup/repeat 和正确性契约。
- 误差字段只来自优化版本 GPU 与保存 CPU reference 的比较。
- POSITIVE/NO_GAIN/REGRESSION 是逐 workload 结果；不能用总体中位数掩盖单算子回退。
