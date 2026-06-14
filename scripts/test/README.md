# scripts/test 使用说明

## 版本说明

当前测试脚本版本：`V3.9`（任务级 6 档验收与全量算子单图输出）

- 命名遵循 `docs/submission` 版本风格：展示用 `V3.x.y`，文件名用 `V3_x_y`。
- 当前任务级 Demo 验收增强与 6 档规模说明见：[READMEV3_9.md](/home/vipuser/CETC/scripts/test/READMEV3_9.md)
- 上一版 GPU-only 全量复测说明见：[READMEV3_8_4.md](/home/vipuser/CETC/scripts/test/READMEV3_8_4.md)
- 上一版低 e2e 算子优化说明见：[READMEV3_8_3.md](/home/vipuser/CETC/scripts/test/READMEV3_8_3.md)
- 上一版 large-gpu 全量基线与 Task2 回归说明见：[READMEV3_8_2.md](/home/vipuser/CETC/scripts/test/READMEV3_8_2.md)
- 当前版本说明见：[READMEV3_8_1.md](/home/vipuser/CETC/scripts/test/READMEV3_8_1.md)
- 上一版混合误差与单 CSV 输出说明见：[READMEV3_8_0.md](/home/vipuser/CETC/scripts/test/READMEV3_8_0.md)
- 上一版 V3.7 回归扫描说明见：[READMEV3_7_0.md](/home/vipuser/CETC/scripts/test/READMEV3_7_0.md)
- 上一版全仓单精度清理与 README 收敛说明见：[READMEV3_6_0.md](/home/vipuser/CETC/scripts/test/READMEV3_6_0.md)
- 上一版大规模 GPU 并行性复测与低速/高误差算子优化说明见：[READMEV3_5_0.md](/home/vipuser/CETC/scripts/test/READMEV3_5_0.md)
- 上一版 CUDA 标准库适配与低速算子二次优化说明见：[READMEV3_4_0.md](/home/vipuser/CETC/scripts/test/READMEV3_4_0.md)
- 上一版全量 6 规模采集说明见：[READMEV3_3_0.md](/home/vipuser/CETC/scripts/test/READMEV3_3_0.md)
- 上一版精度审计与报告格式统一说明见：[READMEV3_2_1.md](/home/vipuser/CETC/scripts/test/READMEV3_2_1.md)

本版完成状态：

- 全量多规模采集脚本：`benchmark_all_ops_scales.py` 已支持 `--scale-profile default,large-gpu`
- GPU-only 全量复测选项：`benchmark_all_ops_scales.py --gpu-only` 可复用 CPU baseline，只重复采集 GPU e2e/kernel timing
- 论文风格作图脚本：`plot_all_ops_benchmark.py --figure-set all` 生成 5 张全局总览图，并为每个算子生成一张独立 CPU/GPU 耗时与加速比图
- 任务级 Demo 验收脚本：`run_task_demos.sh` 支持 `--scale-sweep`，Task1/Task2 各 6 档规模，输出任务级 pass、误差、耗时、稳定性和资源漂移汇总
- 任务级 Demo 图件：`visualize_task1.py` / `visualize_task2.py` 默认覆盖生成 Word 友好 PNG；`run_task_demos.sh --scale-sweep` 会自动刷新 L1-L6 任务性能图
- 默认输出：benchmark 默认只输出主 CSV，不再自动生成 Markdown 报告或图件
- 主 CSV 新增兼容耗时列：`cpu_median_ms`、`gpu_e2e_median_ms`、`gpu_kernel_median_ms`、`gpu_e2e_min_ms`、`gpu_e2e_max_ms`
- 低速/高误差算子优化：已覆盖 `sosfilt`、`detrend`、`kalman_filter`、`gausspulse`、`sawtooth`、`resample`、`pulse_doppler`、`vectorstrength`
- 覆盖范围：当前启用 53 个算子，每个算子 6 个规模点
- 最新全量 benchmark：`318/318` 行全部 `passed`，`mixed_error > 1e-4` 的行数为 `0`
- 精度优化结果：`wiener` deterministic reduction、`detrend` CPU/CUDA reduction 对齐、`channelize_poly` 固定单精度累积顺序已记录在 V3.8.1 文档
- 代表性最大规模误差：`channelize_poly=5.70e-05`、`resample=2.88e-05`、`vectorstrength=2.06e-05`、`sawtooth=2.38e-07`
- 代表性冒烟：`bsplines/cubic`、`filtering/lfilter_zi,channelize_poly`、`spectral/istft,lombscargle` 已通过
- 全量精度审计：`passed=53, failed=0, infra_failed=0`
- 报告格式统一：53 个 operator-level `latest_metrics.json` 均为标准 `summary` 结构
- 修正队列：当前 `latest_precision_fix_queue.csv` 为空，说明现有阈值下没有待修正算子
- 单精度清理：生产库、测试、数据生成脚本、demo、活动 README 与 manifest 已统一到 `float32` / `complex64` 语义
- 单精度采样回归：`detrend,vectorstrength,gausspulse,sawtooth,chirp,square,unit_impulse,kalman_filter,correlate` 的 large-gpu 采样共 `54/54` 行全部 `passed`
- V3.7 回归扫描：不再新增独立测试脚本，统一使用 `benchmark_all_ops_scales.py` 生成 large-gpu CSV 与简洁报告
- Benchmark 主误差指标：`mixed_error`，近零区域使用绝对误差，其他区域使用相对误差
- 精度优化细节：已记录 `wiener` deterministic reduction、`detrend` CPU/CUDA reduction 对齐、`channelize_poly` 固定单精度累积顺序，以及目标算子最终最大规模指标

