# V5 性能优化计划索引

## 总目标

V5 在 CPU reference 与中科芯 ZQ500 GPU 正确性不退化的前提下，完成工程规范、平台兼容、任务性能和全库 81 算子优化。性能结论必须同时具备耗时、误差、显存/cache 和复现证据。

总计划见 `plans/V5_0_plan.md`，最终结论见 `final_summary.md`。

## 阶段划分

| 阶段 | 计划 | 交付文件 | 状态 | 关闭门禁 |
| --- | --- | --- | --- | --- |
| V5.1 | `plans/V5_1_plan.md` | `docs/submission/READMEV5_1.md` | 已完成 | cache、显存和 benchmark schema 可复现 |
| V5.2 | `plans/V5_2_plan.md` | `docs/submission/READMEV5_2.md` | 已完成 | 目录、81 算子契约、类型矩阵和完整平台兼容审计完成 |
| V5.3 | `plans/V5_3_plan.md` | `docs/submission/READMEV5_3.md` | 已完成 | 两任务每步调用算子库，27 个依赖算子和逐步计时/精度闭环 |
| V5.4 | `plans/V5_4_plan.md` | `docs/submission/READMEV5_4.md` | 已完成 | 核心 53/53 完成规范化、独立测试和性能结论 |
| V5.5 | `plans/V5_5_plan.md` | `docs/submission/READMEV5_5.md` | 已完成 | 全库 81/81、任务步骤 schema v2、类型覆盖和平台最终验收完成 |

## 当前执行点

- 当前阶段：V5 已关闭；第六版规划独立放在 `docs/performance/v6_0/`。
- 已完成基线：V5.1 可观测性、cache 统计和整卡显存采样。
- 已提前完成：`filtering/wiener` 二维 shared-memory tiled 快路径，归入 V5.4 核心 53。
- V5.4 收口：`v5_4_gate_latest` 已通过，核心 53/53、模块回归、任务 smoke、接口/类型契约和组合图件均通过。
- 下一门禁：无。V5 目录不再记录第六版执行过程。

## 当前执行队列

1. `V5.2-01`：已关闭；四集合和 81 行契约骨架通过宿主机及容器验证。
2. `V5.2-02`：已关闭；接口、实现、独立测试和 Doxygen 容器审计 81/81 通过。
3. `V5.2-03`：已关闭；五种实数和 complex64 的 CTest 及直接运行通过。
4. `V5.2-04`：已关闭；81 条类型契约通过容器校验。
5. `V5.2-05`：已关闭；三个复赛表通过容器复验。
6. `V5.2-06`：已关闭；编译、七项平台类别运行和禁止扫描通过。
7. `V5.2-07`：已关闭；81/81 accuracy 和全部阶段门禁通过。
8. `V5.3-01`：已关闭；16 个任务步骤映射通过容器复验。
9. `V5.3-02`：已关闭；两任务 14 条统一步骤报告通过。
10. `V5.3-03`：已关闭；Task1 公共算子化和独立测试通过。
11. `V5.3-04`：已关闭；Task2 优化链条、L1-L6 稳定复验和两任务联合 smoke 通过。
12. `V5.4-01`：已关闭；core53 L6 基线和当前优化批次收口通过。
13. `V5.4-03`：已关闭；P0/P1 热点批量优化已完成，收益记录见台账 V5-0031 至 V5-0047。
14. `V5.4-04`：已关闭；任务 smoke、接口审计和类型契约复核通过。
15. `V5.4-05`：已关闭；受影响模块 full 回归通过。
16. `V5.4-06`：已关闭；阶段关闭验证与交付文档收口通过。
17. `V5.5-01`：已关闭；扩展 28、all81、任务、类型和平台最终验收完成。

V5.5 已关闭。第六版规划和后续执行记录独立维护在 `docs/performance/v6_0/`。

### V5.2-01 已关闭命令

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/test/run_all_tests.sh --list > /tmp/v5_2_all81.tsv

