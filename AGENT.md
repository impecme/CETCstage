# AGENT.md

本文是给后续编码代理和协作者使用的项目交接说明。

## Agent skills 自动路由

本项目已经安装并接入 `code-review`、`tdd`、`diagnosing-bugs` 和
`improve-codebase-architecture`。用户不需要记忆或显式输入 skill 名称；主智能体根据任务
意图自动采用对应方法，并继续遵守本文件及当前阶段计划。

| 任务信号 | 自动采用 | 执行要求 |
| --- | --- | --- |
| 审查改动、提交前检查、确认是否满足阶段计划 | `code-review` | 分开检查项目规范和阶段目标；默认以当前阶段计划为 spec |
| 新功能、修复缺陷、优化单个算子 | `tdd` | 先确认公开测试 seam，按一个测试、一个最小实现的纵向切片推进 |
| 报错、失败、性能回退、显存增长、数值异常 | `diagnosing-bugs` | 先建立快速、确定、可判红的复现命令；没有复现闭环时不猜根因 |
| 大文件拆分、模块边界或长期架构治理 | `improve-codebase-architecture` | 先只生成候选和报告；V5.5 最终验收前不得实施大范围架构重构 |

自动路由不表示每轮都运行全部 skill。一个任务只采用能解决当前问题的最小集合：

```text
正常算子优化：tdd -> code-review
出现失败或回退：diagnosing-bugs -> tdd 回归测试 -> code-review
阶段最终关闭：code-review
最终验收后的架构治理：improve-codebase-architecture
```

多智能体仍沿用
`docs/performance/v5_0/agent_collaboration.md` 中的 Agent A-H 分工。角色决定“谁分析”，
skill 决定“用什么方法分析”；辅助智能体默认只读，主智能体统一修改、验证和记录。
详细示例见 `docs/agent_skills_usage.md`。

## 项目定位

本仓库是 `CETC`，面向第十届集创赛“中科芯”企业命题的中科芯 ZQ500 信号处理加速库。

项目目标是构建一个接近 cuSignal 风格的算子库，当前包含：

- 用于正确性对照的 CPU 参考实现。
- 用于加速的 ZQ500 GPU 实现。
- 面向雷达检测和多域特征定位的任务级 demo。
- 单元测试、smoke 测试、benchmark 脚本、运行报告和提交文档。

实际项目根目录是：

```bash
/home/usr_04/CETC
```

不要把 IDE 当前打开的 Windows SSH 配置文件路径误认为项目根目录。

严禁读取、搜索、索引或同步项目根目录下的错误 SDK 副本：

```bash
/home/usr_04/CETC/zq500_sdk_full
/home/usr_04/CETC/.zq500_sdk_full.delete_me
```

这两个路径是多余且错误的目录，不属于项目输入，也不应作为中科芯 SDK 参考来源。当前因 sudoers 限制，隐藏目录 `.zq500_sdk_full.delete_me` 可能暂时无法删除；后续代理必须忽略它。需要参考从容器取出的 SDK 示例时，只能使用项目外部目录：

```bash
/home/usr_04/zq500_sdk_full
```

## 构建系统

顶层构建入口是 `CMakeLists.txt`。

关键目标：

- `cusignal_cpu`：CPU baseline 静态库。
- `cusignal_zx_gpu`：ZQ500 GPU 静态库，依赖 `cusignal_cpu`。
- `task1_radar_demo`：任务一雷达 demo。
- `task2_features_demo`：任务二特征定位 demo。
- `smoke_demo1`：最小编译和链接 smoke 测试。
- `tests/unit` 下的单元测试可执行文件。

依赖环境：

- CMake >= 3.18
- C++17
- 中科芯 ZQ500 SDK 与 `dlcc`
- 中科芯 ZQ500 runtime/FFT/BLAS/SOLVER 兼容库
- 安装在 `third_party/fftw/install` 下的 FFTW3

当前交付验收不再以 NVIDIA 路径为阶段关闭条件。中科芯 ZQ500 平台命令：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

如果缺少 FFTW：

```bash
./scripts/build/install_fftw.sh
```

中科芯容器内优先使用统一依赖准备脚本：

```bash
scripts/platform/prepare_zhongkexin_deps.sh --ensure-fftw
```

