# AGENT.md

本文是给后续编码代理和协作者使用的项目交接说明。

## 项目定位

本仓库是 `CETC`，面向第十届集创赛“中科芯”企业命题的 CUDA C++ 信号处理加速库。

项目目标是构建一个接近 cuSignal 风格的算子库，当前包含：

- 用于正确性对照的 CPU 参考实现。
- 用于加速的 CUDA 实现。
- 面向雷达检测和多域特征定位的任务级 demo。
- 单元测试、smoke 测试、benchmark 脚本、运行报告和提交文档。

实际项目根目录是：

```bash
/home/usr_04/CETC
```

不要把 IDE 当前打开的 Windows SSH 配置文件路径误认为项目根目录。

## 构建系统

顶层构建入口是 `CMakeLists.txt`。

关键目标：

- `cusignal_cpu`：CPU baseline 静态库。
- `cusignal_cuda`：CUDA 静态库，依赖 `cusignal_cpu`。
- `task1_radar_demo`：任务一雷达 demo。
- `task2_features_demo`：任务二特征定位 demo。
- `smoke_demo1`：最小编译和链接 smoke 测试。
- `tests/unit` 下的单元测试可执行文件。

依赖环境：

- CMake >= 3.18
- C++17 / CUDA17
- CUDA Toolkit
- cuFFT static libraries
- cuBLAS
- cuSOLVER
- 安装在 `third_party/fftw/install` 下的 FFTW3

默认 CUDA 架构是 `80`。需要时可通过 `CUDA_ARCH=...` 覆盖。

常用 NVIDIA/CUDA 构建命令：

```bash
./scripts/build/build_v1.sh
cmake --build build --target cusignal_cpu cusignal_cuda --parallel
cmake --build build --target smoke_demo1 --parallel
```

中科芯 CUDA 兼容平台命令：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

如果缺少 FFTW：

```bash
./scripts/build/install_fftw.sh
```

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

复赛说明文件位于 `复赛说明文件/`，迁移摘要位于 `docs/design/zhongkexin_rematch_notes.md`。迁移时必须把这些说明作为平台约束来源：

- `CUDA 11.7 runtime API.xlsx`：runtime API 部分覆盖，不要引入未确认支持的 memory pool、stream ordered allocator、external memory、IPC event、NvSci、graph capture 等高级 API。
- `CUDA 11.7 driver api.xlsx`：driver API 部分覆盖，第一阶段和第二阶段不要主动切到 driver API 实现 runtime 功能。
- `科学计算库实现列表.xlsx`：cuFFT 仅支持 2 的整数次幂点数，不足需要补 0；cuSOLVER `getrf` 的 pivot 参数不能传入 `nullptr`；当前主路径优先关注 cuFFT、cuBLAS、cuSOLVER。
- 任何因复赛说明引发的不兼容、待修改、fallback 或测试阈值调整，都必须记录到 `docs/design/zhongkexin_migration_change_log.md`。

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

