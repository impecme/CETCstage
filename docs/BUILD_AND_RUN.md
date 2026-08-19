# 构建与运行

## 1. 环境边界

GPU 构建和执行必须在中科芯 ZQ500 容器 `gpu_04` 中完成。服务器宿主机负责源码同步、
结果取回和静态检查；容器内需要 CMake、C++17、Python 3、`/zq500/sdk/env.sh`、
`dlcc`、ZQ500 runtime/FFT/BLAS/solver 库，以及仓库内固定版本的 FFTW 离线源包。

宿主机执行 Docker 命令：

```bash
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
```

容器内脚本会自行定位 `/CETC`。退出容器使用 `exit`，它不会停止容器。

## 2. 源码同步

宿主机在当前仓库执行：

```bash
cd /home/usr_04/CETC
scripts/sync_to_container.sh --container gpu_04 --replace
```

该脚本只复制根目录 `DELIVERY_FILES.txt` 白名单并做 SHA256 回读校验，不构建、不测试、
不生成或发布报告。脚本完成后按终端打印的固定命令进入容器并运行
`/tmp/cetc_activate.sh`。

容器内替换源码的实际动作由 `scripts/replace_container_project.sh` 完成；它不负责构建
或测试。

## 3. 构建入口

所有构建选项集中在 `scripts/build.sh`：

```bash
# 默认构建 81 个算子
/CETC/scripts/build.sh

# 构建算子集合
/CETC/scripts/build.sh --operators --operator-set task_used
/CETC/scripts/build.sh --operators --operator-set appendix_only
/CETC/scripts/build.sh --operators --operator-set task_appendix
/CETC/scripts/build.sh --operators --operator-set native_only
/CETC/scripts/build.sh --operators --operator-set all81

# 构建一个模块或一个算子
/CETC/scripts/build.sh --operators --operator-set all81 --module spectral
/CETC/scripts/build.sh --operators --operator spectral/spectrogram

# 构建任务
/CETC/scripts/build.sh --tasks task1
/CETC/scripts/build.sh --tasks task2
/CETC/scripts/build.sh --tasks both

# 81 个算子和两个任务全部构建
/CETC/scripts/build.sh --all
```

依赖已准备好时可使用 `--skip-deps`；完整参数以 `/CETC/scripts/build.sh --help` 为准。
`--target` 仅保留给高级 CMake target 调试。

## 4. 性能测试入口

性能测试集中在 `scripts/performance.sh`。选择器与构建入口一致，规模固定为单个
`L1`～`L6` 或 `all`：

```bash
# 18 个任务实际调用注册算子，全部六个规模
/CETC/scripts/performance.sh --operators --operator-set task_used --scale all

# 仅附录中存在且任务未使用的算子，L3
/CETC/scripts/performance.sh --operators --operator-set appendix_only --scale L3

# 单个算子、单个模块中的任务或两个任务
/CETC/scripts/performance.sh --operators --operator spectral/spectrogram --scale all
/CETC/scripts/performance.sh --tasks --task task1 --scale all
/CETC/scripts/performance.sh --tasks --task both --scale L6

# 全量
/CETC/scripts/performance.sh --all --scale all
```

不传 `--scale` 时默认六个规模；不传选择器时默认 81 个算子和两个任务。自定义规模
暂未提供，脚本会拒绝 `--scale custom`。性能默认 `warmup=5/repeat=30`，可使用
`--warmup`、`--repeat` 和 `--no-build`。

汇总结果写入 `data/reports/autotune/units/benchmarks/`，任务各规模结果写入
`data/reports/autotune/demo/<task>/summary.csv` 与 `operators/L1.csv` ... `L6.csv`；原始中间文件写入
`data/.reports_staging/performance/` 下的本次运行目录。算子规模定义由 `tests/contracts/operator_scale_profiles.json` 提供，
不再由外部 benchmark 包装脚本拼接。

## 5. 正确性烟测入口

`scripts/smoke.sh` 只负责快速正确性检查，复用性能选择器并固定 L3：

```bash
/CETC/scripts/smoke.sh --all
/CETC/scripts/smoke.sh --operators --operator filtering/wiener
/CETC/scripts/smoke.sh --tasks --task task2
```

它不承担平台兼容性审计、完整 81×6 性能门禁或报告固化；需要完整参数时执行
`/CETC/scripts/smoke.sh --help`。

## 6. 结果取回

容器完成运行后回到服务器宿主机：

```bash
cd /home/usr_04/CETC

# 默认把 data/reports 和传输状态保存到仓库外
scripts/pull_results.sh --container gpu_04

# 增量写入当前仓库的 data/reports/
scripts/pull_results.sh --container gpu_04 --sync-reports
```

`pull_results.sh` 只负责传输、校验和可选的增量合并，不调用报告生成器，不提供报告
“升级/发布”选项。容器内尚未生成的宿主机报告文件会保留；原始副本默认放在
`/home/usr_04/CETC_garbage/container_pull_<timestamp>/`。

## 7. 报告与清理

性能入口的默认最终汇总位于 `data/reports/autotune/units/benchmarks/`，单算子明细位于
`data/reports/autotune/units/<module>/<operator>/<L1-L6>/`；原始中间文件位于：

```text
data/.reports_staging/performance/run_<timestamp>_<pid>/
├── raw/reports/<scale>/<module>/<operator>/  # 算子原始 metrics/cases/summary
└── tasks/<task>/<scale>/                     # 任务 metrics 和输入快照
```

任务 demo 自身仍会在 `data/.reports_staging/demo/` 写入其 latest 报告，性能入口随后将
选定规模汇总到 `data/reports/autotune/demo/<task>/summary.csv` 和 `operators/`。报告由运行二进制生成；本架构不再
保留独立的 finalizer 或 PPT 包装脚本。

运行结束后：

```bash
scripts/clean.sh --dry-run
scripts/clean.sh
```

`clean.sh` 只处理可再生输入、运行期暂存和日志，保留参考数据、manifest 和已有报告。