该脚本会检查 `python3`、`cmake >= 3.18`、`make`、`dlcc`、中科芯 SDK 头文件/库和 FFTW；缺少 FFTW 且启用 `--ensure-fftw` 时才要求 `tar`、`gcc`、`wget/curl`。Python 可视化/数据生成依赖来自 `scripts/platform/zhongkexin_python_requirements.txt`；完整迁移验收必须安装并验证 `numpy/matplotlib/scipy`，需要预下载 wheel 缓存时设置 `DOWNLOAD_PYTHON_WHEELS=1`，需要在容器内用户态安装时设置 `INSTALL_PYTHON_DEPS=1`。`scripts/platform/run_zhongkexin_stage1.sh` 默认会启用用户态 Python 依赖安装，并要求 demo 可视化依赖可用。

中科芯迁移的所有阶段都按“该阶段范围内的全部项目功能”关闭。不能只以核心 correctness 或单条 demo 通过作为阶段完成；凡属于当前阶段范围的构建、运行、数据生成、数值验证、非法/边界输入、报告字段、可视化图件、benchmark 图件和文档复现都必须实现、验证或作为明确平台限制入账。验收链路为 CPU reference + 中科芯 GPU，GPU 专指本服务器容器内 ZQ500；NVIDIA 路径不再作为阶段关闭条件。缺依赖、缺图件、缺报告或静默跳过项不能作为阶段完成状态保留。

每个中科芯迁移版本或阶段关闭时，必须在 `docs/submission/` 下新增或更新对应交付文档，命名采用 `READMEV<major>_<minor>.md` 风格，例如 `docs/submission/READMEV4_1.md`。交付文档必须按版本交付口径组织，至少包含版本目标、核心改动、解决的问题、验证结果、交付产物、完成判定和遗留风险；不能只更新设计文档或聊天记录。不要把交付文档写成“第几轮容器验证”的流水账，容器运行轮次只能作为证据摘要或进入迁移台账。

## 参赛者服务器使用要点

中科芯参赛环境的实际开发链路是：

```text
Windows VPN -> SSH 登录服务器 -> 进入本队 docker -> 在 docker 内开发和调试
```

协作时注意：

- 当前项目记录的用户 ID 为 `usr_04`，UID 为 `1006`，当前主机名为 `supervisor-X7850H0`，项目路径为 `/home/usr_04/CETC`。
- VPN、服务器账号和 docker 均按参赛队分配；不要把账号密码写入仓库或文档。
- VPN 客户端当前仅支持 Windows，且每天 `1:00-8:00` 关闭。
- 服务器宿主机只做文件中转和 docker 入口；项目代码应放在个人用户目录 `/home/usr_04`。
- 严禁修改公共路径和其他参赛者用户目录。
- 构建、运行、调试 `CETC` 项目应在本队 docker 内完成。

常用容器命令：

```bash
sudo docker ps -a
sudo docker ps
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
exit
```

每次进入 docker 后先初始化 SDK 环境：

```bash
source /zq500/sdk/env.sh
```

若 SDK 脚本报 `line 4: $1: unbound variable`，说明当前 shell/脚本环境触发了 nounset 或 SDK 需要占位参数，改用：

```bash
set +u
source /zq500/sdk/env.sh ""
set -u
```

检查 GPU：

```bash
dlsmi
```

SDK 示例和头文件路径：

```bash
/zq500/sdk/samples/
/zq500/cuda11/include
```

复赛说明文件位于 `复赛说明文件/`，迁移摘要位于 `docs/migration/zhongkexin/platform_notes.md`。迁移时必须把这些说明作为平台约束来源：

- `CUDA 11.7 runtime API.xlsx`：runtime API 部分覆盖，不要引入未确认支持的 memory pool、stream ordered allocator、external memory、IPC event、NvSci、graph capture 等高级 API。
- `CUDA 11.7 driver api.xlsx`：driver API 部分覆盖，第一阶段和第二阶段不要主动切到 driver API 实现 runtime 功能。
- `科学计算库实现列表.xlsx`：cuFFT 仅支持 2 的整数次幂点数，不足需要补 0；cuSOLVER `getrf` 的 pivot 参数不能传入 `nullptr`；当前主路径优先关注 cuFFT、cuBLAS、cuSOLVER。
- 任何因复赛说明引发的不兼容、待修改、fallback 或测试阈值调整，都必须记录到 `docs/migration/zhongkexin/change_log.md`。

文件传输：

```bash
# 本地 -> 服务器个人目录
scp -r C:\Users\27412\Desktop\project usr_04@10.110.12.10:/home/usr_04

# 服务器宿主机 -> 容器
sudo docker cp /home/usr_04/CETC gpu_04:/root/CETC

# 容器 -> 服务器宿主机
sudo docker cp gpu_04:/root/CETC /home/usr_04/CETC_from_container
```