## 单精度实现约定

当前代码线采用统一单精度口径：

- 公共接口仍保留 `dtype` 参数，但默认值与允许值收敛到 `float32`。
- CPU/CUDA 对照、测试误差统计、demo 计时统计、数据生成脚本和活动 manifest 均使用单精度数据描述。
- `waveforms` 使用单精度数学函数和常量；`detrend` 与 `vectorstrength` 的 reduction workspace、shared memory 和系数计算使用单精度；`correlate` 的复数累加改为项目内 `Complex` 语义。
- 误差阈值未放宽，单算子 metrics 仍保留 GPU 相对 CPU 的 `max_abs_error/max_rel_error/rmse`。
- 全量 benchmark 主 CSV 默认展示 `mixed_error`：落入单精度近零容差带时看绝对误差，其他区域看相对误差。

## `latest_metrics.json` 标准结构

本版统一了旧版顶层 `pass` 报告格式。所有 operator-level `latest_metrics.json` 均应包含：

```json
{
  "module": "...",
  "operator": "...",
  "generated_at": "...",
  "git_commit": "...",
  "gpu_name": "...",
  "compile_config": {
    "cxx_standard": 201703,
    "cudart_version": 11070
  },
  "summary": {
    "pass": true,
    "accuracy_cases": 0,
    "perf_cases": 0,
    "max_abs_error": 0,
    "max_rel_error": 0,
    "max_floor_rel_error": 0,
    "near_zero_count": 0,
    "near_zero_fraction": 0,
    "error_class": "ok",
    "rmse": 0,
    "gpu_e2e_speedup": 0,
    "gpu_kernel_speedup": 0
  },
  "cases": []
}
```

已统一的旧格式算子：

- `correlate/correlate`
- `correlate/correlate2d`
- `demod/fm_demod`
- `estimation/kalman_filter`
- `peak_finding/argrelextrema`

说明：

- `cases: []` 表示该算子当前只迁移了 summary 级 metrics，尚未迁移完整逐 case JSON。
- `audit_all_ops_precision.py` 仅读取标准 `summary` 结构，不再兼容旧版顶层 `pass` 格式。
- `run_all_tests.sh` 的构建是默认行为；使用 `--no-build` 才会跳过构建。

## 脚本参数速查

本节覆盖 `scripts/test` 下当前测试相关脚本的所有可设置选项。`run_all_tests.sh` 使用单数 `--module/--operator`，一次过滤一个模块或算子；Python 汇总脚本使用复数 `--modules/--operators`，支持逗号分隔列表。`--demo-fast` 会在未显式指定 `--warmup/--repeat` 时把计时参数收敛到 `warmup=1, repeat=3`。`--gpu-only` 依赖 CPU baseline cache：`auto` 补齐缺失项，`refresh` 重建 baseline，`reuse` 要求已有完整 baseline。

### `run_all_tests.sh`

| 选项 | 默认值/默认行为 | 作用 | 典型使用 |
|---|---|---|---|
| `--module NAME` | `all` | 只运行指定模块 | 单模块回归，如 `--module spectral` |
| `--operator NAME` | `all` | 只运行指定算子 | 单算子调试，如 `--operator spectrogram` |
| `--case-set NAME` | `full` | 选择 `smoke/accuracy/perf/full` 用例集合 | 只测性能用 `--case-set perf` |
| `--emit-report` | 关闭 | 写出 reports 与 generated samples | 需要刷新 `latest_metrics.json` 时开启 |
| `--verbose` | 关闭 | 输出更详细 runner 日志 | 定位失败 case |
| `--gpu-only-perf` | 关闭 | perf 模式跳过 CPU reference/timing，只采 GPU timing | 配合 GPU-only benchmark |
| `--demo-fast` | 关闭 | 未显式指定时使用 `warmup=1, repeat=3` | 现场演示或快速冒烟 |
| `--warmup N` | `5` | perf warmup 次数，非负整数 | 控制计时稳定性 |
| `--repeat N` | `30` | perf repeat 次数，非负整数 | 控制计时统计样本量 |
| `--build-dir PATH` | `<repo>/build` | CMake build 目录 | 使用非默认构建目录 |
| `--build-type TYPE` | `Release` | CMake build type | Debug/Release 切换 |
| `--cuda-arch ARCH` | 当前默认 `80` | 传给 CMake 的 CUDA 架构 | 指定目标 GPU 架构 |
| `--jobs N` | 自动探测 | 并行构建 job 数 | 限制或加速构建 |
| `--no-build` | 默认会构建 | 跳过 configure/build，复用现有二进制 | 已构建后快速复测 |
| `--list` | 关闭 | 列出过滤后的已注册测试项 | 查看可用模块/算子 |
| `--help` | 关闭 | 打印帮助 | 查看脚本自带说明 |

### `benchmark_all_ops_scales.py`

