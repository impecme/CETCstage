# V5.5 全库 81 算子交付文档

## 阶段状态

- V5.5 性能、全库回归和既有契约 gate 状态为 `passed`。
- 本文新增要求复核结论为**部分完成**，不能仅凭既有 gate 宣称全部完成。
- 全库 benchmark：81/81 算子通过，失败 0。
- full 回归：12 个模块、81 个算子通过。
- Task smoke：2 个任务、14 个步骤通过，失败 0。
- 接口契约：81/81 通过；类型契约 schema 为 81/81 通过，但目标 dtype 尚未全部实现。
- 图件按模块组合压缩为 12 张，覆盖全部 81 个算子。

## 新增要求复核

原要求写“支持四种数据类型”，但随后列出了 FP32、FP16、INT32、INT16、INT8
五种类型；本表按五种实数类型复核。复数按官方澄清仅要求 `complex64`。

| 要求 | 结论 | 当前证据 | 未完成项 |
| --- | --- | --- | --- |
| README 写明代码目录结构 | 完成 | 根 `README.md` 的“代码目录结构”列出 `include/src/demo/tests/scripts/docs/data`，并说明声明、CPU、ZQ500 GPU 和测试的归属 | 无 |
| Task1/Task2 的计算步骤使用 GPU，即使 CPU 更快 | 完成 | 两任务均有 GPU pipeline；最终 task smoke 为 2 个任务、14 个计算步骤，失败 0 | 小规模步骤 GPU 可能慢于 CPU，这是固定开销，不影响“必须使用 GPU”的要求 |
| 每个任务计算步骤调用算子库公共实现 | 部分完成 | Task1 的 6 个计算步骤均为 `public`；Task2 的 filter、correlate、spectrogram、CWT 等步骤调用了公共算子 | Task2 仍有 7 个 `mixed` 步骤和 1 个 `private` 步骤；demod GPU 使用 task-local batched score，measurement conversion 为 private，Kalman GPU pipeline 也未完全切换到公共接口 |
| 每一步独立统计 CPU/GPU 时间 | 部分完成 | 14 个计算步骤均进入 step report；大部分步骤有独立 CPU/GPU E2E 时间 | `measurement_conversion` 时间合并进 Kalman；两任务 signal generation 未作为计算步骤单独计时；`gpu_kernel_ms` 仍为 pending |
| 每一步进行精度验证 | 部分完成 | 最终 step report 中 14 步有 11 步提供数组/数值误差；Task1/Task2 分别为 5/6、6/8 | Task2 demod 没有保留 CPU/GPU 输出用于误差；measurement conversion 精度合并；final detection 和 Kalman 使用业务指标而非逐点 CPU/GPU 误差 |
| 每个算子独立封装，按类别集中实现和声明 | 完成 | 81 个算子按 12 个模块组织；声明在 `include/cusignal/<module>/`，CPU/GPU 分别在 `src/cpu`、`src/zhongkexin` | 无 |
| 算子声明注释说明功能及输入输出 | 完成 | interface audit 检查 81 个算子的声明和 Doxygen，81/81 passed | 无 |
| 每个算子 CPU/GPU 实现对应 | 完成 | interface audit 检查声明、CPU、GPU 三方映射，81/81 passed | 无 |
| 每个算子独立测试并统计性能 | 完成 | 注册表 81 个独立测试入口；all81 benchmark 81/81 passed；full 回归 81/81 passed | 无 |
| 建议使用 template 保证类型通用、减少重复 | 部分完成 | `core/types.hpp` 提供 `Signal<T>`、`Array<T>`、device container 和 dtype traits；部分波形 API 使用模板 | 多数公开算子仍以具体 FP32/complex64 重载为主；该项是建议，但当前实现不足以证明五类 dtype 通用 |
| CUDA 11.7 Runtime/Driver 差异适配 | 项目使用范围完成 | 三份源表共解析 900 行、830 个唯一 API；项目使用 39 个 API，禁止项命中 0、未解析 0；compile/runtime/forbidden scan 均通过 | 兼容矩阵仍有 489 行标记 `runtime_pending`，因此不能解释为实现或运行验证了全部 CUDA 11.7 API |
| BLAS/FFT/DNN/SOLVER/SPARSE/RAND 兼容 | 完成 | ZQ500 runtime probe 实际创建并销毁六库 handle，执行 FFT；容器 CTest passed | 结论限于项目适配和安全探针，不代表覆盖各库所有 API/数据类型 |
| 使用 CMake 构建 | 完成 | 顶层 `CMakeLists.txt`、模块 CMake 和 `dlcc -x cuda --cuda-gpu-arch=dlgput64` 路径已通过容器构建 | 无 |
| 支持 FP32、FP16、INT32、INT16、INT8 | 未完成 | 类型契约已定义 13 类策略、81 个算子和合法/禁止类型；FP32 与 complex64 主路径已通过 | 按契约 `current_types` 对比目标类型，70 个算子仍缺 FP16；6 个算子仍缺 INT16/INT8；3 个算子仍缺 INT32。类型 gate 的 passed 只代表契约合法，不代表目标 dtype 已实现 |

因此，当前可以确认**工程结构、81 算子 CPU/GPU 对应、独立测试、CMake 和
ZQ500 项目使用范围兼容已经完成**；Task2 逐步公共化/精度覆盖和五类实数的
实际实现仍需继续，属于第五阶段未关闭项。