V4.1 第一阶段统一验收入口：

```bash
scripts/platform/run_zhongkexin_stage1.sh
```

该脚本必须在本队 docker 内执行；它会自动 `source /zq500/sdk/env.sh`、运行 `scripts/platform/probe_zhongkexin.sh`、配置 `build-zx`、构建 `cusignal_cpu` / `cusignal_zx_gpu` / `task1_radar_demo` / `task2_features_demo`，最后运行 `scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3 --require-visualization-deps`。

V4.2 第二阶段统一验收入口：

```bash
scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2.log
```

该脚本必须在本队 docker 内执行；它会按 `docs/migration/zhongkexin/task_dependency_matrix.md` 批量运行 Task1/Task2 依赖算子 `accuracy`，写出 `data/reports/zhongkexin/stage2/latest_dependency_operator_report.*` 和逐算子日志。当前调试默认只跑 Task1/Task2 `L3` 一个规模的 scale 报告链路，避免中科芯 GPU 调试耗时过长；单规模通过后用 `STAGE2_SCALES=1,2,3,4,5,6` 打开全规模 sweep。取回日志后优先查看 `stage2.log` 和 `data/reports/zhongkexin/stage2/operators/*.log`。

如果当前只在服务器宿主机上，而用户可以在终端输入 sudo 密码，则使用宿主机同步入口。该流程用于把宿主机项目完全替换到容器 `/CETC`，包括删除容器中已经不存在于宿主机项目里的旧文件：

```bash
cd /home/usr_04/CETC
./copy_to_container.sh gpu_04
```

第一步在宿主机执行 `copy_to_container.sh`。该脚本会把项目复制到容器中的全新 incoming 目录，并在终端打印容器端替换脚本命令，例如：

```bash
/CETC.incoming.20260615124530/replace_container_project.sh /CETC
```

第二步进入容器后，先执行脚本打印的 `replace_container_project.sh` 命令。该命令会删除旧 `/CETC` 并将 incoming 目录替换为新的 `/CETC`，因此宿主机已删除的文件也会从容器项目中消失。

当前服务器 sudoers 可能允许 `docker ps -a` / `docker cp`，但禁止 `docker inspect` 或 `docker exec`。因此宿主机脚本不承担容器内命令执行、构建验证或报告拷回职责。用户按比赛允许的方式进入容器完成替换后，再执行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

如需把完整日志取回宿主机供 Codex 分析，容器内运行：

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

运行结束后回到宿主机终端执行：

```bash
cd /home/usr_04/CETC
sudo docker cp gpu_04:/CETC/stage4_full.log ./stage4_full.log
sudo docker cp gpu_04:/CETC/data/reports/zhongkexin/stage4 ./data/reports/zhongkexin/stage4_full_final
sudo docker cp gpu_04:/CETC/data/reports/unit/benchmarks/zhongkexin_stage4_full ./data/reports/unit/benchmarks/zhongkexin_stage4_full
```

常用日志查看命令：

```bash
tail -n 200 stage4_full.log
grep -nEi "error|failed|fatal|not found|undefined|file format" stage4_full.log
```

运行该统一脚本前不要再手动 source SDK；脚本内部已经用 `source /zq500/sdk/env.sh ""` 兼容当前容器环境。如需覆盖默认值，使用 `BUILD_DIR`、`TASK_SCALES`、`RUN_TASK_SWEEP`、`BENCH_MODULES`、`BENCH_OPERATORS`、`BENCH_SCALE_LEVELS`、`BENCH_WARMUP`、`BENCH_REPEAT` 环境变量。当前中科芯路径固定由 `dlcc --cuda-gpu-arch=dlgput64` 编译 ZQ500 GPU 源码，不再提供 NVIDIA 架构参数入口。

## 核心架构

公开 API 位于 `include/cusignal`。

聚合头文件是：

```cpp
#include "cusignal/cusignal.hpp"
```

主要命名空间：

- `cusignal::cpu::<module>`：CPU host 实现。
- `cusignal::zx_gpu_backend::<module>`：ZQ500 GPU 后端实现。
- `cusignal::core`：共享标量、张量和 device 容器类型。

