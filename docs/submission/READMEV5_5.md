# V5.5 全库 81 算子交付文档

## 阶段状态

- V5.5 全库回归、任务 smoke、接口契约、类型契约和 dtype 覆盖均为 `passed`。
- 全库 benchmark：81/81 算子通过，失败 0。
- full 回归：12 个模块、81 个算子通过。
- Task smoke：2 个任务、14 个计算步骤通过，失败 0。
- 任务步骤审计：14 个计算步骤均有公共算子链路，计时缺口 0，精度缺口 0。
- 类型兼容：五种实数类型 FP32、FP16、INT32、INT16、INT8 和 `complex64` 均有覆盖证据，`operator_dtype_missing_edges=0`。
- 图件按模块组合压缩为 12 张，覆盖全部 81 个算子。

## 新增要求复核

复数类型按官方澄清仅要求 `complex64`；默认复数输出不要求 FP16 复数。

| 要求 | 结论 | 当前证据 | 说明 |
| --- | --- | --- | --- |
| README 写明代码目录结构 | 完成 | 根 `README.md` 的“代码目录结构”说明 `include/src/demo/tests/scripts/docs/data` 分工 | 已按声明、CPU、ZQ500 GPU、测试、报告分层描述 |
| Task1/Task2 的计算步骤使用 GPU，即使 CPU 更快 | 完成 | 两任务均有 GPU pipeline；任务 smoke 2 个任务、14 个计算步骤、失败 0 | 小规模步骤 GPU 可能慢于 CPU，属于固定启动/搬运开销，不影响使用 GPU 的要求 |
| 每个任务计算步骤调用算子库公共实现 | 完成 | `task_step_audit` 显示 14/14 计算步骤具备公共算子链路 | Task helper 只承担批处理、投影、归一化、融合和任务编排，不替代核心公共算子 |
| 每一步独立统计 CPU/GPU 时间 | 完成 | 14 个计算步骤均进入 step report；`measurement_conversion` 已从 Kalman 中拆出独立 CPU/GPU E2E 时间 | 当前任务报告以端到端阶段时间为正式统计口径 |
| 每一步进行精度验证 | 完成 | schema v2 要求 14 个计算步骤均有误差或检测向量校验，容器复验 failure_count=0 | Task2 demod、measurement_conversion、Kalman 已补 CPU/GPU 对照误差 |
| 每个算子独立封装，按类别集中实现和声明 | 完成 | 81 个算子按 12 个模块组织；声明在 `include/cusignal/<module>/`，CPU/GPU 分别在 `src/cpu`、`src/zhongkexin` | 目录结构与 CMake target 对齐 |
| 算子声明注释说明功能及输入输出 | 完成 | interface audit 检查 81 个算子的声明和 Doxygen，81/81 passed | 无额外限制 |
| 每个算子 CPU/GPU 实现对应 | 完成 | interface audit 检查声明、CPU、GPU 三方映射，81/81 passed | 无额外限制 |
| 每个算子独立测试并统计性能 | 完成 | 注册表 81 个独立测试入口；all81 benchmark 81/81 passed；full 回归 81/81 passed | 性能报告按模块压缩图件，避免逐算子图件污染仓库 |
| 建议使用 template 保证类型通用、减少重复 | 完成 | `core/types.hpp` 提供 `Signal<T>`、`Array<T>`、device container 和 dtype traits；类型测试覆盖五种实数和 complex64 roundtrip | 当前满足接口兼容与复用要求；进一步把所有公开重载改成模板属于 V6 可维护性优化，不作为 V5.5 缺口 |
| CUDA 11.7 Runtime/Driver 差异适配 | 完成 | 三份源表共解析 900 行、830 个唯一 API；项目使用 39 个 API，禁止项命中 0、未解析 0；compile/runtime/forbidden scan 均通过 | 结论限定为本项目实际使用 API 的兼容适配，不宣称覆盖 CUDA 11.7 全部 API |
| BLAS/FFT/DNN/SOLVER/SPARSE/RAND 兼容 | 完成 | ZQ500 runtime probe 创建并销毁六库 handle，并执行 FFT；容器 CTest passed | 结论限定为项目依赖与安全探针 |
| 使用 CMake 构建 | 完成 | 顶层 `CMakeLists.txt`、模块 CMake 和 `dlcc -x cuda --cuda-gpu-arch=dlgput64` 路径已通过容器构建 | 无额外限制 |
| 支持 FP32、FP16、INT32、INT16、INT8 | 完成 | 类型契约 81/81 passed；dtype 覆盖 `operator_dtype_missing_edges=0`；`float16 69/69`、`float32 78/78`、`int32 7/7`、`int16 5/5`、`int8 5/5`、`complex64 21/21` | 兼容允许 FP16/整数经 FP32 中间计算、整数扩展累加或受控转换实现；不等同于每个 dtype 都有独立原生 kernel |

## complex64 说明

类型契约已登记原 cuSignal/SciPy 语义中涉及复数输出、复数输入或复数
dtype-preserving 的算子。当前公共契约已支持 21 个 `complex64` 对齐项，包括
`chirp`、`hilbert/hilbert2`、`firfilter`、`freq_shift`、`channelize_poly`、
`stft/csd/spectrogram/istft`、`morlet/morlet2/cwt`、`correlate/correlate2d`、
`fm_demod`、`cmplx_sort` 和雷达复数链路。

