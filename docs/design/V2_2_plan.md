# V2.2 `waveforms` 实现、验证与数据落盘方案

## Summary

- 本轮同时补齐 `waveforms` 的 CPU 与 GPU 真值实现，并恢复单算子验证链路。
- 公开 C++ API 保持不变；新增的是单测/runner 的报告输出约定、`data/` 目录职责和 `READMEV2_2.md` 文档口径。
- 单测根目录使用 `tests/unit/`，`waveforms` 下每个算子单独一个源文件；默认 `ctest` 只做断言，显式启用报告模式时才写 `data/reports/`。

## Implementation Changes

- 补齐 5 个算子真实实现：`chirp`、`gausspulse`、`sawtooth`、`square`、`unit_impulse`。
- CPU 版使用 C++17 双精度公式实现；GPU 版使用真实 CUDA kernel，host 侧负责输入拷贝、launch、同步与结果回传到现有 `std::vector` 容器。
- 继续沿用当前异常契约：非法参数直接抛异常，不用 NaN 静默吞错。
- 公开接口不新增类型；测试/runner 侧新增命令行入口约定：
  - `--emit-report`：写报告到 `data/reports`
  - `--case-set smoke|accuracy|perf|full`
  - `--warmup N`
  - `--repeat N`
  - `--verbose`
- `READMEV2_2.md` 明确说明：V2.2 新增真实 `waveforms` 实现、CPU/GPU 误差统计、性能统计、`tests/unit` 结构与 `data/` 目录职责。

## Verification And Measurement Flow

1. 每个算子 runner 从 case manifest 读取固定测试用例，优先用 `data/reference` 的小型基准，其次用 `data/generated` 的性能基准。
2. 对每个 case 先跑 CPU，再跑 GPU，保存两侧输出。
3. 误差输出分两层：
   - 主指标：`GPU vs CPU`，对应赛题“同 CPU 实现进行对比”。
   - 次指标：`CPU/GPU vs reference`，仅对存在黄金输出的 case 输出。
4. 误差指标统一为：`max_abs_error`、`max_rel_error`、`rmse`、`l2_error`、`exact_match`、`first_mismatch_index`。
5. CPU 性能用 `std::chrono::steady_clock` 统计端到端 API 延迟；默认 `warmup=5`、`repeat=30`。
6. GPU 性能同时统计两组值：
   - 主指标：GPU 端到端 API 延迟，包含 H2D、kernel、D2H、同步；用于和 CPU 算 speedup。
   - 次指标：GPU kernel-only 延迟，用 `cudaEvent` 记录，仅写入 JSON/CSV/Markdown，不作为主 speedup 指标。
7. 终端默认输出“算子级摘要”；`--verbose` 时再追加逐 case 明细。
8. 每个算子写自己的报告；`waveforms` 模块再汇总出模块级总表。

## Terminal Summary

- 每次 `--emit-report` 的终端摘要固定为 5 行：

```text
[waveforms/chirp] PASS  accuracy_cases=6  perf_cases=2
cpu_gpu_error : max_abs=2.1e-13  max_rel=4.7e-13  rmse=9.8e-14
cpu_perf_ms   : median=0.182  mean=0.188  p95=0.201
gpu_perf_ms   : e2e_median=0.093  kernel_median=0.012  p95=0.101  speedup=1.96x
reports       : data/reports/unit/waveforms/chirp/latest_summary.md
```

- 若存在 reference 误差，在第二行后追加一行 `reference_error`。
- 若有 case 失败，第一行改为 `FAIL`，并在末尾附失败 case id 列表。

## Data Layout

- 调整 `data/` 职责如下：

```text
data/
  reference/
    unit/waveforms/<op>/
      manifest.json
      input/
      expected/
  generated/
    unit/waveforms/<op>/
      manifest.json
      input/
      output_samples/
  reports/
    unit/waveforms/<op>/
      latest_summary.md
      latest_metrics.json
      latest_cases.csv
      history/<run_id>/
    unit/waveforms/
      latest_summary.md
      latest_metrics.json
      latest_cases.csv
```

- `data/reference`：尽量入库的小型固定基准输入和黄金输出，作为 correctness 基线。
- `data/generated`：中大样本性能输入、任务演示输入和可选示例输出；优先也入库，但单文件超过 `2 MB` 时只保留 manifest 与生成规则，不强制存整段数组。
- `data/reports`：只存统计结果、摘要和 artifact 路径/哈希，不重复存放大数组原始值。

## File Formats

- `latest_metrics.json`：完整机器可读报告，包含运行时间、git 信息、编译配置、GPU 名称、case 清单、误差指标、CPU 性能、GPU e2e 性能、GPU kernel 性能、引用到的 input/output artifact 路径与 SHA256。
- `latest_cases.csv`：逐 case 表格汇总。
  列固定为：`case_id,backend,metric_kind,samples,warmup,repeat,mean_ms,median_ms,p95_ms,min_ms,max_ms,std_ms,max_abs_error,max_rel_error,rmse,l2_error,exact_match`.
- `latest_summary.md`：人读摘要，包含环境、通过情况、误差表、CPU/GPU 性能表、speedup、artifact 路径。
- `history/<run_id>/`：保留本次快照；`latest_*` 始终覆盖为当前最新结果，便于 README 和答辩材料直接引用。

## Input/Output Planning

- correctness case 不依赖随机数；全部使用固定参数或固定 `seed=20260404` 的生成配方。
- 1D 实数输入/输出用 `csv`，列为 `index,value`。
- 1D 复数输出用 `csv`，列为 `index,real,imag`。
- N 维输出统一展平存 `csv`，shape 写在 `manifest.json`。
- 多返回算子按 channel 分文件保存，例如 `signal`、`quadrature`、`envelope`；命名规则统一为 `<case_id>__<channel>.csv`。
- `manifest.json` 负责描述 case 参数、shape、dtype、容差、是否参与 accuracy/perf、对应 expected 文件名。

## Tests And Acceptance

- `tests/unit/waveforms/` 下拆为 `test_chirp.cpp`、`test_gausspulse.cpp`、`test_sawtooth.cpp`、`test_square.cpp`、`test_unit_impulse.cpp`。
- 默认 `ctest` 运行 correctness 断言，不写 repo 报告文件。
- 手动执行 `--emit-report --case-set full` 时，必须同时生成终端摘要、算子级 `latest_*` 三件套和模块级 `latest_*` 三件套。
- `unit_impulse`、`square` 用精确比较；`chirp`、`gausspulse`、`sawtooth` 用双精度容差比较。
- 验收标准是：
  - CPU/GPU 两后端全部 case 通过
  - `GPU vs CPU` 误差报告完整
  - CPU 性能、GPU e2e 性能、GPU kernel 性能三类指标完整
  - `data/reference`、`data/generated`、`data/reports` 都有清晰落点
  - `READMEV2_2.md` 对上述约定有明确说明

## Assumptions

- `tests/unit` 保持为正式单测根目录，不改成 `test/unit`。
- GPU 主性能口径采用“端到端 API 延迟”，因为当前公开接口是 host `std::vector` 风格；kernel-only 仅作为补充分析指标。
- “尽量都入库”解释为：小型 correctness 数据和代表性性能输入尽量提交到仓库；大体积原始数组与逐次 benchmark trace 不强制入库，避免仓库膨胀。
