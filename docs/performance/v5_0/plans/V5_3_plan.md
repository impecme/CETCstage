# V5.3 Task1/Task2 与 27 个依赖算子计划

## 状态与目标

- 状态：进行中；V5.2 已关闭；对应交付：`docs/submission/READMEV5_3.md`。
- 目标：任务每一步均调用公共算子库，逐步记录 CPU/GPU 时间和精度，并优化两任务与 27 个依赖算子。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V5.3-01 | 任务步骤审计 | Task1/Task2 步骤与公共算子映射 | 每个计算步骤标明公共算子或待迁移私有函数 |
| V5.3-02 | 统一步骤报告 | 公共 timing/error helper 和 JSON/CSV schema | 两任务使用同一统计实现 |
| V5.3-03 | Task1 算子化 | 私有计算迁入模块、独立测试 | Demo 只保留编排，Task1 L1-L6 通过 |
| V5.3-04 | Task2 算子化 | 私有计算迁入模块、独立测试 | Demo 只保留编排，Task2 L1-L6 通过 |
| V5.3-05 | 任务与 task27 基线 | L1-L6、27 算子稳定 baseline | 报告字段完整且同口径 |
| V5.3-06 | 热点逐项优化 | 每热点前后数据和回归 | correctness 通过且收益稳定，否则回滚 |
| V5.3-07 | 阶段全量回归 | task27 + 两任务报告 | 27/27 与两任务全部关闭 |

## 步骤审计与公共化

V5.3-01 固定入口：

```bash
cd /CETC
python3 scripts/test/audit_task_steps.py \
  --contracts scripts/test/task_step_contracts.json \
  --output-dir data/reports/zhongkexin/v5_3_task_step_audit \
  --summary-markdown /tmp/v5_3_task_step_audit.md
```

预期 `status=passed`、2 个任务、16 个总步骤、14 个计算步骤。审计通过表示映射完整，不表示 11 个 mixed/private 步骤已经公共化。

- Task1 至少审计脉冲压缩、Doppler、fftshift、power map、CA-CFAR、ambgfun 和最终检测。
- Task2 至少审计信号生成、滤波、解调、相关、spectrogram、CWT、特征融合、峰值、测量转换和 Kalman。
- `power_map`、`fftshift`、归一化、特征融合等任务私有函数必须迁入语义匹配模块，并补 CPU/GPU 同签名接口与独立测试。
- Demo 禁止直接 launch 业务计算 kernel；只允许输入构造、算子调用、计时、报告、业务 gate 和文件输出。

## 步骤报告接口

统一记录结构固定包含：`task`、`step`、`operator`、`input_shape`、`output_shape`、`input_dtype`、`output_dtype`、`cpu_ms`、`gpu_e2e_ms`、`gpu_kernel_ms`、两类 speedup、四类误差和 `pass`。

- complex64 增加 `real_error`、`imag_error`、`overall_error`。
- GPU E2E 包含该步骤必要传输；kernel 使用 event 计时；总时间由同一批步骤求和。
- 即使 CPU 更快也必须执行 GPU 路径，不允许按规模选择 CPU 替代 GPU。
- 输出固定为 `latest_step_metrics.csv`、`latest_step_metrics.json` 和任务 Markdown 表。

V5.3-02 验证入口：

```bash
cd /CETC
scripts/test/run_task_demos.sh --build-dir build-zx --build --repeat 1 --skip-timing-validation
python3 scripts/test/validate_task_step_reports.py \
  --report-root data/reports/demo \
  --output data/reports/zhongkexin/v5_3_step_reports_summary.json
```

不得用 E2E 时间填充缺失的 kernel 字段；未公共化步骤的不可用误差必须显式标记。该 smoke 跳过历史 timing gate，但保留实际耗时并登记热点，不得据此宣布性能通过。

## 基线命令

任务 L1-L6 基线：

```bash
cd /CETC
scripts/test/run_task_demos.sh \
  --no-build --scale-sweep --repeat 3 --require-visualization-deps
```

task27 快速基线：

```bash
cd /CETC
OPERATOR_SET=task27 \
RUN_TASK_SWEEP=0 \
BENCH_SCALE_LEVELS=6 \
BENCH_WARMUP=1 \
BENCH_REPEAT=3 \
BENCH_REPORT_MODE=concise \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/v5_3_task27_probe \
STAGE4_REPORT_ROOT=data/reports/zhongkexin/v5_3_task27_probe \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage5_3_task27_probe.log
```

稳定基线把 warmup/repeat 改为 5/30，输出目录改为 `v5_3_task27_baseline`，不得与 probe 混用加速比。

## 单热点执行模板

1. 从步骤耗时和 task27 CSV 选择一个热点，只修改一个算子或一个任务数据流主题。
2. 修改前保存同口径 baseline 行；修改后先跑该算子 full：

```bash
scripts/test/run_all_tests.sh \
  --platform ZHONGKEXIN --module <module> --operator <operator> \
  --case-set full --warmup 5 --repeat 30 \
  --build-dir build-zx --no-build --emit-report
```

3. 再跑受影响任务 L3；通过后跑任务 L1-L6。
4. `mixed_error`、业务 gate 或适用类型失败立即停止性能判断。
5. 收益低于重复运行波动、E2E 退化或显存无解释增长时回滚候选方案。

## 阶段关闭与回传

阶段关闭执行 task27 5/30 benchmark 和两个任务 L1-L6 repeat=5。用户回传 task27 CSV、两个任务 `latest_step_metrics.*`、scale report、validation、显存 summary 和日志。

关闭条件：任务计算步骤 100% 公共算子化；27/27 独立 full 和性能状态完整；逐步/总计时及精度字段完整；两任务 L1-L6 全部通过；`READMEV5_3.md` 和台账已更新。
