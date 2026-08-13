# 最终交付状态

## 当前边界

- 主仓库就是交付版本；本轮不创建外部压缩包，不提交、不推送。
- 算子集合口径为 `all81=81`、`task_appendix=53`、`task_used=18`、
  `appendix_only=37`、`native_only=26`。
- `scripts/` 只保留一个构建入口、一个性能入口、一个正确性烟测入口，以及清理、
  容器同步、容器替换和结果取回脚本。
- 历史运行编号、冻结性能数据和旧流程说明位于 `docs/history/`，不作为当前入口。

## 保留内容

- `include/`、`src/`：公共接口、CPU 实现和 ZQ500 GPU 实现；
- `demo/`：Task1/Task2 demo；
- `tests/`：算子、任务和平台相关测试；
- `tests/contracts/`：算子集合与六级规模契约；
- `scripts/build.sh`：统一构建；
- `scripts/performance.sh`：统一性能测试；
- `scripts/smoke.sh`：统一正确性烟测；
- `scripts/clean.sh`：清理可再生运行数据；
- `scripts/sync_to_container.sh`、`replace_container_project.sh`、`pull_results.sh`：
  容器工作流；
- `data/reference/`、`data/generated/**/manifest.json`：参考数据和输入契约；
- `data/reports/`：已有结果目录；
- `DELIVERY_FILES.txt`：容器同步白名单。

旧的分散构建、算子测试、任务 demo、六规模 benchmark、报告 finalizer、PPT 包装和
完整 validate 入口不属于当前脚本架构。

## 报告边界

`performance.sh` 将最终结果写入 `data/reports/units/benchmarks/` 和
`data/reports/demo/<task>/summary.csv` 与 `operators/`；算子和任务二进制负责生成正式 CSV
报告。每次运行的原始中间文件另写入
`data/.reports_staging/performance/run_<timestamp>_<pid>/`。当前架构不再保留独立报告
finalizer。

容器结果取回由宿主机上的 `pull_results.sh` 完成：

```bash
scripts/pull_results.sh --container gpu_04
scripts/pull_results.sh --container gpu_04 --sync-reports
```

不提供 `--promote-reports`。`--sync-reports` 只是校验并增量合并容器已有报告，不能
替代重新运行构建、烟测或性能测试。

## 验证边界

宿主机可执行 shell 语法、帮助接口、契约文件和 Python 单元测试的静态检查；GPU 构建、
正确性和性能必须在 `gpu_04` 容器内运行：

```bash
scripts/build.sh --all
scripts/smoke.sh --all
scripts/performance.sh --all --scale all
```

本轮已在 `gpu_04` 容器完成契约审计、目标构建、相关算子定向性能和两个任务 L3 烟测；
未在本轮执行 81 个算子六级全量性能复测，也未将容器报告再次拉回宿主机。

## 受保护项

本轮不处置以下已有工作区状态：`.codex`、赛事 DOCX、`.vscode/`、
`复赛说明文件/` 和 `ppt_work/`。兼容 XLSX 由
`ZX_COMPAT_SOURCE_DIR` 提供，不因本脚本清理自动加入交付白名单。