| 选项 | 默认值/默认行为 | 作用 | 典型使用 |
|---|---|---|---|
| `--modules MODULES` | `all` | 逗号分隔模块过滤 | `--modules filtering,spectral` |
| `--operators OPERATORS` | `all` | 逗号分隔算子过滤 | `--operators cwt,stft` |
| `--scale-count SCALE_COUNT` | `6`，当前固定 | 规模点数量 | 保持默认，不作为常规调参 |
| `--scale-profile {default,large-gpu}` | `default` | 选择 6 档规模 profile | 展示 GPU 吞吐用 `large-gpu` |
| `--warmup WARMUP` | `5`，`--demo-fast` 下为 `1` | perf warmup 次数 | 稳定复测用较大值 |
| `--repeat REPEAT` | `30`，`--demo-fast` 下为 `3` | perf repeat 次数 | 现场快跑用小值 |
| `--demo-fast` | 关闭 | 未显式指定时使用 `warmup=1, repeat=3` | 快速生成演示数据 |
| `--build` | 关闭 | benchmark 前构建选中测试目标 | fresh 环境或改代码后 |
| `--no-build` | 默认 | 复用已有二进制 | 已构建后的批量复测 |
| `--build-dir BUILD_DIR` | `build` | 构建目录 | 与实际 CMake build 目录对齐 |
| `--output-dir OUTPUT_DIR` | `data/reports/unit/benchmarks/all_ops` | benchmark 输出根目录 | 区分 `all_ops` 与 `all_ops_large` |
| `--report-mode {csv,concise,full}` | `csv` | 控制报告详细程度 | 归档用 `full`，日常用 `csv` |
| `--keep-old-output` | 关闭 | 保留旧 CSV/Markdown | 对比多轮结果 |
| `--keep-generated-samples` | 关闭 | 保留每算子 input/output 样本 | 排查数据与误差 |
| `--runner-script RUNNER_SCRIPT` | `scripts/test/run_all_tests.sh` | 指定底层 runner | 使用自定义 runner 路径 |
| `--gpu-only` | 关闭 | 复用 CPU baseline，仅采 GPU perf timing | 快速 GPU-only 复测 |
| `--cpu-baseline-mode {auto,refresh,reuse}` | `auto` | 控制 GPU-only CPU baseline 策略 | 最终验收常用 `reuse` |
| `--cpu-baseline-file CPU_BASELINE_FILE` | `data/reports/unit/benchmarks/cpu_baselines/<scale-profile>/latest_cpu_baseline.json` | CPU baseline cache JSON | 显式复用 demo-fast baseline |

### `plot_all_ops_benchmark.py`

| 选项 | 默认值/默认行为 | 作用 | 典型使用 |
|---|---|---|---|
| `--csv CSV` | `data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv` | 输入 all-operator benchmark CSV | 指向 `all_ops_large` CSV |
| `--output-dir OUTPUT_DIR` | `data/reports/unit/benchmarks/all_ops/figures` | 图件输出目录 | 与输入 CSV 所属报告目录对应 |
| `--formats FORMATS` | `png` | 逗号分隔输出格式 | Word 推荐 `png,svg` |
| `--dpi DPI` | `450` | PNG raster DPI | Word 小图常用 `300` |
| `--keep-old-output` | 关闭 | 不清理旧图件 | 手工保留历史图 |
| `--figure-set {overview,all,word,word-summary}` | `overview` | 选择图件集合 | `all` 全局+单算子；`word` 按模块拆分；`word-summary` 正文结论图 |
| `--report-mode {compact,full}` | `compact` | 兼容选项，当前不生成 candidate report | 保持默认即可 |

`--figure-set word` 会按模块输出 A4 纵向正文宽度的 5 类图到 `word_figures/`，直接显示完整 `module/operator`。`--figure-set word-summary` 输出更紧凑的 Word 正文结论图到 `word_summary_figures/`，用于报告正文概览，不替代按模块细节图。

### `run_task_demos.sh`

| 选项 | 默认值/默认行为 | 作用 | 典型使用 |
|---|---|---|---|
| `--build-dir DIR` | `build` | 构建目录 | 与 CMake build 目录对齐 |
| `--build` | 默认开启 | 运行前构建 task demo 目标 | fresh 环境验收 |
| `--no-build` | 关闭 | 跳过构建 | 已构建后快速验收 |
| `--repeat N` | `5` | 传给两个 demo 的 repeat 次数 | 稳定性验收或现场快检 |
| `--scale-sweep` | 关闭 | 执行 Task1/Task2 6 档规模扫测 | 生成任务级规模趋势 |
| `--scales LIST` | `1,2,3,4,5,6` | 指定 `--scale-sweep` 的规模列表 | 只扫 `3,4,5,6` |
| `--leak-check` | 关闭 | 可用时额外运行 `compute-sanitizer --tool memcheck` | 深度内存/显存检查 |
| `-h, --help` | 关闭 | 打印帮助 | 查看脚本自带说明 |

`--scale-sweep` 写完 `latest_task_demo_scale_benchmark.csv` 后会自动调用 `plot_task_demo_scale_benchmark.py`，覆盖生成 Word 友好的任务级 L1-L6 性能图。

### `plot_task_demo_scale_benchmark.py`

| 选项 | 默认值/默认行为 | 作用 | 典型使用 |
|---|---|---|---|
| `--csv CSV` | `data/reports/demo/latest_task_demo_scale_benchmark.csv` | 输入任务级 scale benchmark CSV | 复用已归档 CSV 重新出图 |
| `--output-root DIR` | `data/reports/demo` | 图件输出根目录 | 与 `run_task_demos.sh` 报告根目录一致 |

输出图件直接覆盖现有路径，面向 Word 正文插入使用：