当前公开 GPU 命名空间为 `zx_gpu_backend`。当前交付路径固定使用 `CUSIGNAL_PLATFORM=ZHONGKEXIN`；兼容差异应集中放在 `include/cusignal/core/platform_zx_gpu_compat.hpp` 或 `include/cusignal/core/platform_zx_gpu_libraries.hpp`。

项目采用统一单精度口径：

- `cusignal::core::Scalar = float`
- `cusignal::core::Complex = std::complex<float>`
- 实数数据语义为 `float32`
- 复数数据语义为 `complex64`

重要 host 类型：

- `core::RealSignal`
- `core::ComplexSignal`
- `core::RealArray`
- `core::ComplexArray`
- `core::IndexArray`

重要 device 类型：

- `core::ZxGpuRealSignal`
- `core::ZxGpuComplexSignal`
- `core::ZxGpuRealArray`
- `core::ZxGpuComplexArray`
- `core::ZxGpuIndexSignal`

`include/cusignal/core/types.hpp` 中的 `DeviceSignal` 和 `DeviceArray` 管理 ZQ500 device storage，并通过 `.get()` 把结果拷回 host。复数 device 存储使用 `float2` 打包。

## 源码布局

修改算子前先按这个结构理解代码：

- `include/cusignal/<module>/<module>.hpp`：公开 API 声明和结果结构。
- `src/common/<module>_detail.hpp`：共享参数校验、数学公式、shape/axis 逻辑。
- `src/cpu/<module>.cpp`：CPU 参考实现。
- `src/zhongkexin/<module>.cu`：ZQ500 GPU 实现、kernel、workspace 和 ZQ500 兼容库调用。
- `tests/unit/<module>`：单元测试支撑和算子测试入口。
- `data/reference/unit/<module>/<operator>`：静态 manifest、输入和期望输出数据。
- `scripts/data/generate_<module>_data.py`：reference/generated 数据生成脚本。

修改某个算子时，应同时检查以上相关层。

## 模块清单

当前公开模块包括：

- `bsplines`：cubic、quadratic、gauss_spline。
- `correlate`：correlate、correlate2d、correlation_lags。
- `demod`：fm_demod。
- `estimation`：CPU 和 CUDA KalmanFilter。
- `filter_design`：kaiser_beta、kaiser_atten、cmplx_sort、firwin、firwin2。
- `filtering`：wiener、FIR/IIR filtering、SOS filtering、Hilbert transforms、detrend、resample、channelizer、upfirdn。
- `peak_finding`：argrelextrema、argrelmin、argrelmax。
- `radartools`：pulse_compression、pulse_doppler、ambgfun、cfar_alpha、ca_cfar、mvdr。
- `spectral`：lombscargle、periodogram、welch、csd、spectrogram、stft、istft、coherence、vectorstrength。
- `waveforms`：chirp、gausspulse、sawtooth、square、unit_impulse。
- `wavelets`：qmf、morlet、ricker、morlet2、cwt。
- `windows`：get_window 和多种命名窗函数。

## 任务级 Demo

任务一位于 `demo/task1_radar`。

它模拟雷达目标检测和多普勒分析：

- 生成 chirp 模板。
- 构造包含目标、多普勒和噪声的接收脉冲矩阵。
- 执行脉冲压缩。
- 执行 pulse-Doppler 处理。
- 构造 range-Doppler power map。
- 执行 CA-CFAR 检测。
- 计算 ambiguity-function 输出。
- 对比 CPU/GPU 中间结果和最终结果。
- 输出 metrics、timings、validation 状态和样本。

任务二位于 `demo/task2_features`。

它模拟多域特征提取和定位：

- 生成多帧目标和干扰信号。
- 执行 filtering、correlation、FM demodulation、spectrogram、CWT、feature fusion、peak selection 和 Kalman tracking。
- 对比 CPU/GPU 输出。
- 输出任务级 validation、timing、resource usage 和可视化样本。

两个 demo 都支持 L1-L6 规模档位、repeat、非法输入检查和报告输出。

## 测试与验证

单元测试主入口：

```bash
./scripts/test/run_all_tests.sh
```

常用命令：

```bash
./scripts/test/run_all_tests.sh --list
./scripts/test/run_all_tests.sh --module spectral
./scripts/test/run_all_tests.sh --module radartools --operator ambgfun
./scripts/test/run_all_tests.sh --module filtering --case-set smoke
./scripts/test/run_all_tests.sh --module windows --no-build
```

任务级 demo 验证：

