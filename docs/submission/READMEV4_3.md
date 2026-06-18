# V4.3 中科芯第三阶段交付文档

## 版本信息

- 版本名称：`V4.3 全量公开算子迁移`
- 交付日期：`2026-06-17`
- 当前状态：已关闭
- 对应计划：`docs/design/V4_3_plan.md`
- 全量矩阵：`docs/design/zhongkexin_full_operator_matrix.md`
- 修改台账：`docs/design/zhongkexin_migration_change_log.md`

## 版本目标

V4.3 将中科芯迁移范围从 V4.2 的 Task1/Task2 依赖算子扩展到项目公开算子测试注册表。版本关闭口径为 CPU reference + 容器内中科芯 ZQ500 GPU 双链路；NVIDIA 不再作为阶段关闭条件。

## 核心改动

- 新增 Stage3 统一入口：`scripts/platform/run_zhongkexin_stage3.sh`。
- 新增全量公开算子矩阵：`docs/design/zhongkexin_full_operator_matrix.md`。
- `scripts/test/run_all_tests.sh --platform ZHONGKEXIN` 自动加载 `/zq500/sdk/env.sh`，手工单算子复验和 Stage3 包装入口使用同一 SDK 环境。
- 原注释候选 28 条已纳入 active 注册表，当前 active accuracy 条目为 81 条。
- 中科芯 `spectral/csd` 禁用 R2C 快路径，改走已验证的 C2C 路径。
- 中科芯 `filtering/wiener` 修复自动噪声估计与局部窗口遍历，避免 `dlcc` 设备代码误处理无符号倒序循环。
- `radartools/mvdr` 与 `spectral/coherence` 的原候选测试 manifest 容差按 float32 CPU/reference 与 GPU/reference 误差校准。

## 解决的问题

- `dlcc was not found for ZHONGKEXIN build`：单算子入口已自动加载 SDK 环境。
- `filtering/wiener` accuracy 失败：修复局部统计 kernel 遍历后通过。
- `spectral/csd` accuracy 失败：中科芯路径改走 C2C 后通过。
- `radartools/mvdr`、`spectral/coherence` 原注释候选容差不可满足：校准 manifest 后单算子和完整 Stage3 均通过。

## 验证结果

容器内执行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage3.sh 2>&1 | tee stage3_accuracy.log
```

最终结果：

- 脚本版本：`diagnostics-20260617-stage3-full-ops-v2`
- 模块级：`12/12` 通过
- 算子级：`81/81` 通过
- 模块失败数：`0`
- 算子失败数：`0`
- 依赖准备：`cmake 3.22.1`、`dlcc /zq500/sdk/bin/dlcc`、SDK headers/libs、FFTW、Python modules 均满足

关键复验：

- `radartools/mvdr`：单算子 accuracy 通过，`cpu_gpu_error max_abs=3.404061e-04`，`rmse=2.374302e-04`。
- `spectral/coherence`：单算子 accuracy 通过，`cpu_gpu_error max_abs=4.758292e-02`，`rmse=7.193005e-03`。

## 交付产物

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| Stage3 完整日志 | `data/reports/zhongkexin/stage3_runs/20260617_110827/stage3_accuracy.log` | active 81 条完整验证日志 |
| 模块级报告 | `data/reports/zhongkexin/stage3_runs/20260617_110827/latest_full_operator_module_report.md` | 12 个模块全部通过 |
| 算子级报告 | `data/reports/zhongkexin/stage3_runs/20260617_110827/latest_full_operator_detail_report.md` | 81 个 active 算子全部通过 |
| `mvdr` 复验日志 | `data/reports/zhongkexin/stage3_runs/20260617_110827/stage3_mvdr.log` | `radartools/mvdr` 单算子通过 |
| `coherence` 复验日志 | `data/reports/zhongkexin/stage3_runs/20260617_110827/stage3_coherence.log` | `spectral/coherence` 单算子通过 |

## 完成判定

V4.3 已关闭：

- active 81 条公开算子 accuracy 全部通过。
- 原注释候选 28 条已纳入 active 验证，不再作为静默候选保留。
- 每个模块均有可复现的日志与模块/算子报告。
- CPU reference 与容器内中科芯 ZQ500 GPU 双链路可复现。
- 本阶段发现项已写入迁移台账。

## 遗留风险

- `csd` 和 `spectrogram` 均对中科芯 R2C 快路径做了 correctness 优先规避，V4.4 性能阶段需要评估是否恢复或优化 R2C 快路径。
- `wiener` 自动噪声估计当前在中科芯路径包含一次 D2H 标量拷贝，后续性能阶段可评估纯设备端 reduction。
