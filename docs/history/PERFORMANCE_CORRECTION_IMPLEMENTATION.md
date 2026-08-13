# 性能测量口径修正实施文档

本文件记录本轮已实施的测量修正、尚未处理的事项及容器验收方法。目标是让性能数字
直接回答“完整端到端耗时是多少、GPU 内核本身耗时是多少、相对 CPU 的加速比是多少”。

## 一、修正范围与状态

| 项目 | 实施结论 | 代码/结果位置 |
| --- | --- | --- |
| 1. 单算子测试方法 | GPU E2E 每次从 Host 输入开始，包含 H2D、算子执行、D2H/输出物化；不是改测试名称。 | `tests/unit/*/*_test_support.cu`、`tests/unit/common/report.hpp` |
| 2. 任务测试方法 | 任务总耗时按完整任务链路统计，不只统计计算阶段。 | `demo/task1_radar/task1_radar_demo.cpp`、`demo/task2_features/task2_features_demo.cpp` |
| 3. CPU/GPU 完整任务边界 | CPU、GPU 均分为输入构造、计算、最终输出；GPU 另显式列 `h2d`，输出阶段包含 D2H；CPU 最终输出为 Host 结果物化/复制。 | 两个 task demo 的 `latest_stage_timings.csv`、`latest_metrics.json` |
| 4. GPU kernel 计时 | CUDA event 只包围设备端算子工作；初始 H2D、最终 D2H 不计入 kernel。任务每次 repeat 保存 `gpu_kernel_total_ms`，发布时取中位数。 | `demo/common/task_step_report.hpp`、两个 task demo、`scripts/export_unified_scale_reports.py` |
| 5. 单算子输入复用 | E2E 测量回调中每次重新 `from_host` 或 `copy_from`，并物化输出；kernel 测量继续使用预上传输入以隔离内核。 | bsplines、demod、estimation、filtering、radartools、spectral、wavelets、peak_finding、correlate、windows、filter_design、waveforms 测试支持文件 |
| 6. 其他缓存/资源项 | 暂不处理。 | — |
| 7. 其他平台项 | 暂不处理。 | — |
| 8. 单算子六规模 | 新增六规模复测脚本，默认 workload divisors=`32,16,8,4,2,1`，每个算子输出六行。 | `scripts/benchmark_operator_scales.sh`、`scripts/export_operator_scale_reports.py` |
| 9. 其他数据项 | 暂不处理。 | — |
| 10. 三层算子划分 | `task_used=18`、`appendix_only=26`、`native_only=37`，三者互斥覆盖 all81；任务内部 helper 不混入 81 表。 | `tests/contracts/operator_sets.json`、`scripts/ppt_performance.py` |
| 11. 其他校验项 | 暂不处理。 | — |
| 12. PPT 内容 | 暂不处理。 | — |
| 13–15. 其他事项 | 暂不处理。 | — |

## 二、统一计时口径

### 单算子

每个 perf case 的一次 GPU E2E 计时为：

```text
Host manifest/input
  → host input construction + fresh H2D
  → GPU operator(s)
  → D2H/output materialization
```

GPU kernel 计时使用已准备好的 device 输入，仅记录 CUDA event 之间的设备工作。两种
加速比均直接写入报告：

```text
GPU E2E 加速比    = CPU median / GPU E2E median
GPU kernel 加速比 = CPU median / GPU kernel median
```

报告中的 `gpu_e2e_scope`、`gpu_kernel_scope` 明确记录上述边界。

### 任务

任务每次 repeat 的阶段顺序为：

```text
  input_construction (CPU/Host, included in both CPU and GPU E2E)
  → h2d (GPU only)
  → task operators (device-resident chain)
  → final_detection / task final operator
  → final_output (CPU copy vs GPU D2H/materialization)
```

任务内部链路的阶段名对应实际使用的公共算子或任务 helper；`gpu_kernel_ms` 是各阶段
CUDA event 的设备工作时间，不含 `input_construction`、`h2d`、`final_output`。正式 L1–L6
导出时首轮作为 warm-up 排除，其余 repeat 的 CPU total、GPU total、kernel total 都取中位数。

任务的性能校验阈值仍以原有“设备计算预算”为基准，但在完整 GPU E2E 校验时显式加上本轮
实测的 `input_construction` 时间；因此不会为了通过旧阈值而删掉 Host 输入构造，也不会把
输入构造误计入 GPU kernel。

## 三、六规模算子复测

容器内完成构建后执行：