## 关键创新与最佳优化

| 项目 | 核心创新 | 优化前 | 优化后 | 结果 |
| --- | --- | ---: | ---: | ---: |
| `filtering/filtfilt` | 将二阶单行 BA 滤波转换为单节 SOS，正反向复用 GPU prefix scan | 909.94 ms | 0.679 ms | 耗时降低约 1340×，为本阶段最大降幅 |
| `filtering/lfilter` | BA→SOS fast path，复用并行 prefix scan，保留通用高阶 fallback | 455.17 ms | 0.359 ms | 耗时降低约 1268× |
| `windows/cosine` 等窗口 | 直接写最终输出，移除通用分发、extended workspace 和冗余 copy | 约 52.3 ms | 约 0.25 ms | `cosine` 降低约 209×，多个窗口进入亚毫秒级 |
| `spectral/periodogram` | 实数单边谱改用 R2C FFT，并融合 constant detrend 与 PSD 输出 | 72.91 ms | 0.669 ms | 耗时降低约 109× |
| `filtering/wiener` | 16×16 shared-memory tiled kernel 复用重叠邻域 | 214.44 ms | 3.50 ms | 耗时降低约 61× |
| `radartools/mvdr` | 小传感器 direct triangular covariance、block mean reduction 和 8×8 单 kernel solve | E2E 52.48 ms；kernel 42.12 ms | E2E 11.17 ms；kernel 0.847 ms | E2E 降低 4.7×，kernel 降低约 49.7× |
| `spectral/coherence` | 共享 x/y FFT，一次融合计算 Pxx/Pyy/Pxy 和 coherence | 5.27 ms | 0.751 ms | 耗时降低约 7× |
| Task2 pipeline | 将 validation-only 谱图移出 pipeline timing，并逐步融合 correlate、spectrogram、CWT 等 GPU helper | L3 曾约 3553 ms | L3 最终约 25 ms | 修正计时口径并显著降低端到端耗时 |

最终 all81 终测中，实际 CPU/GPU E2E 加速比最高的是 `wavelets/cwt`
（约 215×），其次为 `windows/kaiser`（约 196×）和 `filtering/wiener`
（约 194×）。这些是最终 CPU/GPU 对比；上表“耗时降低倍数”是优化前后 GPU
版本对比，两者口径不同。

## 终测报告

第五阶段报告目录已清理为“终测数据 + gate 汇总 + 模块聚合”的结构，
不再保留逐轮 probe 和逐算子明细目录。当前 `data/reports/` 下只保留
`demo/`、`unit/`、`zhongkexin/` 三类报告入口。

| 内容 | 路径 |
| --- | --- |
| 统一汇总 | `data/reports/zhongkexin/v5_5_final/summary.json`、`summary.md` |
| Stage4 与显存摘要 | `data/reports/zhongkexin/v5_5_final/stage4_summary.json`、`gpu_memory_summary.json` |
| 任务 smoke | `data/reports/zhongkexin/v5_5_final/task_smoke.json` |
| 接口审计 | `data/reports/zhongkexin/v5_5_final/interface_audit.json`、`interface_audit.md` |
| 类型契约 | `data/reports/zhongkexin/v5_5_final/type_contracts.json`、`type_contracts.md` |
| 81 算子性能明细 | `data/reports/unit/benchmarks/v5_5_final/latest_all_ops_scale_benchmark.csv` |
| 性能简报 | `data/reports/unit/benchmarks/v5_5_final/latest_report.md` |
| 组合图件 | `data/reports/unit/benchmarks/v5_5_final/figures/` |
| 模块回归聚合 | `data/reports/unit/<module>/latest_metrics.json`、`latest_cases.csv`、`latest_summary.md` |
| 任务终测摘要 | `data/reports/demo/latest_task_demo_report.json`、`latest_task_demo_report.md` |
| 任务分步报告 | `data/reports/demo/task1_radar/`、`data/reports/demo/task2_features/` 下的 `latest_*` |

`data/reports/unit/<module>/` 中的 `latest_*` 文件是 full 回归输入，由 gate
汇总读取。逐算子 `data/reports/unit/<module>/<operator>/` 明细和逐轮优化
probe 不属于终测交付，已移出代码库。报告目录结构说明见
`data/reports/README.md`。

## 终测结果

- all81 最大 GPU E2E 项为 `radartools/ambgfun`，约 167.8 ms。
- 其次为 `spectral/lombscargle`，约 12.5 ms；`radartools/mvdr` 约 11.1 ms。
- GPU 显存峰值 2453 MiB，最大利用率 100%。
- V5.5 重点优化后的 `lfilter`、`filtfilt`、`periodogram`、`coherence` 和窗口生成路径均通过终测。

## 汇总复现

```bash
cd /CETC
source /zq500/sdk/env.sh

python3 scripts/platform/summarize_v5_5_gate.py
cat data/reports/zhongkexin/v5_5_final/summary.json
cat data/reports/zhongkexin/v5_5_final/summary.md
```

汇总脚本校验 all81 benchmark、模块 full 回归、任务 smoke、接口/类型契约和
12 张模块组合图；任一门禁失败时返回非零状态。