- `data/reports/demo/task1_radar/task1_l1_l6_scale_performance.png/svg/pdf`
- `data/reports/demo/task1_radar/task1_l1_l6_scale_performance_word.png/svg/pdf`
- `data/reports/demo/task2_multidomain_l1_l6_scale_performance.png/svg`

### `audit_all_ops_precision.py`

| 选项 | 默认值/默认行为 | 作用 | 典型使用 |
|---|---|---|---|
| `--modules MODULES` | `all` | 逗号分隔模块过滤 | 只审计指定模块 |
| `--operators OPERATORS` | `all` | 逗号分隔算子过滤 | 只审计指定算子 |
| `--build` | 关闭 | 每个算子执行前构建 | 缺二进制或代码刚改后 |
| `--no-build` | 默认 | 复用已有二进制 | 常规审计 |
| `--build-dir BUILD_DIR` | `build` | 构建目录 | 与实际 build 目录一致 |
| `--warmup WARMUP` | `5` | perf 快照 warmup 次数 | 调整性能采样稳定性 |
| `--repeat REPEAT` | `30` | perf 快照 repeat 次数 | 调整性能采样样本量 |
| `--output-dir OUTPUT_DIR` | `data/reports/unit/audit` | 审计输出目录 | 单独归档审计结果 |
| `--runner-script RUNNER_SCRIPT` | `scripts/test/run_all_tests.sh` | 指定底层 runner | 使用自定义 runner 路径 |
| `--compare-baseline COMPARE_BASELINE` | 空 | 与旧 baseline CSV 做 perf delta 对比 | 修复前后对比 |
| `--fix-notes-file FIX_NOTES_FILE` | 空 | 读取修正说明 CSV 增强报告 | 生成带修复机制说明的报告 |

## `benchmark_all_ops_scales.py`（全量多规模采集）
该脚本用于当前已启用的 53 个算子多规模 `perf` 自动化测试。每个算子执行 6 个规模点，脚本会按算子输入语义临时改写 `data/generated/unit/<module>/<operator>/manifest.json`，运行结束后自动恢复 manifest。

默认行为：
- 默认模块/算子：`all`（来自 `scripts/test/run_all_tests.sh --list`）
- 默认规模点数：6
- 默认规模 profile：`--scale-profile default`
- 默认口径：`--case-set perf --emit-report --warmup 5 --repeat 30`
- 默认构建：`--no-build`
- 默认输出目录：`data/reports/unit/benchmarks/all_ops`
- 默认报告策略：只覆盖更新固定的 `latest_all_ops_scale_benchmark.csv`
- 默认清理策略：读取 metrics 后删除本轮生成的 `input/` 与 `output_samples/` 调试样本，避免 `data/generated/unit/**` 堆积

常用命令：

```bash
# 1) 全量 53 算子 x 6 规模，复用已有二进制
scripts/test/benchmark_all_ops_scales.py --no-build

# 2) 全量执行前先构建
scripts/test/benchmark_all_ops_scales.py --build --build-dir build

# 3) 大规模 GPU profile，全量复测
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 \
  --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops_large

# 4) 大规模 GPU profile，指定低速/高误差候选算子
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --operators sosfilt,detrend,kalman_filter,gausspulse,sawtooth,chirp,square,firfilter,fm_demod \
  --warmup 5 \
  --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops_large

# 5) 单算子冒烟，快速验证 CSV 与 manifest 恢复
scripts/test/benchmark_all_ops_scales.py \
  --modules bsplines \
  --operators cubic \
  --no-build \
  --warmup 1 \
  --repeat 1

# 6) 跑指定模块或算子集合
scripts/test/benchmark_all_ops_scales.py \
  --modules filtering,spectral \
  --operators lfilter_zi,channelize_poly,istft,lombscargle \
  --no-build \
  --warmup 1 \
  --repeat 1

# 7) 自定义输出目录
scripts/test/benchmark_all_ops_scales.py \
  --output-dir data/reports/unit/benchmarks/all_ops
```

默认输出文件：

- `data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv`

如需 Markdown 简表，增加 `--report-mode concise`，会额外写出 `latest_report.md`。
如需归档型详细输出，增加 `--report-mode full`，会额外写出时间戳总表、分模块 CSV，以及 `large-gpu` 候选 CSV/Markdown。
如需保留每个算子的输入/输出样本用于排错，增加 `--keep-generated-samples`；如需保留旧 benchmark CSV/Markdown，增加 `--keep-old-output`。

`default` 与 `large-gpu` 都是 6 档规模，不是“默认只有一个规模”。区别是每档的实际输入规模不同：

- `default`：常规回归规模，适合快速稳定复测。
- `large-gpu`：更大的 GPU 展示/压力规模，更适合体现 GPU 吞吐和加速比。
- 推荐输出目录分别使用 `data/reports/unit/benchmarks/all_ops` 与 `data/reports/unit/benchmarks/all_ops_large`，避免两套 profile 的 CSV 和图件混淆。

规模策略：