该脚本必须在本队 docker 内执行；它会自动 `source /zq500/sdk/env.sh`、运行 `scripts/platform/probe_zhongkexin.sh`、配置 `build-zx`、构建 `cusignal_cpu` / `cusignal_cuda` / `task1_radar_demo` / `task2_features_demo`，最后运行 `scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3`。

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
scripts/platform/run_zhongkexin_stage1.sh 2>&1 | tee stage1.log
```

运行结束后回到宿主机终端执行：

```bash
cd /home/usr_04/CETC
sudo docker cp gpu_04:/CETC/stage1.log ./stage1.log
```

常用日志查看命令：

```bash
tail -n 200 stage1.log
grep -nEi "error|failed|fatal|not found|undefined|file format" stage1.log
```

运行该统一脚本前不要再手动 source SDK；脚本内部已经用 `source /zq500/sdk/env.sh ""` 兼容当前容器环境。如需覆盖默认值，使用 `BUILD_DIR`、`CUDA_ARCH`、`REPEAT` 环境变量。当前中科芯路径默认使用 `CUDA_ARCH=OFF`，不要手动设置 `CUDA_ARCH=80`，否则 CMake 可能生成 NVIDIA 专用的 `sm_80` 参数。

## 核心架构

公开 API 位于 `include/cusignal`。

聚合头文件是：

```cpp
#include "cusignal/cusignal.hpp"
```

主要命名空间：

- `cusignal::cpu::<module>`：CPU host 实现。
- `cusignal::cuda_backend::<module>`：CUDA 后端实现。
- `cusignal::core`：共享标量、张量和 device 容器类型。

第一阶段中科芯迁移会继续保留 `cuda_backend` 命名空间。平台选择由 `CUSIGNAL_PLATFORM=NVIDIA|ZHONGKEXIN` 控制；兼容差异应集中放在 `include/cusignal/core/platform_cuda_compat.hpp` 或 `include/cusignal/core/platform_cuda_libraries.hpp`，不要通过修改公开 API 解决。

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

- `core::CudaRealSignal`
- `core::CudaComplexSignal`
- `core::CudaRealArray`
- `core::CudaComplexArray`
- `core::CudaIndexSignal`

`include/cusignal/core/types.hpp` 中的 `DeviceSignal` 和 `DeviceArray` 管理 CUDA device storage，并通过 `.get()` 把结果拷回 host。复数 device 存储使用 `float2` 打包。

## 源码布局

修改算子前先按这个结构理解代码：

- `include/cusignal/<module>/<module>.hpp`：公开 API 声明和结果结构。
- `src/common/<module>_detail.hpp`：共享参数校验、数学公式、shape/axis 逻辑。
- `src/cpu/<module>.cpp`：CPU 参考实现。
- `src/cuda/<module>.cu`：CUDA 实现、kernel、workspace 和 CUDA 库调用。
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
scripts/test/run_task_demos.sh --no-build --repeat 5
scripts/test/run_task_demos.sh --no-build --scale-sweep --repeat 3
scripts/test/run_task_demos.sh --no-build --repeat 2 --leak-check
```

最小 CTest smoke：

```bash
ctest --test-dir build -R '^smoke_demo1$' --output-on-failure
```

全量 benchmark：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops
```

大规模 GPU profile：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

生成 benchmark 图件：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
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

- 保持 CPU 和 CUDA API 行为一致。
- CPU/CUDA 都需要的公式和校验逻辑放到 `src/common/*_detail.hpp`。
- 公开声明放在对应的 `include/cusignal/<module>/<module>.hpp`。
- 除非任务明确要求，否则保持单精度策略。
- 保留近零参考值下的 `mixed_error` 报告口径。
- 优先复用现有 helper 类型和 shape/axis 工具。
- 修复算子时不要引入无关重构。

CUDA 代码约定：

- 尽量使用现有 device container 类型。
- 检查 CUDA、cuFFT、cuBLAS 和 cuSOLVER 返回值。
- 修改性能敏感路径时保留 thread-local workspace/cache 模式。
- 热路径中避免重复分配，优先扩展已有 workspace。

测试约定：

- 按需新增或更新 `tests/unit/<module>` 下的测试支撑。
- 行为变化时同步更新 reference manifest/data。
- 先跑最窄相关测试；涉及共享行为时再扩大测试范围。

## 中科芯迁移记录硬规则

中科芯迁移期间，AGENT 以本节为最高优先级迁移纪律之一执行。迁移过程中发现的不兼容点、需要修改点、已修改点、暂缓点和 fallback，必须全部记录到 `docs/design/zhongkexin_migration_change_log.md`。

必须记录的情况：

- 发现中科芯平台与 NVIDIA CUDA 在编译器、runtime、库 target、头文件、链接方式、数值结果、性能、工具链或运行行为上的差异。
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
- 是否影响 NVIDIA 路径。
- 验证命令和验证结果。
- 当前状态和后续处理阶段。

执行要求：

- 即使暂时不修，也必须先记录。
- 修改前记录“计划修改”，修改后补充“实际修改”和“验证结果”。
- 每个阶段关闭前，必须核对台账，确认没有只存在于聊天记录或终端输出中的问题。
- 更新 `docs/design/zhongkexin_migration_change_log.md` 后，同步检查 `docs/design/zhongkexin_migration_status.md` 是否需要更新。

## 项目注意事项

- 中科芯迁移协作信息位于 `docs/design/zhongkexin_migration_plan.md` 和 `docs/design/zhongkexin_migration_status.md`。
- 有些测试存在 CMake target，但在 `scripts/test/run_all_tests.sh` 的 shell 注册表中被注释掉；判断默认脚本是否会运行某测试时，要同时检查 CMake 和脚本。
- `README.md` 是最高层工程说明；构建、demo、benchmark、validation 出现重大变化时应保持同步。
- `docs` 下包含比赛设计和提交文档；除非任务与文档或交付物相关，否则不要随意修改。
