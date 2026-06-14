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
scripts/platform/probe_zhongkexin.sh
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_cuda task1_radar_demo task2_features_demo --parallel
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3
```

如果缺少 FFTW：

```bash
./scripts/build/install_fftw.sh
```

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

## 项目注意事项

- 中科芯迁移协作信息位于 `docs/design/zhongkexin_migration_plan.md` 和 `docs/design/zhongkexin_migration_status.md`。
- 有些测试存在 CMake target，但在 `scripts/test/run_all_tests.sh` 的 shell 注册表中被注释掉；判断默认脚本是否会运行某测试时，要同时检查 CMake 和脚本。
- `README.md` 是最高层工程说明；构建、demo、benchmark、validation 出现重大变化时应保持同步。
- `docs` 下包含比赛设计和提交文档；除非任务与文档或交付物相关，否则不要随意修改。