| `scale_family` | 6 个规模点 | `scale_value` 含义 | 对应算子 |
|---|---:|---|---|
| `linear_points` | `1024,4096,16384,65536,262144,1048576` | 一维点数或样本数 | `waveforms/chirp`、`waveforms/gausspulse`、`waveforms/sawtooth`、`waveforms/square`、`waveforms/unit_impulse`、`bsplines/cubic`、`bsplines/quadratic`、`bsplines/gauss_spline`、`windows/chebwin`、`windows/general_cosine`、`windows/general_gaussian`、`windows/hamming`、`windows/kaiser`、`windows/parzen`、`windows/taylor`、`windows/triang`、`wavelets/qmf`、`wavelets/morlet`、`wavelets/ricker`、`wavelets/morlet2` |
| `medium_1d_fft` | `1024,2048,4096,8192,16384,32768` | 中等规模一维长度或事件数 | `filtering/firfilter2`、`filtering/sosfilt`、`filtering/hilbert`、`filtering/detrend`、`filtering/freq_shift`、`filtering/channelize_poly`、`filtering/decimate`、`filtering/resample`、`filtering/resample_poly`、`filtering/upfirdn`、`spectral/csd`、`spectral/spectrogram`、`spectral/stft`、`spectral/vectorstrength`、`wavelets/cwt` |
| `heavy_quadratic` | `256,512,1024,2048,4096,8192` | 重计算输入长度 | `radartools/ambgfun`、`spectral/lombscargle`、`correlate/correlate` |
| `matrix_total` | `4096,16384,65536,262144,524288,1048576` | 矩阵/图像总元素数 | `filtering/wiener`、`filtering/firfilter`、`filtering/hilbert2`、`radartools/pulse_compression`、`radartools/pulse_doppler`、`radartools/ca_cfar`、`correlate/correlate2d`、`demod/fm_demod`、`peak_finding/argrelextrema` |
| `filter_design_taps` | `129,257,513,1025,2049,4097` | FIR tap 数 | `filter_design/firwin`、`filter_design/firwin2` |
| `small_state` | `16,32,64,128,256,512` | 小状态数、滤波阶数或点数 | `filtering/lfilter_zi`、`radartools/cfar_alpha`、`estimation/kalman_filter` |
| `istft_frames` | `9,17,33,65,129,257` | `istft` 时间帧数 | `spectral/istft` |

`large-gpu` 规模策略：

| `scale_family` | 6 个规模点 | 说明 |
|---|---:|---|
| `linear_points` | `65536,262144,1048576,4194304,8388608,16777216` | 点式、轻量、批处理友好算子显著放大 |
| `medium_1d_fft` | `32768,65536,131072,262144,524288,1048576` | 中等一维 FFT/滤波/谱分析路径放大到百万级 |
| `kalman_points` | `512,2048,8192,32768,131072,524288` | `kalman_filter` 按 points 批处理规模测试 |
| 其他规模族 | 继承 `default` | O(N^2)、filter-design taps、标量 helper 保持安全上限 |

作图建议：
- 跨算子对比优先使用 `scale_level=1..6` 作为横轴；
- 图例或标注使用 `scale_value` 展示实际输入规模；
- 同一 `scale_family` 内的算子可以直接按实际规模比较。

关键字段说明：

| 字段名 | 含义 |
|---|---|
| `scale_level` | 抽象规模级别，固定为 `1..6`，便于跨算子对齐作图 |
| `scale_value` | 当前算子的实际规模值，例如点数、总元素数、tap 数或帧数 |
| `scale_family` | 规模族，说明该算子使用哪一组 6 点阶梯 |
| `status` | 运行状态：`passed` / `failed` |
| `pass` | `return_code==0` 且 `summary.pass=true` 时为 `true` |
| `max_abs_error` | GPU 输出相对 CPU 输出的最大绝对误差 |
| `max_rel_error` | GPU 输出相对 CPU 输出的最大相对误差，保存为 ratio 小数 |
| `max_floor_rel_error` | 兼容字段，默认等同于单元测试输出的 `max_rel_error` |
| `near_zero_count` | CPU 参考输出落入单元测试同款近零分母 floor 的样本数 |
| `near_zero_fraction` | 近零样本占比 |
| `error_class` | `near-zero-relative` / `true-error` / `performance-bound` / `ok` |
| `rmse` | GPU 输出相对 CPU 输出的均方根误差 |
| `cpu_*_ms` | CPU 延迟统计，包含 `median/mean/p95/min/max/std` |
| `gpu_e2e_*_ms` | GPU 端到端延迟统计，包含 `median/mean/p95/min/max/std` |
| `gpu_kernel_*_ms` | GPU kernel 延迟统计，包含 `median/mean/p95/min/max/std` |
| `gpu_e2e_speedup` | `cpu_median_ms / gpu_e2e_median_ms` |
| `gpu_kernel_speedup` | `cpu_median_ms / gpu_kernel_median_ms` |
| `shape_note` | 本行实际改写的关键规模字段摘要 |
| `metrics_json_path` | 本行读取的 `latest_metrics.json` 绝对路径 |
| `error_note` | 失败诊断信息，例如命令失败、metrics 未更新或 manifest 缩放失败 |

新增兼容耗时列：

| 字段名 | 含义 |
|---|---|
| `cpu_median_ms` | CPU perf median 耗时，GPU-only reuse 模式下来自 CPU baseline |
| `gpu_e2e_median_ms` | 当前 GPU e2e median 耗时 |
| `gpu_kernel_median_ms` | 当前 GPU kernel median 耗时 |
| `gpu_e2e_min_ms` | 当前 GPU e2e 最小耗时 |
| `gpu_e2e_max_ms` | 当前 GPU e2e 最大耗时 |

