# 性能测试与报告

## 集合

| 集合 | 数量 | 含义 |
| --- | ---: | --- |
| `all81` | 81 | 全部公开算子 |
| `task_appendix` | 53 | 附录中的全部算子 |
| `task_used` | 18 | 两个任务源码实际调用的注册算子 |
| `appendix_only` | 37 | 附录中未被任务采用的注册算子 |
| `native_only` | 26 | 原生库中不在附录且未被任务采用的注册算子 |

集合定义唯一来源是 `tests/contracts/operator_sets.json`，关系为
`appendix_only = task_appendix - task_used`，三层互斥且并集为 81。

## 入口

只有一个性能入口：

```bash
scripts/performance.sh [选择器] [--scale L1|L2|L3|L4|L5|L6|all]
```

选择器可以是算子集合、模块、单个 `module/operator`、Task1、Task2 或两者：

```bash
scripts/performance.sh --operators --operator-set task_used --scale all
scripts/performance.sh --operators --operator-set appendix_only --scale L3
scripts/performance.sh --operators --operator spectral/spectrogram --scale all
scripts/performance.sh --tasks --task task1 --scale all
scripts/performance.sh --tasks --task both --scale L6
scripts/performance.sh --all --scale all
```

不传选择器时执行 `all81` 和两个任务；不传规模时执行 L1～L6。自定义规模暂不支持，
脚本会在启动阶段拒绝 `--scale custom`。默认 `warmup=5/repeat=30`，已有二进制可用
`--no-build`。

正确性烟测使用同一组选择器，但固定代表性 L3：

```bash
scripts/smoke.sh --all
scripts/smoke.sh --operators --operator filtering/wiener
scripts/smoke.sh --tasks --task both
```

## 规模定义

六个规模由 `tests/contracts/operator_scale_profiles.json` 为每个算子显式声明。脚本在
运行前读取 profile、生成本次临时 manifest，并将规模元数据写入本次 staging 目录；不
修改仓库内基础 manifest。输入维度优先采用 2 的整数次幂，FIR taps 等算法约束保留
合法的 `2^k+1` 例外；只改变阶数、窗长或阈值的算子标记为 `scalar_parameter`。

单算子报告分别记录：

- CPU 端到端中位耗时；
- GPU E2E 中位耗时，包含 GPU 端输入构造、GPU 计算和最终输出物化；正式任务输入 H2D 为 0；
- GPU kernel 中位耗时，由独立 CUDA event 测量；验证专用 H2D/D2H 不计入正式 E2E；
- `gpu_e2e_speedup = CPU E2E / GPU E2E`；`gpu_kernel_speedup` 仅表示
  `CPU wall / GPU kernel` 的辅助比值，当前没有独立 CPU kernel 计时，不能表述为严格的
  CPU/GPU kernel 加速比。

汇总 CSV/JSON 还预留 `host_input_ms`、`h2d_ms`、`gpu_compute_ms`、`d2h_ms`、
`host_output_ms`、`path_kind` 和 `gpu_acceleration_eligible` 字段。后端未单独报告的
阶段保持为空/`null`，不从端到端耗时反推；无独立 GPU Kernel 的算子同样使用空值和
“—/不适用”。

任务报告记录 CPU total、GPU total、任务步骤 kernel 总时延、正确性和无效输入检查。

任务级 GPU E2E 每个正式 repeat 都在 Device 端重新生成波形、目标回波/帧和噪声；任务链内部的
Device 输出直接传给下一算子，链尾统一执行 D2H/输出物化。CPU 和 GPU 使用相同场景参数、seed、索引映射和计数式 RNG，但分别持有各自输入。允许复用的是“容量”而非
“数据”：`DeviceStorage` 可以保留已申请的显存块，FFT plan 可以保留已建立的计划及
其元数据，但不得把上一轮输入值当作下一轮输入。任务 `metrics.json` 的
`timing_protocol` 会同时记录 `input_refresh_policy` 和 `workspace_reuse_policy`。

任务误差分为三层：`input_error` 比较 CPU-native 输入与 GPU-native 输入；`operator_error`
在验证模式使用同一份 CPU 输入并额外上传到 GPU，隔离 CPU/GPU 算子差异；`e2e_error`
比较两条正式 native 路径的最终结果。验证专用传输不进入正式性能统计。

## 报告位置

本次运行将最终汇总写入固定发布目录，原始中间文件使用唯一暂存目录：

```text
data/reports/units/benchmarks/
├── operator_scales.json
├── operator_scales.csv
├── operator_scales.md
```

原始中间文件位于：

```text
data/.reports_staging/performance/run_<timestamp>_<pid>/
├── raw/reports/<scale>/<module>/<operator>/latest_metrics.json
└── tasks/<task>/<scale>/latest_*.json
```

任务可执行文件仍会把其原始 latest 报告写入
`data/.reports_staging/demo/<task>/`，其中 `latest_summary.csv`、`latest_operators.csv` 和
`latest_stages.csv` 是正式任务汇总入口；`latest_operators.csv` 只包含注册公共算子，
`latest_stages.csv` 保留输入构造、私有 Helper、融合和输出等阶段。性能入口随后只发布
`data/reports/demo/<task>/summary.csv` 和
`data/reports/demo/<task>/operators/L1.csv` ... `L6.csv`、
`data/reports/demo/<task>/stages/L1.csv` ... `L6.csv`。
summary/operator CSV 均包含 `max_abs`、`max_rel`、`RMSE`、`mixed_error`；
正式任务输入 `task_input_h2d_ms` 为零。
报告由测试
二进制生成，不再经过独立的 `finalize_reports.py`、六规模 benchmark 或 PPT 包装脚本。

`performance.sh` 会覆盖同名最终汇总文件；需要
从容器取回结果时，在宿主机使用：

```bash
scripts/pull_results.sh --container gpu_04
scripts/pull_results.sh --container gpu_04 --sync-reports
```
