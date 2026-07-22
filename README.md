# CETC ZQ500 信号处理算子库

这是面向中科芯 ZQ500 平台的 C++17 信号处理代码库。它包含 CPU reference 和 ZQ500
GPU 实现，覆盖 12 个模块、81 个公开算子，以及 Task1 雷达处理和 Task2 特征提取两个
可执行 demo。

## 代码结构

```text
CETC/
├── CMakeLists.txt        顶层构建入口
├── DELIVERY_FILES.txt    容器同步与交付清单
├── include/cusignal/     公开 API 与兼容层
├── src/
│   ├── common/           共用语义与工具
│   ├── cpu/              CPU reference
│   └── zhongkexin/       ZQ500 GPU 后端
├── demo/
│   ├── common/           Task 报告公共代码
│   ├── task1_radar/      雷达处理 demo
│   └── task2_features/   特征提取 demo
├── tests/
│   ├── unit/             81 算子独立测试
│   ├── contracts/        all81、dtype、任务契约
│   ├── tools/            审计工具
│   └── platform/         ZQ500 兼容性检查
├── data/
│   ├── reference/        固定参考数据
│   ├── generated/        可再生输入与 manifest
│   └── reports/          当前发布报告
├── scripts/
│   ├── build.sh、test_operators.sh、demo.sh、validate.sh
│   ├── finalize_reports.py、clean.sh
│   └── sync_to_container.sh、pull_results.sh
├── third_party/fftw/     离线 FFTW 依赖
└── docs/                 架构、运行、验证与交付文档
```

结构图只列出稳定边界，不逐项展开 81 个算子、参考 CSV、运行期暂存或各模块单测文件；
这些条目分别由 `tests/contracts/operator_sets.json`、各算子 manifest 和 `tests/unit/`
管理。

## 容器

本队对应容器为 `gpu_04`。Docker 命令在服务器宿主机执行；进入容器后才运行构建、
测试和 demo 命令。当前账户可使用交互式 shell，但不具备通用非交互
`sudo docker exec gpu_04 <command>` 权限。

### 直接运行容器中的终版代码

在宿主机复制执行以下命令进入容器：

```bash
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
```

容器内的最终运行入口均使用绝对路径。无论当前位于 `/`、`/tmp` 或其他目录，均可直接
执行下列命令；脚本会自行定位 `/CETC`、加载 SDK，并把相对 `build-zx` 定位为
`/CETC/build-zx`：

```bash
/CETC/scripts/validate.sh --build-dir build-zx
```

`exit` 只退出当前容器 shell，不会停止 `gpu_04`。

### 同步宿主机的新源码

在宿主机源码修改后，先复制运行以下命令：

```bash
cd /home/usr_04/CETC
scripts/sync_to_container.sh --container gpu_04 --replace
```

再复制执行脚本打印的固定激活块；其内容始终如下，无需填写时间戳或目录路径：

```bash
sudo docker exec -it gpu_04 bash
bash /tmp/cetc_activate.sh
exit
```

第一条命令自动启动 `gpu_04`、复制唯一暂存目录、完成 SHA256 回读校验，并将激活脚本放入
容器 `/tmp`。第二条固定命令在当前账户获准的交互式 Shell 中原子替换 `/CETC` 并删除旧源码。
两步均不执行构建、测试、验证、报告发布或任何固化流程；替换后再按本 README 的构建、演示或
性能命令单独执行。

### 取回容器运行结果

容器内运行完成后先 `exit` 返回宿主机。当前终版路径固定为 `/CETC`，因此取回时无需填写
容器目录或时间戳。局部算子测试、任务复测、现场 `--live-demo` 与完整验证均可直接同步到
宿主机仓库的对应目录：

```bash
# 通用结果同步：将容器 data/reports 中已有文件增量写入宿主机 data/reports/
# 不要求运行完整验证；容器未生成的宿主机报告会保留
cd /home/usr_04/CETC
scripts/pull_results.sh --container gpu_04 --sync-reports

# 正式发布：仅在 scripts/validate.sh 完整通过后使用；校验后原子替换宿主机 data/reports/
cd /home/usr_04/CETC
scripts/pull_results.sh --container gpu_04 --promote-reports
```

`--sync-reports` 通过 SHA256 校验传输内容后，将容器结果按原有相对路径写入宿主机
`data/reports/`，并刷新该目录的 `FILES.sha256`；它不调用报告固化脚本，也不删除容器未生成的
宿主机文件。完整验证通过后再使用 `--promote-reports`：只有 81 个算子、两条任务及审计报告
齐全时才原子替换整个宿主机 `data/reports/`，此前的报告自动移入
`/home/usr_04/CETC_garbage/promoted_report_backups/`。

如需仅保留仓库外的原始传输副本而不更新仓库，可省略 `--sync-reports`；脚本会把副本保存到
`/home/usr_04/CETC_garbage/container_pull_<时间戳>/`。

## 构建与运行

以下命令均可在容器任意目录执行。

先构建：

```bash
/CETC/scripts/build.sh --build-dir build-zx
```

构建并运行两个任务 demo，使用默认 L6 高并行数据规模：

```bash
/CETC/scripts/demo.sh --build-dir build-zx --build --repeat 5
```

在不修改源码的前提下探索任务输入形状、比较实际加速比，并把中间日志保留在容器
`/tmp`，可运行：

```bash
/CETC/scripts/explore_task_acceleration.sh --build-dir build-zx --task both --repeat 3
```