误差口径说明：
- `max_abs_error/max_rel_error/rmse` 均来自 `latest_metrics.json` 的 `summary`，其含义是 GPU 输出相对 CPU 输出的误差；
- `max_rel_error` 不保存百分数，例如 `0.001` 表示 `0.1%`；
- Python 不重新计算 `max_rel_error`；`max_floor_rel_error` 仅作为历史兼容列保留，默认等同于 `max_rel_error`；
- `near_zero_count/near_zero_fraction` 只做诊断：`filtering/filter_design` 使用 `1e-15`，`demod/correlate/estimation` 使用 `1e-12`，其余多数模块使用 `1e-30`，`waveforms` 按测试单元的零范数语义统计；
- 若画百分比图，在绘图阶段使用对应 ratio 字段乘以 `100`。

## `run_task_demos.sh`（任务级 Demo 验收）

该脚本用于 Task1/Task2 任务级验收，覆盖业务指标、分阶段耗时、计算误差、repeat 稳定性、CPU/GPU 资源占用、异常输入明确报错，以及可选 `compute-sanitizer` 深度检查。

常用命令：

```bash
# 默认 L3 任务级验收，适合现场快检
CUDA_VISIBLE_DEVICES=1 scripts/test/run_task_demos.sh --no-build --repeat 5

# 6 档任务规模扫测，适合归档和展示规模趋势
CUDA_VISIBLE_DEVICES=1 scripts/test/run_task_demos.sh --no-build --scale-sweep --repeat 3

# 只扫部分规模
CUDA_VISIBLE_DEVICES=1 scripts/test/run_task_demos.sh --no-build --scale-sweep --scales 3,4,5,6 --repeat 3

# 深度内存/显存检查
CUDA_VISIBLE_DEVICES=1 scripts/test/run_task_demos.sh --no-build --repeat 2 --leak-check
```

Task1 6 档规模：

`scale_value = num_pulses * samples_per_pulse`，`rx_shape = num_pulses x samples_per_pulse`。`delay_samples` 由规模自动派生，公式为 `samples_per_pulse * 3 / 16`。

| level | num_pulses | samples_per_pulse | rx_shape | template_length | delay_samples | pulse_compression_nfft | pulse_doppler_nfft | scale_value |
|---:|---:|---:|---|---:|---:|---:|---:|---:|
| L1 | 32 | 128 | 32 x 128 | 32 | 24 | 128 | 32 | 4096 |
| L2 | 48 | 256 | 48 x 256 | 64 | 48 | 256 | 64 | 12288 |
| L3 | 64 | 256 | 64 x 256 | 64 | 48 | 256 | 64 | 16384 |
| L4 | 96 | 512 | 96 x 512 | 128 | 96 | 512 | 128 | 49152 |
| L5 | 128 | 1024 | 128 x 1024 | 256 | 192 | 1024 | 128 | 131072 |
| L6 | 192 | 1536 | 192 x 1536 | 384 | 288 | 2048 | 256 | 294912 |

Task2 6 档规模：

`scale_value = num_frames * samples_per_frame`，`rx_shape = num_frames x samples_per_frame`。`target_start_sample_0`、`interferer_start_sample/interferer_length` 和 `representative_frame_index` 均由规模自动派生。

| level | num_frames | samples_per_frame | rx_shape | template_length | target_start_sample_0 | interferer_start_sample | interferer_length | representative_frame_index | filter_numtaps | spectrogram nperseg/noverlap/nfft | scale_value |
|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---|---:|
| L1 | 16 | 512 | 16 x 512 | 128 | 110 | 320 | 128 | 8 | 65 | 64 / 48 / 128 | 8192 |
| L2 | 32 | 768 | 32 x 768 | 192 | 165 | 480 | 192 | 16 | 97 | 96 / 72 / 128 | 24576 |
| L3 | 48 | 1024 | 48 x 1024 | 256 | 220 | 640 | 256 | 24 | 129 | 128 / 96 / 256 | 49152 |
| L4 | 64 | 1536 | 64 x 1536 | 384 | 330 | 960 | 384 | 32 | 161 | 192 / 144 / 256 | 98304 |
| L5 | 80 | 2048 | 80 x 2048 | 512 | 440 | 1280 | 512 | 40 | 193 | 256 / 192 / 512 | 163840 |
| L6 | 96 | 3072 | 96 x 3072 | 768 | 660 | 1920 | 768 | 48 | 257 | 384 / 288 / 512 | 294912 |

输出文件：

- `data/reports/demo/latest_task_demo_report.json`
- `data/reports/demo/latest_task_demo_report.md`
- `data/reports/demo/latest_task_demo_scale_benchmark.csv`
- `data/reports/demo/latest_task_demo_scale_report.json`
- `data/reports/demo/latest_task_demo_scale_report.md`
- `data/reports/demo/<task>/scales/L<N>/latest_metrics.json`
- `data/reports/demo/leak_check/*_compute_sanitizer.log`
- `data/reports/demo/task1_radar/task1_l1_l6_scale_performance.png/svg/pdf`
- `data/reports/demo/task1_radar/task1_l1_l6_scale_performance_word.png/svg/pdf`
- `data/reports/demo/task2_multidomain_l1_l6_scale_performance.png/svg`

任务级详情图默认覆盖生成 Word 友好 PNG：`data/reports/demo/task1_radar/figures/*.png` 和 `data/reports/demo/task2_features/figures/*.png` 均采用 300 dpi、大字号标题/坐标/图例/colorbar，适合 A4 纵向正文宽度插入。

现场演示建议：

- 完整 `53 x 6 x repeat30` 全量 benchmark 建议提前离线跑好，现场展示 CSV 和图件。
- 现场快检建议运行 `run_task_demos.sh --no-build --repeat 1`，时间允许时再跑 `--scale-sweep --repeat 1`。

