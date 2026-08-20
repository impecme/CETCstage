# CETC

中科芯 ZQ500 信号处理库、81 个公开算子和两个任务 demo。

## 代码框架

项目主要目录树如下；运行期生成物、性能报告和源码分别归档在 `data/`、`scripts/`、
`src/` 等对应目录中：

```text
CETC/
├── CMakeLists.txt                         顶层 CMake，生成 CPU/GPU 库和测试目标
├── README.md
├── DELIVERY_FILES.txt                     同步到 ZQ500 容器的文件白名单
├── auto_git.sh                            提交辅助脚本
├── include/
│   └── cusignal/                          对外 API、公共类型和结果结构
│       ├── core/
│       ├── bsplines/       correlate/     demod/        estimation/
│       ├── filter_design/  filtering/     peak_finding/ radartools/
│       ├── spectral/       waveforms/     wavelets/     windows/
│       └── cusignal.hpp                   聚合头文件
├── src/
│   ├── common/                            CPU/GPU 共享语义和参数检查
│   ├── cpu/                               CPU reference 实现
│   └── zhongkexin/                        ZQ500 GPU 实现和平台适配
├── demo/
│   ├── common/
│   ├── task1_radar/                       Task1 雷达任务 demo
│   └── task2_features/                    Task2 特征任务 demo
├── tests/
│   ├── contracts/                         算子、规模和任务步骤契约
│   ├── unit/                              公开算子单元测试
│   │   ├── core_types/ bsplines/ correlate/ demod/
│   │   ├── estimation/ filter_design/ filtering/ peak_finding/
│   │   ├── radartools/ spectral/ waveforms/ wavelets/ windows/
│   │   └── common/
│   ├── platform/                          ZQ500 编译/运行库探针
│   └── tools/                             测试辅助工具
├── scripts/
│   ├── build.sh                           构建入口
│   ├── performance.sh                     性能测试入口
│   ├── smoke.sh                           正确性烟测入口
│   ├── clean.sh                           可再生运行数据清理
│   ├── sync_to_container.sh               宿主机同步源码
│   ├── replace_container_project.sh       容器内替换源码
│   └── pull_results.sh                    容器结果取回
├── data/
│   ├── reference/                         固定正确性参考数据
│   ├── generated/                         可再生输入和输出样本
│   ├── baseline/                          冻结 CPU/GPU 基线
│   ├── tuning/                            Auto 离线查表缓存
│   └── reports/                           静态、Auto 和任务报告
└── docs/
    ├── ARCHITECTURE.md                    完整架构说明
    ├── BUILD_AND_RUN.md                   构建与运行说明
    └── ...                                性能、交付和平台兼容文档
```

### 代码目录职责

| 路径 | 职责 |
| --- | --- |
| `include/cusignal/` | 公开模块 API、输入/输出类型、公共结果结构和聚合头 |
| `src/common/` | CPU/GPU 必须一致的参数检查、shape/axis、窗口和数学语义 |
| `src/cpu/` | CPU reference；FFT-heavy 路径使用 FFTW，作为正确性对照 |
| `src/zhongkexin/` | ZQ500 GPU 后端、设备 kernel、workspace、平台库和设备缓存 |
| `demo/task1_radar/` | Task1 输入构造、任务链、分步 timing/accuracy 和报告 |
| `demo/task2_features/` | Task2 输入构造、批处理、融合、跟踪和任务私有优化；不新增公开算子 |
| `tests/contracts/` | 算子集合、规模和任务步骤契约 |
| `tests/unit/` | 公开算子的独立 CPU/GPU 正确性测试 |
| `tests/platform/` | ZQ500 兼容性编译、运行库探针和平台检查 |

### CMake 构建关系

顶层 `CMakeLists.txt` 在 `CUSIGNAL_PLATFORM=ZHONGKEXIN` 下建立两个核心静态库：

```text
cusignal_cpu
├── src/cpu/
└── FFTW

cusignal_zx_gpu
├── src/zhongkexin/
├── ZQ500 runtime / FFT / BLAS / SOLVER 等兼容库
└── links cusignal_cpu
        │
        ├── task1_radar_demo
        ├── task2_features_demo
        ├── tests/unit/*
        └── tests/platform/*
```

### 两条任务调用链

- Task1 的 GPU 入口是 `demo/task1_radar/task1_gpu.cu`，公共算子主实现位于
  `src/zhongkexin/radartools.cu`；主链为
  `pulse_compression → pulse_doppler_shifted → power_map → ca_cfar → detect_peak`，
  `ambgfun` 为独立分支。
- Task2 的 GPU 输入和任务入口位于 `demo/task2_features/task2_gpu.cu`，任务私有批处理、
  融合、缓存和 fallback 位于 `task2_features_zx_gpu.cu`；核心数学仍通过
  `include/cusignal/`、`src/common/` 和 `src/zhongkexin/` 的公开算子完成。
- `demo/` 中的 helper、融合和阶段代码属于任务实现，不计为额外的公开算子；公开算子集合
  和任务步骤分别以 `tests/contracts/` 中的契约文件为准。

完整架构说明见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)，构建与运行入口见
[`docs/BUILD_AND_RUN.md`](docs/BUILD_AND_RUN.md)。

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
