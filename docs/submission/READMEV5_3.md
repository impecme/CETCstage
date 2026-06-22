# V5.3 Task1/Task2 与依赖算子交付文档

## 版本信息

- 当前状态：进行中。
- 对应计划：`docs/performance/v5_0/plans/V5_3_plan.md`。
- 进入条件：V5.2 已关闭。

## 交付要求

- Task1/Task2 每个计算步骤均调用公共算子库。
- 任务私有算法完成公共 CPU/GPU 算子化和独立测试。
- 每步报告算子、shape、dtype、CPU/GPU 耗时、speedup 和精度。
- `complex64` 步骤报告实部、虚部和复数整体误差。
- 27/27 依赖算子有 full、性能和最终状态证据。
- 两任务 L1-L6 correctness、业务 validation、性能、显存和图件通过。

## 当前工作包

- `V5.3-01`：已关闭，Task1/Task2 步骤与公共算子映射审计通过。
- `V5.3-02`：已关闭，统一步骤报告 schema 和公共结构通过容器验证。
- `V5.3-03`：当前工作包，Task1 私有计算公共算子化。
- 宿主机审计覆盖 2 个任务、16 个总步骤和 14 个计算步骤，源码符号检查通过。
- 当前仅 3 个计算步骤完全公共化；8 个 mixed、3 个 private，共 11 个步骤进入迁移队列。
- V5.3-01 基线缺 2 个独立计时项和 5 个逐步精度项；V5.3-02 已补 Task1 power-map 误差，其余缺口显式标记。
- 审计交付：`docs/performance/v5_0/task_step_audit.md` 和 `scripts/test/task_step_contracts.json`。

## V5.3-02 实现

- 两任务共用 `demo/common/task_step_report.hpp` 中的 `StageTiming`、`ErrorMetrics`、`StepMetric` 和写出器。
- 新报告固定包含算子、shape、dtype、CPU、GPU E2E/kernel、speedup、四类误差、complex64 分量误差和 pass。
- 保留 `latest_stage_timings.csv` 与 `latest_metrics.json`，新增 `latest_step_metrics.csv/json/md`。
- 当前公共算子没有向任务暴露统一 kernel event 时间，因此 `gpu_kernel_ms` 为 null，并由 note 明确后续工作包。
- 首次容器运行确认 schema 14/14 通过，数值与业务检查通过；Task2 因 `spectrogram=3499.7 ms` 触发历史 150 ms timing gate。该热点保留原始数据，不调整阈值，schema smoke 使用显式 skip 后复验。
- 2026-06-22 使用显式 timing skip 复验，两任务均 PASS，14 条步骤 schema 和 11 条已有误差全部有效。

## V5.3-03 实现

- `fftshift_rows`、`power_map`、`detect_peak` 迁入公共 `radartools` CPU/ZQ500 GPU 接口。
- Task1 删除私有 `task1_radar_zx_gpu.*`，Demo 只调用公共算子并保留流程编排。
- 三个 helper 分别有独立 CTest；GPU 检测在设备执行并只回传标量结果。
- GPU helper 使用模块线程本地 workspace，检测结果 buffer 跨调用复用。
- Task1 6 个计算步骤已全部登记为 public；全局迁移步骤从 11 降至 8。