## `plot_all_ops_benchmark.py`（论文风格作图）
该脚本是可选作图步骤，读取全量 benchmark CSV。默认输出总览图与每算子 summary；`--figure-set all` 会输出 5 张全局总览图，并额外在 `operator_figures/` 下为每个算子生成一张独立性能图。脚本只依赖 `numpy + matplotlib`，不依赖 `pandas/seaborn`。

默认读取：

```bash
data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv
```

大规模复测推荐命令：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
  --figure-set all \
  --dpi 450
```

输出文件：

- `figure_1_accuracy_performance_overview.png`
- `figure_2_cpu_gpu_e2e_time_heatmaps.png`
- `figure_3_e2e_speedup_heatmap.png`
- `figure_4_largest_scale_cpu_vs_gpu_scatter.png`
- `figure_5_largest_scale_speedup_rank.png`
- `operator_figures/<module>__<operator>.png`
- `latest_all_ops_plot_summary.csv`

全局热图的 y 轴直接使用完整 `module/operator` 算子名，并在每个热图 panel 内重复标注，便于单独截取任一 panel 时仍能对应具体算子。查看单个算子的 CPU/GPU 耗时曲线时，继续打开 `operator_figures/<module>__<operator>.*`。

图件含义：

| 图件 | 含义 |
|---|---|
| `figure_1_accuracy_performance_overview` | 全局总览热图；每个 panel 的 y 轴直接标注完整算子名，列是 L1-L6，panel 分别表示 e2e speedup、kernel speedup、mixed error 和 pass/fail |
| `figure_2_cpu_gpu_e2e_time_heatmaps` | 全算子 CPU/GPU e2e median 耗时热图；每个 panel 的 y 轴直接标注完整算子名 |
| `figure_3_e2e_speedup_heatmap` | 全算子 e2e 加速比热图；y 轴直接标注完整算子名 |
| `figure_4_largest_scale_cpu_vs_gpu_scatter` | 每个算子取最大规模点，横轴 CPU、纵轴 GPU，虚线是 `CPU=GPU` |
| `figure_5_largest_scale_speedup_rank` | 每个算子最大规模 e2e speedup 排序 |
| `operator_figures/<module>__<operator>` | 单算子图；上半部分是 L1-L6 CPU/GPU e2e median 耗时，下半部分是 e2e/kernel speedup |

完整图件：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops/figures \
  --figure-set all \
  --formats pdf,svg,png \
  --dpi 450
```

Word 友好版图件：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
  --figure-set word \
  --formats png,svg \
  --dpi 300