```bash
scripts/test/run_task_demos.sh --no-build --repeat 5 --require-visualization-deps
scripts/test/run_task_demos.sh --no-build --scale-sweep --repeat 3 --require-visualization-deps
scripts/test/run_task_demos.sh --no-build --repeat 2 --leak-check
```

最小 CTest smoke：

```bash
ctest --test-dir build -R '^smoke_demo1$' --output-on-failure
```

当前中科芯全量 benchmark 与作图统一使用 Stage4 入口：

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

如需单独重生成 benchmark 图件：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/zhongkexin_stage4_full/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/zhongkexin_stage4_full/figures \
  --figure-set all \
  --dpi 450
```

## 数据与报告

`data` 目录有三类职责：

- `data/reference`：纳入版本管理的静态测试参考数据。
- `data/generated`：运行期生成的测试/demo 输入和样本。
- `data/reports`：latest metrics、summary、timings、benchmark CSV 和 figures。

单元测试参考数据结构：

```text
data/reference/unit/<module>/<operator>/
├─ manifest.json
├─ input/
└─ expected/
```

运行生成的输出和报告通常使用 `latest_*` 命名。除非用户明确要求保留，否则这些文件应视为可被覆盖的运行产物。

清理生成数据和报告：

```bash
./scripts/clean_data.sh
```

## 实现约定

尽量沿用现有模式：

- 保持 CPU 和 ZQ500 GPU API 行为一致。
- CPU/ZQ500 GPU 都需要的公式和校验逻辑放到 `src/common/*_detail.hpp`。
- 公开声明放在对应的 `include/cusignal/<module>/<module>.hpp`。
- 除非任务明确要求，否则保持单精度策略。
- 保留近零参考值下的 `mixed_error` 报告口径。
- 优先复用现有 helper 类型和 shape/axis 工具。
- 修复算子时不要引入无关重构。

ZQ500 GPU 代码约定：

- 尽量使用现有 device container 类型。
- 检查 ZQ500 runtime、cuFFT、cuBLAS 和 cuSOLVER 兼容 API 返回值。
- 修改性能敏感路径时保留 thread-local workspace/cache 模式。
- 热路径中避免重复分配，优先扩展已有 workspace。

测试约定：

- 按需新增或更新 `tests/unit/<module>` 下的测试支撑。
- 行为变化时同步更新 reference manifest/data。
- 先跑最窄相关测试；涉及共享行为时再扩大测试范围。

## 中科芯迁移记录硬规则

中科芯迁移期间，AGENT 以本节为最高优先级迁移纪律之一执行。迁移过程中发现的不兼容点、需要修改点、已修改点、暂缓点和 fallback，必须全部记录到 `docs/migration/zhongkexin/change_log.md`。

必须记录的情况：

- 发现中科芯平台与既有 CUDA 代码、SDK 示例、runtime、库 target、头文件、链接方式、数值结果、性能、工具链或运行行为上的差异。
- 发现需要修改源码、CMake、脚本、测试、demo、报告或文档的地方。
- 实施了任何中科芯相关修改。
- 引入、保留或删除 fallback。
- 调整 public API、报告字段、测试阈值、性能 gate、验证命令或构建入口。

每条记录至少包含：

- 编号。
- 发现阶段。
- 模块或文件。
- 问题现象。
- 原因判断。
- 计划修改。
- 实际修改。
- 对 CPU reference 与中科芯 ZQ500 GPU 链路的影响范围。
- 验证命令和验证结果。
- 当前状态和后续处理阶段。

执行要求：

- 即使暂时不修，也必须先记录。
- 修改前记录“计划修改”，修改后补充“实际修改”和“验证结果”。
- 每个阶段关闭前，必须核对台账，确认没有只存在于聊天记录或终端输出中的问题。
- 更新 `docs/migration/zhongkexin/change_log.md` 后，同步检查 `docs/migration/zhongkexin/status.md` 是否需要更新。

## 项目注意事项

- 中科芯迁移协作信息位于 `docs/migration/zhongkexin/README.md` 和 `docs/migration/zhongkexin/status.md`。
- 有些测试存在 CMake target，但在 `scripts/test/run_all_tests.sh` 的 shell 注册表中被注释掉；判断默认脚本是否会运行某测试时，要同时检查 CMake 和脚本。
- `README.md` 是最高层工程说明；构建、demo、benchmark、validation 出现重大变化时应保持同步。
- `docs` 下包含比赛设计和提交文档；除非任务与文档或交付物相关，否则不要随意修改。
