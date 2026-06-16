# 中科芯 V4.2 Task1/Task2 依赖算子矩阵

## 文档定位

本文档冻结 V4.2 第二阶段的 Task1/Task2 直接依赖算子范围。第二阶段关闭前，矩阵内条目必须具备构建、运行、accuracy、报告和日志证据；若失败或暂缓，必须写入 `docs/design/zhongkexin_migration_change_log.md`。

统一执行入口：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2.log
```

默认输出：

- `data/reports/zhongkexin/stage2/latest_dependency_operator_report.csv`
- `data/reports/zhongkexin/stage2/latest_dependency_operator_report.json`
- `data/reports/zhongkexin/stage2/latest_dependency_operator_report.md`
- `data/reports/zhongkexin/stage2/operators/*.log`
- `data/reports/demo/latest_task_demo_scale_benchmark.csv`
- `data/reports/demo/latest_task_demo_scale_report.json`
- `data/reports/demo/latest_task_demo_scale_report.md`
- `data/reports/demo/task1_radar/task1_l1_l6_scale_performance.*`
- `data/reports/demo/task2_multidomain_l1_l6_scale_performance.*`

## Task1 依赖矩阵

| 模块 | 算子 | 用途 | 测试入口 | V4.2 默认 case_set | 平台注意事项 |
| --- | --- | --- | --- | --- | --- |
| `radartools` | `pulse_compression` | 脉冲压缩主链路 | `run_all_tests.sh --module radartools --operator pulse_compression` | `accuracy` | FFT-heavy，需确认补 0 和裁剪口径 |
| `radartools` | `pulse_doppler` | Doppler 处理 | `run_all_tests.sh --module radartools --operator pulse_doppler` | `accuracy` | FFT-heavy，需确认 2 的整数次幂长度 |
| `radartools` | `ambgfun` | 模糊函数表面 | `run_all_tests.sh --module radartools --operator ambgfun` | `accuracy` | FFT/相关运算组合路径 |
| `radartools` | `ca_cfar` | CA-CFAR 检测 | `run_all_tests.sh --module radartools --operator ca_cfar` | `accuracy` | 边界窗口和保护单元检查 |
| `radartools` | `cfar_alpha` | CFAR 阈值系数 | `run_all_tests.sh --module radartools --operator cfar_alpha` | `accuracy` | 标量公式与边界输入 |
| `spectral` | `spectrogram` | 频谱图/时频辅助 | `run_all_tests.sh --module spectral --operator spectrogram` | `accuracy` | FFT-heavy，需确认 nfft 支持范围 |
| `filter_design` | `firwin` | 匹配滤波/窗口化 FIR | `run_all_tests.sh --module filter_design --operator firwin` | `accuracy` | 窗函数和 tap 数边界 |
| `filter_design` | `firwin2` | 任意响应 FIR 设计 | `run_all_tests.sh --module filter_design --operator firwin2` | `accuracy` | 频率网格边界 |
| `windows` | `hamming` | 默认窗函数 | `run_all_tests.sh --module windows --operator hamming` | `accuracy` | 任务窗函数依赖 |
| `windows` | `kaiser` | 可调窗函数 | `run_all_tests.sh --module windows --operator kaiser` | `accuracy` | beta 参数边界 |

## Task2 依赖矩阵

| 模块 | 算子 | 用途 | 测试入口 | V4.2 默认 case_set | 平台注意事项 |
| --- | --- | --- | --- | --- | --- |
| `waveforms` | `chirp` | 多域特征输入生成 | `run_all_tests.sh --module waveforms --operator chirp` | `accuracy` | 相位累计误差 |
| `waveforms` | `gausspulse` | 高斯脉冲输入 | `run_all_tests.sh --module waveforms --operator gausspulse` | `accuracy` | 包络和 cutoff 口径 |
| `waveforms` | `unit_impulse` | 基础输入构造 | `run_all_tests.sh --module waveforms --operator unit_impulse` | `accuracy` | 空/边界索引 |
| `filter_design` | `firwin` | FIR 滤波器设计 | `run_all_tests.sh --module filter_design --operator firwin` | `accuracy` | 与 filtering 共享 |
| `filtering` | `firfilter` | 帧级滤波 | `run_all_tests.sh --module filtering --operator firfilter` | `accuracy` | FIR 卷积路径 |
| `filtering` | `sosfilt` | 二阶节滤波 | `run_all_tests.sh --module filtering --operator sosfilt` | `accuracy` | 状态维度边界 |
| `filtering` | `hilbert` | 解析信号 | `run_all_tests.sh --module filtering --operator hilbert` | `accuracy` | FFT-heavy，需确认长度补齐 |
| `filtering` | `hilbert2` | 二维解析信号 | `run_all_tests.sh --module filtering --operator hilbert2` | `accuracy` | 2D FFT-heavy |
| `bsplines` | `cubic` | 平滑/插值辅助 | `run_all_tests.sh --module bsplines --operator cubic` | `accuracy` | 轻量 kernel |
| `bsplines` | `quadratic` | 平滑/插值辅助 | `run_all_tests.sh --module bsplines --operator quadratic` | `accuracy` | 轻量 kernel |
| `correlate` | `correlate` | 模板相关 | `run_all_tests.sh --module correlate --operator correlate` | `accuracy` | 卷积/相关长度边界 |
| `correlate` | `correlate2d` | 2D 相关 | `run_all_tests.sh --module correlate --operator correlate2d` | `accuracy` | 形状和边界 padding |
| `demod` | `fm_demod` | FM 解调评分 | `run_all_tests.sh --module demod --operator fm_demod` | `accuracy` | 相位差和 unwrap 口径 |
| `spectral` | `spectrogram` | 时频能量评分 | `run_all_tests.sh --module spectral --operator spectrogram` | `accuracy` | FFT-heavy |
| `spectral` | `stft` | STFT 基础路径 | `run_all_tests.sh --module spectral --operator stft` | `accuracy` | FFT-heavy |
| `wavelets` | `cwt` | CWT 特征评分 | `run_all_tests.sh --module wavelets --operator cwt` | `accuracy` | 宽度数组与边界输入 |
| `wavelets` | `ricker` | CWT wavelet | `run_all_tests.sh --module wavelets --operator ricker` | `accuracy` | wavelet 核生成 |
| `peak_finding` | `argrelextrema` | 峰值轨迹候选 | `run_all_tests.sh --module peak_finding --operator argrelextrema` | `accuracy` | order 参数和平台无 Thrust 路径 |
| `estimation` | `kalman_filter` | 跨帧轨迹平滑 | `run_all_tests.sh --module estimation --operator kalman_filter` | `accuracy` | 状态更新稳定性 |

## 阶段关闭要求

- 上述矩阵条目必须由 `scripts/platform/run_zhongkexin_stage2.sh` 自动执行并生成独立日志。
- 失败条目不得只记录在终端输出中，必须进入迁移台账。
- L1-L6 sweep 必须生成 CSV/JSON/Markdown 和 Task1/Task2 图件。
- 若某条目在中科芯平台需要暂缓，必须写清楚是否影响 Task1/Task2 主链路、是否影响 NVIDIA 路径，以及计划清理阶段。