```

Word 版输出到 `data/reports/unit/benchmarks/all_ops_large/figures/word_figures/`，按模块拆分，每个模块输出 5 类 A4 纵向正文宽度图：

- `figure_1_accuracy_performance_overview_<module>.*`
- `figure_2_cpu_gpu_e2e_time_heatmaps_<module>.*`
- `figure_3_e2e_speedup_heatmap_<module>.*`
- `figure_4_largest_scale_cpu_vs_gpu_scatter_<module>.*`
- `figure_5_largest_scale_speedup_rank_<module>.*`
- `latest_word_figure_manifest.csv`

Word 版不使用编号索引，图内直接显示完整 `module/operator` 算子名。插入 Word 时优先使用 `svg` 保持清晰；若 Word 环境兼容性较差，再使用同名 `png`。

候选分类口径：

| 分类 | 判定逻辑 | 处理建议 |
|---|---|---|
| `kernel-bound` | 最大规模 `gpu_kernel_speedup < 10` | 优先重构 kernel，并检查是否需要 scan/reduction/分块/批处理 |
| `e2e-copy-bound` | kernel 已快但 `gpu_e2e_speedup < 3` | 优先减少内部 D2D copy；进一步提升需要数据驻留或批处理 API |
| `error-bound` | 单元测试 `max_rel_error`、绝对误差或 RMSE 超阈值，且不是 near-zero denominator 放大 | 检查 CPU/CUDA 数值口径、边界处理与规约顺序 |
| `scalar-helper` | 标量公式或 tiny helper | 不作为 GPU kernel 优化对象 |
| `already-fast` | 速度与误差均满足当前口径 | 暂不作为优先优化项 |

near-zero denominator 说明：
- 若 `max_rel_error` 很大，但 `max_abs_error/RMSE` 很小且存在近零参考样本，报告会标注 `near-zero-relative`；
- 这类情况保留原始 `max_rel_error` 字段，图和优先级仍默认使用单元测试给出的 `max_rel_error`。

## V3.5.0 大规模优化结果摘要

最新大规模 CSV：

```bash
data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv
```

全量结果为 `318` 行，即 `53` 个启用算子乘 `6` 个规模点，全部 `passed`。

| 算子 | 最大规模 | e2e speedup | kernel speedup | max rel error | 结论 |
|---|---:|---:|---:|---:|---|
| `filtering/sosfilt` | `1048576` | `4.81x` | `76.27x` | `7.63e-4` | 分层 affine prefix-scan 生效 |
| `filtering/detrend` | `1048576` | `2.02x` | `79.51x` | `0` | two-pass block reduction 生效，e2e 仍受搬运/launch 影响 |
| `estimation/kalman_filter` | `524288` | `2.00x` | `715x` | `0` | points 批处理与 register fast path 生效 |
| `waveforms/gausspulse` | `16777216` | `8.71x` | `2152x` | `0` | single-precision 数值路径消除相对误差问题 |
| `waveforms/sawtooth` | `16777216` | `1.68x` | `882x` | `0` | single-precision 数值路径消除相对误差问题 |
| `demod/fm_demod` | `1048576` | `4.45x` | `500x` | `0` | 大规模 profile 下 kernel 并行度充分展开 |
| `filtering/resample` | `1048576` | `80.65x` | `447.2x` | `6.96e-2` | 修正大规模 cuFFT scaling 溢出；相对误差为 near-zero 放大 |
| `radartools/pulse_doppler` | `1048576` | `3.09x` | `584.8x` | `8.64e-6` | 修正 padding/truncation packing 问题 |
| `spectral/vectorstrength` | `1048576` | `398.2x` | `983x` | `9.76e-2` | two-stage reduction 生效；相对误差为 near-zero 放大 |

剩余候选：
- `peak_finding/argrelextrema`：唯一 `kernel-bound`，最大规模 kernel speedup 约 `5.75x`。
- `radartools/ca_cfar`：唯一真实 `error-bound`，最大规模 `max_rel_error` 约 `0.012`，后续需单独检查边界窗口和浮点规约口径。
- `radartools/cfar_alpha`：`scalar-helper`，本质是标量公式 helper，不作为 GPU kernel 优化对象。
- `bsplines/*`、`wavelets/qmf`、`waveforms/chirp/square/sawtooth`：主要为 `e2e-copy-bound`，kernel 已经很快，端到端加速受公开 API 下 H2D/D2H 限制。

## 历史专项规模脚本
`benchmark_bsplines_scales.py` 与 `benchmark_modules_scales.py` 已由 `benchmark_all_ops_scales.py` 覆盖并删除。

后续规模性能与误差采集统一使用：

```bash
scripts/test/benchmark_all_ops_scales.py --build --warmup 5 --repeat 30
```

如只想跑某个模块或算子，使用全量脚本的过滤参数：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --modules wavelets \
  --operators cwt \
  --no-build \
  --warmup 1 \
  --repeat 1
```

## `audit_all_ops_precision.py`（全量误差体检与修正跟踪）
该脚本用于当前已启用算子（来自 `run_all_tests.sh --list`）的全量误差体检，按现有阈值（`summary.pass`）筛选修正队列，并输出性能快照与可选前后对比报告。

默认行为：
- 默认模块/算子：`all`（即所有已启用算子）
- 默认仅复用已有二进制：`--no-build`
- 默认 perf 采样参数：`--warmup 5 --repeat 30`
- 默认输出目录：`data/reports/unit/audit`

常用命令：

```bash
# 1) 全量 accuracy 体检 + 失败队列 + 失败队列 perf 快照
scripts/test/audit_all_ops_precision.py --no-build

# 2) 仅审计指定模块/算子
scripts/test/audit_all_ops_precision.py \
  --modules wavelets,spectral \
  --operators cwt,stft \
  --no-build

# 3) 带构建执行（缺少二进制时可用）
scripts/test/audit_all_ops_precision.py --build --build-dir build

# 4) 修正后与旧基线对比（生成 perf delta 与修正说明）
scripts/test/audit_all_ops_precision.py \
  --compare-baseline data/reports/unit/audit/precision_baseline_<old_run_id>.csv \
  --fix-notes-file data/reports/unit/audit/fix_notes.csv \
  --no-build
```

默认输出文件：

- `data/reports/unit/audit/precision_baseline_<run_id>.csv`
- `data/reports/unit/audit/latest_precision_baseline.csv`
- `data/reports/unit/audit/precision_fix_queue_<run_id>.csv`
- `data/reports/unit/audit/latest_precision_fix_queue.csv`
- `data/reports/unit/audit/precision_perf_snapshot_<run_id>.csv`
- `data/reports/unit/audit/latest_precision_perf_snapshot.csv`
- `data/reports/unit/audit/precision_perf_delta_<run_id>.csv`
- `data/reports/unit/audit/latest_precision_perf_delta.csv`
- `data/reports/unit/audit/latest_precision_fix_report.md`

关键字段说明：

| 字段名 | 含义 |
|---|---|
| `status` | 运行状态：`passed` / `failed` / `infra_failed` |
| `summary_pass` | 来自 `latest_metrics.json` 的 `summary.pass` |
| `return_code` | `run_all_tests.sh` 执行返回码 |
| `max_rel_error` | 诊断用最大相对误差（ratio 小数） |
| `max_abs_error` | 诊断用最大绝对误差 |
| `rmse` | 均方根误差 |
| `cpu_median_ms` / `gpu_e2e_median_ms` / `gpu_kernel_median_ms` | 性能中位延迟 |
| `gpu_e2e_speedup` / `gpu_kernel_speedup` | 速度比（CPU/GPU） |
| `error_note` | 命令失败、metrics 缺失或解析失败时的诊断信息 |

说明：
- `precision_fix_queue_*.csv` 仅包含 `status=failed`（即已执行成功但阈值判定未通过）的算子；
- `infra_failed` 表示环境或执行链路问题（如缺失二进制），不直接进入修正队列。

`--fix-notes-file` 可选 CSV 头（用于增强 `latest_precision_fix_report.md`）：

```csv
module,operator,trigger_reason,fix_mechanism,impact_scope
wavelets,cwt,summary.pass=false due to ...,precompute kernel + fmaf accumulation,cpu/cuda wavelets only
```
