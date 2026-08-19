# CETC

中科芯 ZQ500 信号处理库、81 个公开算子和两个任务 demo。

## 脚本边界

```text
auto_git.sh                         根目录自动提交辅助脚本，保留
scripts/build.sh                    唯一构建入口
scripts/performance.sh              唯一性能测试入口
scripts/run_optimized_operators_against_frozen.sh
                                    只运行优化算子并与冻结 GPU 基线配对
scripts/smoke.sh                    正确性烟测入口
scripts/clean.sh                    清理可再生运行数据
scripts/sync_to_container.sh        宿主机同步源码到容器
scripts/replace_container_project.sh 容器内替换源码
scripts/pull_results.sh             容器结果取回
```

`scripts/` 不再保留旧的分散构建、算子测试、任务 demo、六规模 benchmark、报告
收束或 PPT 包装脚本。算子集合定义在
`tests/contracts/operator_sets.json`，六个规模定义在
`tests/contracts/operator_scale_profiles.json`。

集合数量固定为：`all81=81`、`task_appendix=53`、`task_used=18`、
`appendix_only=37`、`native_only=26`。第一层按任务源码真实调用的注册算子确定；任务 Helper/变体单独记录，不计入 81 个注册算子。

## 构建

构建必须在 ZQ500 容器中执行。默认构建全部 81 个算子：

```bash
scripts/build.sh
```

按算子集合、模块或单个算子构建：

```bash
scripts/build.sh --operators --operator-set task_used
scripts/build.sh --operators --operator-set appendix_only
scripts/build.sh --operators --operator-set all81 --module spectral
scripts/build.sh --operators --operator spectral/spectrogram
```

按任务构建，或一次构建全部内容：

```bash
scripts/build.sh --tasks task1
scripts/build.sh --tasks task2
scripts/build.sh --tasks both
scripts/build.sh --all
```

`--operator-set`、`--module`、`--operator` 可以组合；完整参数见
`scripts/build.sh --help`。`--target` 仅用于高级 CMake target 调试，不是日常入口。

## 性能测试

性能入口可以选择算子、任务、集合、模块、单个算子和固定规模。规模只允许单个
`L1`～`L6` 或六个规模全部执行，不提供自定义规模配置：

```bash
# 任务实际调用的 18 个注册算子，六个规模
scripts/performance.sh --operators --operator-set task_used --scale all

# 附录中但任务未使用的算子，单个规模
scripts/performance.sh --operators --operator-set appendix_only --scale L3

# 单个算子
scripts/performance.sh --operators --operator spectral/spectrogram --scale all

# 单个任务或两个任务
scripts/performance.sh --tasks --task task1 --scale all
scripts/performance.sh --tasks --task both --scale L6

# 81 个算子和两个任务
scripts/performance.sh --all --scale all
```

默认将汇总结果写入 `data/reports/autotune/units/benchmarks/`，每个规模的单算子明细写入
`data/reports/autotune/units/<module>/<operator>/<L1-L6>/`，任务结果写入
`data/reports/autotune/demo/<task>/summary.csv`、公共注册算子 `operators/L1.csv` ... `L6.csv` 和任务阶段
`stages/L1.csv` ... `L6.csv`；其中 Task1 每个规模 5 个公共算子、Task2 每个规模 14 个公共算子，
阶段/私有 Helper 不计入公共算子数量。原始中间文件写入
`data/.reports_staging/performance/run_<timestamp>_<pid>/`。性能报告中分别保留 CPU
端到端、GPU E2E、GPU kernel 计时及加速比；E2E 加速比为 `CPU E2E / GPU E2E`，
`gpu_kernel_speedup` 仅为 `CPU wall / GPU kernel` 辅助比值，不表述为严格的 CPU/GPU kernel
加速比。无独立 GPU kernel 的算子以 `null`/“不适用”表示。已有构建可加 `--no-build`；正式性能测量
默认 `warmup=5/repeat=30`，可用 `--warmup`、`--repeat` 调整。

任务级正式 E2E 每次 repeat 都在各自后端重新构造输入；GPU 路径由 Device 波形算子和
输入 kernel 直接生成，正式 `task_input_h2d_ms=0`，链内 Device 输出直接传给下一算子，
链尾统一回读。可复用的是显存容量和 FFT plan，不是上一轮输入值；任务报告的
`timing_protocol` 会记录这一口径。

## 正确性烟测

烟测复用性能入口的选择器，但固定代表性 `L3`、`warmup=0`、`repeat=1`，只检查
正确性，不承担完整平台审计或正式报告发布：

```bash
scripts/smoke.sh --all
scripts/smoke.sh --operators --operator filtering/wiener
scripts/smoke.sh --tasks --task both
```

## 容器工作流

Docker 命令在服务器宿主机执行，构建/测试命令在 `gpu_04` 容器内执行：

```bash
# 宿主机
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash

# 容器内
cd /CETC
scripts/build.sh --all
scripts/smoke.sh --all
scripts/performance.sh --all --scale all
exit
```

同步源码前在宿主机运行：

```bash
cd /home/usr_04/CETC
scripts/sync_to_container.sh --container gpu_04 --replace
```

按脚本打印的激活命令在容器内执行。`sync_to_container.sh` 只同步
`DELIVERY_FILES.txt` 白名单，不构建、不测试、不发布报告。

结果取回同样在宿主机执行：

```bash
cd /home/usr_04/CETC
scripts/pull_results.sh --container gpu_04
scripts/pull_results.sh --container gpu_04 --sync-reports
```

第一条保存到仓库外的 `CETC_garbage/container_pull_<timestamp>/`；第二条把容器的
`data/reports/` 增量同步到宿主机，不执行报告固化，也没有 `--promote-reports` 模式。

## 清理

```bash
scripts/clean.sh --dry-run
scripts/clean.sh
```

只清理可再生输入、运行期暂存和日志，不处理 `data/reference/`、规模 manifest、已存在
的报告或用户的其他未提交修改。`auto_git.sh` 会调用该清理入口。

## 目录

- `include/`、`src/`：公共接口、CPU 实现和 ZQ500 GPU 实现。
- `demo/`：Task1/Task2 demo。
- `tests/contracts/`：算子集合和规模契约。
- `tests/unit/`：算子测试目标。
- `data/generated/`：可再生输入和 manifest。
- `data/.reports_staging/`：运行期原始报告暂存区。
- `docs/`：构建、性能、交付和历史说明。