python3 scripts/test/validate_operator_sets.py \
  --registry /tmp/v5_2_all81.tsv \
  --sets scripts/test/operator_sets.json \
  --summary-json /tmp/v5_2_operator_sets_summary.json

for name in task27 core53 extended28 all81; do
  printf '%s=' "$name"
  python3 scripts/test/validate_operator_sets.py \
    --registry /tmp/v5_2_all81.tsv \
    --sets scripts/test/operator_sets.json \
    --list-set "$name" | wc -l
done

cat /tmp/v5_2_operator_sets_summary.json
```

实测计数为 27、53、28、81，summary 的 `status`、`source_path_check` 均为 `passed`。该命令作为 V5.2-01 复现入口保留。

### V5.2-02 容器命令

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/test/run_all_tests.sh --list > /tmp/v5_2_all81.tsv

python3 scripts/test/audit_operator_interfaces.py \
  --registry /tmp/v5_2_all81.tsv \
  --sets scripts/test/operator_sets.json \
  --output-dir data/reports/zhongkexin/v5_2_interface_audit \
  --contract-markdown /tmp/v5_2_operator_contract_inventory.md

python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path(
    "data/reports/zhongkexin/v5_2_interface_audit/latest_interface_audit.json"
).read_text())
print(json.dumps(payload["summary"], indent=2))
PY
```

2026-06-21 容器实测为 `operator_count=81`、`passed_count=81`、`failed_count=0`、`status=passed`。该命令作为 V5.2-02 复现入口保留。

### V5.2-03 容器命令

```bash
cd /CETC
source /zq500/sdk/env.sh
cmake -S . -B build-zx \
  -DCMAKE_BUILD_TYPE=Release \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCMAKE_CXX_COMPILER="$(command -v dlcc)"
cmake --build build-zx --target cusignal_type_contract_tests --parallel
ctest --test-dir build-zx -R '^cusignal_type_contract$' --output-on-failure
./build-zx/tests/unit/core_types/cusignal_type_contract_tests
```

预期 CTest 1/1 通过，并输出 `[core/types] PASS real_types=5 complex_types=1`。

2026-06-21 容器实测 CTest 1/1 通过，直接运行输出与预期一致，本工作包已关闭。

### V5.2-04 容器命令

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/test/run_all_tests.sh --list > /tmp/v5_2_all81.tsv
python3 scripts/test/validate_operator_type_contracts.py \
  --registry /tmp/v5_2_all81.tsv \
  --contracts scripts/test/operator_type_contracts.json \
  --output-dir data/reports/zhongkexin/v5_2_type_contracts \
  --contract-markdown /tmp/v5_2_operator_type_contracts.md