```bash
cd /CETC
/CETC/scripts/benchmark_operator_scales.sh --no-build --warmup 1 --repeat 3 --print
```

若二进制尚未构建：

```bash
/CETC/scripts/benchmark_operator_scales.sh --build --warmup 1 --repeat 3 --print
```

过程使用 `/tmp` 临时 manifest 与 raw report；临时内容在脚本结束时删除。正式结果只写入：

```text
/CETC/data/reports/units/benchmarks/operator_scales.json
/CETC/data/reports/units/benchmarks/operator_scales.csv
/CETC/data/reports/units/benchmarks/operator_scales.md
```

每行包含：算子、L1–L6、CPU median、GPU E2E median、GPU kernel median、E2E 加速比、
kernel 加速比、PASS 状态及源报告 SHA256。

## 四、容器同步与验收

宿主机：

```bash
cd /home/usr_04/CETC
scripts/sync_to_container.sh --dry-run
scripts/sync_to_container.sh --container gpu_04
```

若脚本提示创建唯一 incoming 目录，按提示进入交互式容器 shell 执行 `mkdir`，再执行
提示的 `--destination-ready` 命令。进入容器后：

```bash
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
cd /CETC
source /zq500/sdk/env.sh ""
/CETC/scripts/build.sh --build-dir build-zx
/CETC/scripts/benchmark_operator_scales.sh --no-build --warmup 1 --repeat 3 --print
```

任务最小闭环可先执行：

```bash
/CETC/build-zx/demo/task1_radar/task1_radar_demo --repeat 3 --scale-level 1 --unified-scale-protocol --invalid-input-checks
/CETC/build-zx/demo/task2_features/task2_features_demo --repeat 3 --scale-level 1 --unified-scale-protocol --invalid-input-checks
```

需要生成正式六规模任务报告时使用：

```bash
/CETC/scripts/unified_scale_benchmark.sh --build-dir build-zx --no-build --repeat 7
```

容器生成的最终报告回宿主机：

```bash
exit
cd /home/usr_04/CETC
scripts/pull_results.sh --container gpu_04 --sync-reports
```

`--sync-reports` 会按原有相对路径增量写入宿主机 `data/reports/` 并刷新
`data/reports/FILES.sha256`，不调用固化脚本。

## 五、验收条件

1. `python3 -m py_compile scripts/export_operator_scale_reports.py scripts/ppt_performance.py` 通过。
2. `bash -n scripts/benchmark_operator_scales.sh` 通过。
3. 任一单算子报告中的 E2E 回调存在 fresh H2D 与输出物化，kernel 回调不调用 D2H。
4. 任务 `latest_metrics.json` 的 `timing_protocol`、`h2d`、`final_output` 存在，`repeat_runs` 每行含 `gpu_kernel_total_ms`。
5. 正式任务导出不再使用“最终一次 kernel 时间”代替重复统计，`measurement.gpu_kernel_total.median_ms` 必须存在。
6. 三层集合计数为 `18 + 26 + 37 = 81`，且不重叠。

## 六、已完成的容器闭环

在 `gpu_04` 的终版 `/CETC` 路径完成以下验收：

- `scripts/build.sh --build-dir build-zx`：`[build] PASS`，所有 demo、公共库和 81 项测试目标完成链接。
- Task1 L1：`PASS repeat=3`，实测 `CPU E2E=205.341 ms`、`GPU E2E=52.026 ms`、
  `GPU kernel=6.261 ms`。
- Task2 L1：`PASS repeat=3`，实测 `CPU E2E=1767.908 ms`、`GPU E2E=899.510 ms`、
  `GPU kernel=2.926 ms`。
- `waveforms/chirp` 独立算子：`PASS`，实测 `CPU=297.711 ms`、`GPU E2E=424.746 ms`、
  `GPU kernel=3.135 ms`；该结果说明当前口径确实包含 fresh H2D/D2H，不能把 kernel 加速比
  当作端到端加速比。
- 六规模脚本以 `demo_cache_probe4`、`divisor=1024,1024,1024,1024,1024,1024` 完成
  24 行冒烟验证，确认 L1–L6、CSV/JSON/Markdown 发布和终端集中打印均正常；这只是脚本
  闭环验证，不是 all81 正式六规模数据。正式数据使用本文件第三节的默认命令生成。

本轮未把中途停止的 all81 长时回归标记为“全量通过”；正式 all81 六规模数据仍需在容器中
执行默认命令后再用于答辩图表。