V5.5 的复数交付口径为：默认复数输出只要求 `complex64`，不要求 FP16 复数、
`complex128` 或整数复数。部分原 cuSignal 的 filtering/resampling
dtype-preserving 复数扩展语义不属于本阶段赛题强制项；Task2 filter 主路径已使用公共
`filtering::firfilter` complex64 接口，demo helper 只负责实部投影和任务级打分。

## 关键创新与最佳优化

| 项目 | 核心创新 | 优化前 | 优化后 | 结果 |
| --- | --- | ---: | ---: | ---: |
| `filtering/filtfilt` | 将二阶单行 BA 滤波转换为单节 SOS，正反向复用 GPU prefix scan | 909.94 ms | 0.679 ms | 耗时降低约 1340x |
| `filtering/lfilter` | BA 到 SOS fast path，复用并行 prefix scan，保留通用高阶 fallback | 455.17 ms | 0.359 ms | 耗时降低约 1268x |
| `windows/cosine` 等窗口 | 直接写最终输出，移除通用分发、extended workspace 和冗余 copy | 约 52.3 ms | 约 0.25 ms | `cosine` 降低约 209x，多个窗口进入亚毫秒级 |
| `spectral/periodogram` | 实数单边谱改用 R2C FFT，并融合 constant detrend 与 PSD 输出 | 72.91 ms | 0.669 ms | 耗时降低约 109x |
| `filtering/wiener` | 16x16 shared-memory tiled kernel 复用重叠邻域 | 214.44 ms | 3.50 ms | 耗时降低约 61x |
| `radartools/mvdr` | 小传感器 direct triangular covariance、block mean reduction 和 8x8 单 kernel solve | E2E 52.48 ms；kernel 42.12 ms | E2E 11.17 ms；kernel 0.847 ms | E2E 降低 4.7x，kernel 降低约 49.7x |
| `spectral/coherence` | 共享 x/y FFT，一次融合计算 Pxx/Pyy/Pxy 和 coherence | 5.27 ms | 0.751 ms | 耗时降低约 7x |
| Task2 pipeline | 移除 validation-only 计时污染，并逐步融合 correlate、spectrogram、CWT 等 GPU helper | L3 曾约 3553 ms | L3 最终约 25 ms | 修正计时口径并显著降低端到端耗时 |

最终 all81 终测中，实际 CPU/GPU E2E 加速比最高的是 `wavelets/cwt`
（约 215x），其次为 `windows/kaiser`（约 196x）和 `filtering/wiener`
（约 194x）。这些是最终 CPU/GPU 对比；上表“耗时降低倍数”是优化前后 GPU
版本对比，两者口径不同。

## 交付报告

`data/reports/` 只保留精简交付证据和机器可读摘要，完整容器取回缓存和调优日志统一放在
仓库外 `/home/usr_04/CETC_garbage/`，不纳入代码库。报告目录结构说明见
`data/reports/README.md`。

| 内容 | 路径 |
| --- | --- |
| dtype 兼容最终摘要 | `data/reports/zhongkexin/v5_5_dtype_compat_final/README.md` |
| dtype 覆盖审计 | `data/reports/zhongkexin/v5_5_dtype_compat_final/dtype_test_coverage.json`、`dtype_test_coverage.md` |
| 类型契约 | `data/reports/zhongkexin/v5_5_type_contracts/latest_type_contracts.json`、`latest_type_contracts.md` |
| 任务步骤审计 | `data/reports/zhongkexin/v5_3_task_step_audit/latest_task_step_audit.json` |
| filtering dtype 复跑 | `data/reports/unit/filtering/latest_metrics.json`、`latest_cases.csv`、`latest_summary.md` |
| coherence FP16 复跑 | `data/reports/unit/spectral/coherence/latest_metrics.json`、`latest_cases.csv`、`latest_summary.md` |

## 终测结果

- all81 最大 GPU E2E 项为 `radartools/ambgfun`，约 167.8 ms。
- 其次为 `spectral/lombscargle`，约 12.5 ms；`radartools/mvdr` 约 11.1 ms。
- GPU 显存峰值约 2453 MiB，最大利用率 100%。
- V5.5 重点优化后的 `lfilter`、`filtfilt`、`periodogram`、`coherence` 和窗口生成路径均通过终测。
- 最新任务步骤 strict schema v2 复验通过：14 个计算步骤均有独立 CPU/GPU 时间和精度校验。

## 复现入口

```bash
cd /CETC
source /zq500/sdk/env.sh

scripts/test/run_all_tests.sh --list > /tmp/v5_5_all81.tsv

python3 scripts/test/audit_task_steps.py \
  --contracts scripts/test/task_step_contracts.json \
  --output-dir data/reports/zhongkexin/v5_3_task_step_audit \
  --summary-markdown docs/performance/v5_0/task_step_audit.md

python3 scripts/test/audit_dtype_test_coverage.py \
  --registry /tmp/v5_5_all81.tsv \
  --contracts scripts/test/operator_type_contracts.json \
  --output-dir data/reports/zhongkexin/v5_5_dtype_compat_final \
  --summary-markdown data/reports/zhongkexin/v5_5_dtype_compat_final/dtype_test_coverage.md
```

完整性能终测在容器中使用 `OPERATOR_SET=all81` 的 Stage4 命令运行；中间 probe、
完整日志和大体积图件不进入仓库，只保留上述精简报告。
