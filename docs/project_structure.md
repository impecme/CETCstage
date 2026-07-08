# CETC 项目结构、模块与验证入口

本文保存项目架构、源码布局、模块清单、demo、测试、数据和报告约定。`AGENT.md` 只保留必须每轮看到的摘要。

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

当前中科芯全量 benchmark 与作图统一使用 Stage4 入口，完整命令见 `docs/platform/zhongkexin_runtime.md`。

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
