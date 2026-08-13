# 正确性与报告

当前脚本架构把“正确性烟测”和“性能测试”分开：不再保留一个同时承担平台审计、完整
benchmark、报告固化和正式发布的 `validate.sh`。

## 入口职责

| 入口 | 职责 | 规模 |
| --- | --- | --- |
| `scripts/build.sh` | SDK/FFTW 检查、配置和目标构建 | 由算子/任务选择器决定 |
| `scripts/smoke.sh` | 算子和任务的快速正确性检查 | 固定代表性 L3 |
| `scripts/performance.sh` | CPU/GPU 计时、加速比和结构化结果 | 单个 L1～L6 或全部六级 |
| `scripts/pull_results.sh` | 从容器取回或增量合并已有结果 | 不运行测试、不固化报告 |

## 烟测

烟测复用性能入口的选择器，但固定 `warmup=0/repeat=1`，只检查选定内容：

```bash
scripts/smoke.sh --all
scripts/smoke.sh --operators --operator-set task_used
scripts/smoke.sh --operators --operator spectral/spectrogram
scripts/smoke.sh --tasks --task task1
scripts/smoke.sh --tasks --task both
```

烟测通过表示选定二进制的正确性 smoke case 和任务无效输入检查通过；它不等价于完整
平台兼容性审计或六级性能结果。

## 性能结果

```bash
scripts/performance.sh --operators --operator-set task_appendix --scale all
scripts/performance.sh --tasks --task both --scale all
```

最终结果默认写入：

```text
data/reports/
├── units/benchmarks/operator_scales.{json,csv,md}
└── demo/<task>/{summary.csv,operators/L1.csv ... operators/L6.csv}
```

每次运行的原始中间文件另存于唯一目录：

```text
data/.reports_staging/performance/run_<timestamp>_<pid>/
├── raw/reports/<scale>/<module>/<operator>/latest_metrics.json
└── tasks/<task>/<scale>/latest_*.json
```

算子单行记录 CPU E2E、GPU E2E、GPU kernel、两种加速比、规模字段，以及
operator/e2e 的 `max_abs`、`max_rel`、`RMSE`、`mixed_error` 和状态；任务汇总记录
CPU/GPU input、total、步骤 kernel、`task_input_h2d_ms`、三类误差的
`max_abs`、`max_rel`、`RMSE`、`mixed_error`、正确性和输入检查。规模来自
`tests/contracts/operator_scale_profiles.json`，运行时生成临时 manifest，不修改基础
manifest。

## 既有报告与取回

容器运行完成后，在服务器宿主机执行以下命令取回并增量写入当前仓库的
`data/reports/`：

```bash
scripts/pull_results.sh --container gpu_04
scripts/pull_results.sh --container gpu_04 --sync-reports
```

不提供报告 promotion/finalizer 模式；`--sync-reports` 只做传输校验和增量合并。

## 独立平台检查

平台兼容夹具校验、API 扫描和合同工具仍位于 `tests/platform/`、`tests/tools/`，需要时
可直接调用其 Python 工具或 CMake 测试。它们不是 `scripts/` 的日常入口，也不会由
`smoke.sh` 隐式执行。外部 XLSX 通过 `ZX_COMPAT_SOURCE_DIR` 提供，源文件不属于脚本
清理范围。