探索脚本只保留通过 CPU/GPU 数值验证的候选，并按端到端加速比输出排序；它不会将探索
结果发布为最终报告。确定候选后，应以 `repeat=5` 单独复测，再运行正式 demo 生成报告。

构建并运行全部算子，使用每个算子 manifest 中定义的默认 full case：

```bash
/CETC/scripts/test_operators.sh --build-dir build-zx --case-set full
```

构建并运行指定算子，使用该算子 manifest 中定义的默认 full case：

```bash
/CETC/scripts/test_operators.sh \
  --build-dir build-zx \
  --module filtering \
  --operator wiener \
  --case-set full
```

查看可运行的模块和算子：

```bash
/CETC/scripts/test_operators.sh --list
```

### 答辩性能终端表

生成答辩用性能终端表：默认一次测量 81 个公开算子和两条任务的正式 L1～L6，随后按
`task27`、`extended28`、`core53` 三层逐算子打印 CPU median、GPU E2E median、已计算
加速比和状态，并打印两个任务的 L1～L6 表：

```bash
/CETC/scripts/ppt_performance.sh
```

分项运行与只读打印：

```bash
# 重测 all81，并按 task27 / extended28 / core53 三层打印全部公开算子性能
/CETC/scripts/ppt_performance.sh --operators

# 重测两条任务的正式统一 L1-L6，并打印任务端到端性能
/CETC/scripts/ppt_performance.sh --tasks

# 不执行 GPU 测量，仅打印当前 data/reports/ 中已有的结果
/CETC/scripts/ppt_performance.sh --print-only
```

现场时间有限时建议先在上台前构建一次。以下 `--demo-fast` 命令用于局部复测，不适合作为
短时现场演示：Top30 和完整任务 L1～L6 仍需较长时间。

```bash
# 上台前准备：只构建，不计入现场演示时间
/CETC/scripts/build.sh --build-dir build-zx

# 局部算子复测：Top30 代表算子，perf case，warmup=1，repeat=3
/CETC/scripts/ppt_performance.sh --operators --demo-fast --no-build

# 局部任务复测：两条任务正式 L1-L6，repeat=3
/CETC/scripts/ppt_performance.sh --tasks --demo-fast --no-build

# 兜底方案：不重测，秒级打印已发布的 all81 和任务数据
/CETC/scripts/ppt_performance.sh --print-only
```

现场只演示赛题基础目录和两个任务最高加速比规模时，使用专用命令：

```bash
# 上台前完成构建；现场只复用二进制
/CETC/scripts/build.sh --build-dir build-zx

# 现场实测 core53（53 个）perf case；Task1/Task2 自动选当前正式报告中加速比最高的规模，
# 终端只打印 core53 和两个任务的单行结果；本轮快照直接写入既有 reports/units 与 reports/demo
/CETC/scripts/ppt_performance.sh --live-demo --no-build
```

当前正式报告中两个任务的最高加速比规模均为 `L6`：Task1 为 `33.094558×`，Task2 为
`1048.778098×`。`--live-demo` 每次仍会从正式 L1～L6 报告重新选择最大值，不把该结论硬编码
为固定规模；现场运行使用 `core53 / perf / warmup=1 / repeat=1` 和任务 `repeat=1`，因此是
演示复核，不替代正式 `warmup/repeat` 协议的结果发布。

现场模式不会新建目录，完成后仅增加以下四个快照文件，并更新 `data/reports/FILES.sha256`：

- `data/reports/units/live_demo_core53.json`、`data/reports/units/live_demo_core53.csv`
- `data/reports/demo/live_demo_tasks.json`、`data/reports/demo/live_demo_tasks.csv`

它们明确标注为现场复核快照，不替代 `units/benchmarks/summary.json` 或任务的正式 L1～L6 报告。

默认算子测量为 `all81`、`case-set=full`、`warmup=5`、`repeat=30`；每行的加速比是
结构化结果中直接记录的 `CPU median / GPU E2E median`。任务测量默认 `repeat=7`，
首轮仅 warm-up，后续轮次的 CPU/GPU total 中位数用于计算 L1～L6 加速比。可用
`--no-build` 复用已有二进制，也可用 `--operator-set`、`--operator-case-set`、
`--operator-warmup`、`--operator-repeat`、`--task-repeat` 调整测量范围和次数。

`core53` 包含 `task27`，三层是性能覆盖视图，不得相加为 108 个算子；`extended28` 使用
“赛题附录”标题前，仍须核对其与官方附录名单一致。

执行完整验证，包括构建、81 个算子、Task1/Task2 的 L1-L6、接口/dtype/任务步骤审计
及报告发布；全部通过后自动在终端集中打印三层算子性能表和两条任务的 L1-L6 性能表：

```bash
/CETC/scripts/validate.sh --build-dir build-zx
```

完整验证成功后，当前报告发布到 `data/reports/`：

- `units/<module>/<operator>/`：逐算子测试数据；
- `units/benchmarks/summary.json` 和 `summary.csv`：全部算子的运行时间、加速比和误差汇总；
- `demo/`：两个任务的最终场景和 L1-L6 数据；
- `validation/`：接口、dtype、算子集合和任务步骤审计。

运行期数据写在 `data/.reports_staging/`，只有完整验证通过才会替换已发布报告。
构建目录、缓存、日志和历史过程文件不属于交付内容。详细容器工作流和结果取回见
[docs/BUILD_AND_RUN.md](docs/BUILD_AND_RUN.md)。