python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path(
    "data/reports/zhongkexin/v5_2_type_contracts/latest_type_contracts.json"
).read_text())
print(json.dumps(payload["summary"], indent=2))
PY
```

预期为 81 个算子、14 个类型策略、五种实数、复数仅 complex64，且
`compatibility_gap_count=0`。`current_types` 记录原生直达类型，
`compatibility_types` 记录 FP32/complex64 中间计算、整数扩展累加或受控转换
覆盖的兼容路径。原 cuSignal complex64 对齐清单应显示 21 个公共契约已支持项；
另有 8 个 filtering/resampling dtype-preserving 复数扩展路径不属于当前赛题强制项。

当前类型契约应为 `status=passed`、81 个算子、14 个策略、8 个整数相关算子和 21 个 complex64 相关算子。

### V5.2-05 容器命令

根 `README.md` 的“V5.2-05 当前阶段验证”是唯一执行入口。预期完整覆盖 900 个非空源行、816 个 API 行和 830 个唯一 API；本阶段生成的 315 项禁止清单将在 V5.2-06 扫描项目引用。

2026-06-21 容器结果全部符合预期，本工作包已关闭。

### V5.2-06 容器命令

根 `README.md` 的“V5.2-06 当前阶段验证”是唯一执行入口。宿主机已确认三个 CMake target 均可构建，六类科学计算库可链接，315 项禁止 API 扫描无命中；容器负责执行安全运行探针并复验 CTest。

2026-06-21 容器两个 CTest 2/2 通过，Runtime、FFT、BLAS、DNN、SOLVER、SPARSE、RAND 均通过，禁止引用和未解析 API 均为 0，本工作包已关闭。

### V5.2-07 容器命令

执行根 `README.md` 的“V5.2-07 当前阶段验证”。统一脚本完成全部静态门禁、三个 CTest 和 81 算子 accuracy，并输出 `data/reports/zhongkexin/v5_2_gate_latest/summary.{json,md}`。

2026-06-21 容器 `operator_accuracy_passed_count=81`，全部 8 项 checks 为 true，V5.2 阶段关闭。

### V5.3-01 容器命令

执行根 `README.md` 的“V5.3-01 当前阶段验证”。该审计只冻结当前事实和迁移清单，不修改任务数值路径。

2026-06-21 容器结果为 2 个任务、16 个步骤、11 个迁移步骤，状态 passed，本工作包已关闭。

### V5.3-02 容器命令

执行根 `README.md` 的“V5.3-02 当前阶段验证”。两任务继续保留历史报告，同时新增相同 schema 的 `latest_step_metrics.csv/json/md`；不可用的 kernel 和误差字段必须为 null/available=false。

2026-06-22 容器两任务和 14 条报告 schema 均通过，本工作包已关闭。Task2 `spectrogram` 约 3.5 秒热点保留到 V5.3-04/06，不调整历史阈值。

### V5.3-03 容器命令

执行根 `README.md` 的“V5.3-03 当前阶段验证”。三个 pipeline helper 有独立 CTest，但不改变赛题固定的 81 算子注册表数量。

## 类型原则

- 正式实数类型：FP32、FP16、INT32、INT16、INT8，按算子语义确定适用范围。
- 复数只支持 `complex64`，CPU 为 `std::complex<float>`，GPU 为 `cuFloatComplex`/`cuComplex`。
- 不实现 FP64、`complex128`、FP16 复数或整数复数。
- 纯浮点算子不强制实现整数版本，但必须记录不适用理由并验证拒绝行为。
- FP16 只表示实数半精度路径；默认复数输出算子只实现 `complex64`，不实现半精度复数。
- 适用 FP16 的实数算子允许内部使用 FP32 中间累加；整数兼容只针对原始语义允许的算子，不能用简单 cast 代替整数语义。
- 当前原生直达类型与兼容路径分开记录；V5.5 当前门禁要求目标适用类型全部落入 `compatibility_types`，但不要求每个目标 dtype 都有独立原生 kernel。

## 执行规则

1. 未满足当前阶段关闭门禁，不进入下一阶段。
2. 计划能力与已实现能力分开记录，不允许把“待实现”写成“已支持”。
3. 核心算子修改至少通过单算子 full；阶段关闭必须通过对应模块或任务回归。
4. 所有措施和结果写入 `optimization_change_log.md`，不得只保留在终端日志中。
5. 辅助智能体并行分析，主智能体统一修改、同步、记录和发布验证命令。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| `agent_collaboration.md` | 智能体职责、文件所有权和阶段协作流程 |
| `final_summary.md` | V5 最终验收、类型兼容、任务步骤和报告收束结论 |
| `optimization_change_log.md` | 优化措施、工程变更、验证证据和状态台账 |
| `operator_optimization_matrix.md` | 81 算子范围、类型/接口/测试契约和性能状态 |
| `plans/V5_0_plan.md` 至 `plans/V5_5_plan.md` | V5 总计划与各阶段门禁 |

生成型审计长表不再放在 V5 目录中，正式结论统一汇总到 `final_summary.md` 和 `data/reports/zhongkexin/v5_5_final/summary.*`。
