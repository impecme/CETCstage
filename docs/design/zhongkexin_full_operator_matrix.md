# 中科芯 V4.3 全量公开算子矩阵

## 文档定位

本文档用于 V4.3 全量公开算子迁移。它冻结当前公开模块、CUDA 实现、测试注册状态和中科芯容器验证入口。

V4.2 只覆盖 Task1/Task2 直接依赖算子；V4.3 扩展到 `scripts/test/run_all_tests.sh` 当前注册的全部公开算子测试。原注释候选项已确认具备测试源码、CMake target 和 CPU/CUDA API，现已纳入 active 验证范围。

## 当前注册概览

- active 测试条目：`81`
- 覆盖模块：`12`
- 原注释候选条目：`28`，已启用
- 统一入口：`scripts/platform/run_zhongkexin_stage3.sh`
- 目标报告：V4.3 脚本写入 `data/reports/zhongkexin/stage3/`
- 当前验证：Stage3 active 81 条 accuracy 已全部通过，模块级 `12/12`、算子级 `81/81`。

| 模块 | active 条目数 | CUDA 实现 | 测试支持库 | 依赖类型 | V4.2 覆盖情况 | V4.3 起始状态 |
| --- | ---: | --- | --- | --- | --- | --- |
| `waveforms` | 5 | `src/cuda/waveforms.cu` | `tests/unit/waveforms/waveform_test_support.cu` | runtime/math | 部分覆盖 | 5/5 已通过 |
| `bsplines` | 3 | `src/cuda/bsplines.cu` | `tests/unit/bsplines/bsplines_test_support.cu` | runtime/math | 部分覆盖 | 3/3 已通过 |
| `windows` | 23 | `src/cuda/windows.cu` | `tests/unit/windows/windows_test_support.cu` | runtime/math | 部分覆盖 | 23/23 已通过 |
| `filter_design` | 5 | `src/cuda/filter_design.cu` | `tests/unit/filter_design/filter_design_test_support.cu` | runtime/math | 已覆盖 active 条目 | 5/5 已通过 |
| `filtering` | 17 | `src/cuda/filtering.cu` | `tests/unit/filtering/filtering_test_support.cu` | FFT-heavy/mixed | 部分覆盖 | 17/17 已通过 |
| `radartools` | 6 | `src/cuda/radartools.cu` | `tests/unit/radartools/radartools_test_support.cu` | FFT-heavy/mixed | 已覆盖 active 条目 | 6/6 已通过 |
| `spectral` | 9 | `src/cuda/spectral.cu` | `tests/unit/spectral/spectral_test_support.cu` | FFT-heavy | 部分覆盖 | 9/9 已通过 |
| `wavelets` | 5 | `src/cuda/wavelets.cu` | `tests/unit/wavelets/wavelets_test_support.cu` | runtime/math | 部分覆盖 | 5/5 已通过 |
| `correlate` | 3 | `src/cuda/correlate.cu` | `tests/unit/correlate/correlate_test_support.cu` | FFT-heavy/mixed | 已覆盖 active 条目 | 3/3 已通过 |
| `demod` | 1 | `src/cuda/demod.cu` | `tests/unit/demod/demod_test_support.cu` | runtime/math | 已覆盖 active 条目 | 1/1 已通过 |
| `estimation` | 1 | `src/cuda/estimation.cu` | `tests/unit/estimation/estimation_test_support.cu` | BLAS/SOLVER/mixed | 已覆盖 active 条目 | 1/1 已通过 |
| `peak_finding` | 3 | `src/cuda/peak_finding.cu` | `tests/unit/peak_finding/peak_finding_test_support.cu` | runtime/math | 已覆盖 active 条目 | 3/3 已通过 |

## Active 条目清单

| 模块 | 算子 |
| --- | --- |
| `waveforms` | `chirp`, `gausspulse`, `sawtooth`, `square`, `unit_impulse` |
| `bsplines` | `cubic`, `quadratic`, `gauss_spline` |
| `windows` | `get_window`, `barthann`, `bartlett`, `blackman`, `blackmanharris`, `bohman`, `boxcar`, `chebwin`, `cosine`, `exponential`, `flattop`, `gaussian`, `general_cosine`, `general_gaussian`, `general_hamming`, `hamming`, `hann`, `kaiser`, `nuttall`, `parzen`, `taylor`, `triang`, `tukey` |
| `filter_design` | `kaiser_beta`, `kaiser_atten`, `cmplx_sort`, `firwin`, `firwin2` |
| `filtering` | `wiener`, `firfilter`, `lfilter`, `firfilter_zi`, `lfilter_zi`, `firfilter2`, `filtfilt`, `sosfilt`, `hilbert`, `hilbert2`, `detrend`, `freq_shift`, `channelize_poly`, `decimate`, `resample`, `resample_poly`, `upfirdn` |
| `radartools` | `pulse_compression`, `pulse_doppler`, `ambgfun`, `cfar_alpha`, `ca_cfar`, `mvdr` |
| `spectral` | `lombscargle`, `periodogram`, `welch`, `csd`, `spectrogram`, `stft`, `istft`, `coherence`, `vectorstrength` |
| `wavelets` | `qmf`, `morlet`, `ricker`, `morlet2`, `cwt` |
| `correlate` | `correlate`, `correlate2d`, `correlation_lags` |
| `demod` | `fm_demod` |
| `estimation` | `kalman_filter` |
| `peak_finding` | `argrelextrema`, `argrelmin`, `argrelmax` |

## 原注释候选项

这些条目原先在 `scripts/test/run_all_tests.sh` 注册表中以注释形式存在。静态盘点显示它们均有测试源码和 CMake target，因此已纳入 active 81 条，并已随 Stage3 v2 完整验证通过。

| 模块 | 候选算子 |
| --- | --- |
| `windows` | `get_window`, `barthann`, `bartlett`, `blackman`, `blackmanharris`, `bohman`, `boxcar`, `cosine`, `exponential`, `flattop`, `gaussian`, `general_hamming`, `hann`, `nuttall`, `tukey` |
| `filter_design` | `kaiser_beta`, `kaiser_atten`, `cmplx_sort` |
| `filtering` | `lfilter`, `firfilter_zi`, `filtfilt` |
| `radartools` | `mvdr` |
| `spectral` | `periodogram`, `welch`, `coherence` |
| `correlate` | `correlation_lags` |
| `peak_finding` | `argrelmin`, `argrelmax` |

## 容器复验入口

active 81 条 accuracy 已通过。复现命令：

```bash
cd /home/usr_04/CETC
./copy_to_container.sh gpu_04
```

进入容器后执行同步脚本打印的 `/CETC.incoming.<timestamp>/replace_container_project.sh /CETC`，然后运行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage3.sh 2>&1 | tee stage3_accuracy.log
```

若复验失败，按模块归类：

- 构建失败：优先定位中科芯 `dlcc` 编译兼容问题。
- 链接失败：检查 support `.cu` 是否进入 target，以及 SDK 库映射是否完整。
- accuracy 失败：记录 CPU/GPU/reference 误差、输入规模、容差和依赖类型。
- 产物缺失：补报告字段或数据生成入口，不能静默跳过。

## V4.3 关闭结果

- active 81 条 accuracy 已完成，失败项为 0。
- 原注释候选 28 条已纳入 active；不再作为静默候选项保留。
- 每个模块都有报告产物和可复现命令。
- CPU reference 与中科芯 GPU 双链路完成验证；GPU 专指本服务器容器内 ZQ500。
- 关闭证据归档在 `data/reports/zhongkexin/stage3_runs/20260617_110827/`。
