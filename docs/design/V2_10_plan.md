# V2.10 `radartools` 模块完整接入

## Summary

- 当前版本定为 `V2.10`。本轮把 `radartools` 按现有主线模式完整接入，不做“只补接口”或“只补 CPU”。
- 行为基准固定为仓内 Python 实现：
  - `cusignal/python/cusignal/radartools/radartools.py`
  - `cusignal/python/cusignal/radartools/beamformers.py`
  - `cusignal/python/cusignal/test/test_radartools.py`
- 约束保持不变：
  - 不改公开函数签名和接口模式。
  - `cpu::*` 继续 host in/out。
  - `zx_gpu_backend::*` 继续 host/device 双输入、device 输出。
  - `include/` 注释块结构和风格保留，只删除“占位返回零张量”之类已失真描述。
  - 测试、数据、报告组织对齐当前 canonical unit schema。

## Key Changes

### 1. 实现层

- 重写 `src/cpu/radartools.cpp` 和 `src/zhongkexin/radartools.cu`，完整实现以下公开 API：
  - `pulse_compression`
  - `pulse_doppler`
  - `ambgfun` 两个重载
  - `cfar_alpha`
  - `ca_cfar` 1D / 2D
  - `mvdr`
- 新增 `src/common/radartools_detail.hpp`，承接公共校验、轴生成、归一化、窗口解析、CFAR 参考单元计数、协方差与小型线性代数辅助。
- `pulse_compression`
  - CPU 用 FFTW，CUDA 用 `cuFFT`。
  - 语义按 Python：先可选加窗，再可选归一化模板，再做逐脉冲 matched filter。
  - `nfft=0` 时默认 `samples_per_pulse`，输出 shape 固定为 `{num_pulses, nfft}`。
- `pulse_doppler`
  - CPU 用 FFTW，CUDA 用 `cuFFT`。
  - 沿 slow-time 轴做 FFT，窗口长度固定对齐 `num_pulses`。
  - `nfft=0` 时默认 `num_pulses`，输出 shape 固定为 `{nfft, samples_per_pulse}`。
  - 实现固定采用“转置到连续批处理布局 -> batched FFT -> 转置回结果”。
- `ambgfun`
  - 单输入重载直接委托双输入重载。
  - 保持 Python 数值语义：`cut in {"2d","delay","doppler"}`，先做 L2 归一化。
  - `2d`：生成延迟移位矩阵后做 batched IFFT。
  - `delay`：固定 delay，输出随 doppler 变化的一维切片。
  - `doppler`：固定 doppler，输出随 delay 变化的一维切片。
  - 轴约定固定：
    - `delay_axis[i] = (i - (xlen - 1)) / fs`
    - `doppler_axis = fftshift(fftfreq(nfreq, 1/fs))`
    - `cut="delay"` 返回 `values + doppler axis`
    - `cut="doppler"` 返回 `values + delay axis`
  - `prf` 按 Python 基准保留参数与合法性校验，但不引入额外数值分支。
- `cfar_alpha`
  - 保留现有公式实现和异常语义。
- `ca_cfar`
  - 1D / 2D 都按 Python 版 CA-CFAR 语义实现。
  - CPU 使用前缀和 / 积分图。
  - CUDA 使用 device-native prefix-sum / integral-image 路径和阈值 kernel。
  - `threshold` 与 `detections` 均返回 `RealArray` / `ZxGpuRealArray`；`detections` 固定写 `0.0 / 1.0`。
  - 2D 参考单元计数按 Python 公式，不沿用当前 placeholder 的错误计数。
- `mvdr`
  - CPU：
    - `calc_cov=true` 时按 `cp.cov` 语义先做按传感器行去均值协方差。
    - 之后用复数高斯消元 / LU 求解 `R * wB = sv`，再做 `w = wB / (sv^H wB)`。
  - CUDA：
    - `calc_cov=true` 时用 kernel 去均值，`cuBLAS` 做协方差矩阵构造。
    - 用 `cuSOLVER` 做复数线性方程求解，不走 host 回退。
    - 输出 shape 恢复为 `sv` 原 shape。
  - 维度语义固定：
    - `calc_cov=true`：`x` 为 `{num_sensors, num_snapshots}`，要求 `num_sensors <= num_snapshots`
    - `calc_cov=false`：`x` 为方形协方差矩阵
    - `sv` 的元素数必须等于 `num_sensors`

### 2. ZQ500 GPU 实现与显存复用

- `src/zhongkexin/radartools.cu` 引入 `thread_local RadartoolsWorkspace`，按算子族拆分 scratch：
  - `PulseWorkspace`：窗口、模板频谱、批量 FFT 输入输出、转置缓冲、`cuFFT` plan
  - `AmbgfunWorkspace`：归一化输入、移位矩阵、频谱缓冲、轴缓冲、`cuFFT` plan
  - `CfarWorkspace`：prefix-sum / integral-image 缓冲、阈值缓冲、检测缓冲
  - `BeamformerWorkspace`：去均值缓冲、协方差缓冲、RHS、pivot/info、输出缓冲
- workspace 只复用内部 scratch 和 plan，不把内部存储别名返回给调用方；公开返回值始终是独立 device 对象。
- `g_last_kernel_ms` 扩展为累积整个 GPU 计算阶段：
  - kernel
  - `cuFFT`
  - `cuBLAS`
  - `cuSOLVER`
- `gpu_kernel_perf` 不能再系统性为 `0.000`。

### 3. 构建、测试、数据与脚本

- 构建层：
  - `cusignal_zx_gpu` 新增链接 `CUDA::cublas` 和 `CUDA::cusolver`。
  - 若当前 Toolkit 缺少这两个 target，则配置阶段直接失败。
- 新增 `tests/unit/radartools/`，每个公开 API 一个 runner：
  - `pulse_compression`
  - `pulse_doppler`
  - `ambgfun`
  - `cfar_alpha`
  - `ca_cfar`
  - `mvdr`
- `tests/unit/CMakeLists.txt` 接入 `add_subdirectory(radartools)`。
- `scripts/test/run_all_tests.sh` 新增 `radartools` 注册项，支持 `--module radartools`。
- `scripts/clean_data.sh` 不需要特殊修改，当前通用清理逻辑已覆盖新模块。
- 数据组织对齐现有 schema：
  - `data/reference/unit/radartools/<op>/manifest.json`
  - `data/generated/unit/radartools/<op>/manifest.json`
  - `data/reports/unit/radartools/<op>/...`
- accuracy 数据由新脚本 `scripts/data/generate_radartools_data.py` 生成并提交入库，基于仓内 Python `cusignal`。
- perf 输入采用运行时生成，`--emit-report` 时再落盘到 `generated/input`。
- `output_samples` 命名固定：
  - `pulse_compression` / `pulse_doppler` / `mvdr`：`__cpu__signal.csv`、`__gpu__signal.csv`
  - `ambgfun` cut：`__cpu__values.csv`、`__cpu__axis.csv`；surface：另加 `delay_axis`、`doppler_axis`
  - `cfar_alpha`：`__cpu__value.csv`、`__gpu__value.csv`
  - `ca_cfar`：`__cpu__threshold.csv`、`__gpu__threshold.csv`，以及 `detections`
- `reports.artifacts` 同步登记 CPU/GPU 两套样本。
- `latest_summary.md`、`latest_metrics.json`、`latest_cases.csv` 不改 schema。

### 4. 文档与版本

- 新增：
  - `docs/design/V2_10_plan.md`
  - `docs/submission/READMEV2_10.md`
- 更新 `README.md`：
  - 当前版本改为 `V2.10`
  - 入口指向 `READMEV2_10.md`
  - 当前状态说明加入 `radartools` 已接入 unit 链路
- 旧版本文档保留，不复用为当前版本说明。

## Public Interfaces

- 不改任何 `radartools` 公开函数签名或返回类型。
- 不新增新的公开类型。
- `include/cusignal/radartools/radartools.hpp` 只做注释修正：
  - 去掉 placeholder/零张量描述
  - 保留原注释块结构和风格
- 构建接口变化仅一项：
  - `cusignal_zx_gpu` 额外依赖 `CUDA::cublas` 与 `CUDA::cusolver`

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
  - 单独确认全部 `radartools_*` target 编译通过
- 模块回归：
  - `./scripts/test/run_all_tests.sh --module radartools`
  - `./scripts/test/run_all_tests.sh --module radartools --emit-report`
- accuracy 重点：
  - `pulse_compression`：基础 case、`normalize=true`、命名窗、显式窗、`nfft` 改写
  - `pulse_doppler`：无窗/有窗、`nfft` 改写、输出 shape 与 Python 一致
  - `ambgfun`：单输入/双输入、`2d/delay/doppler` 三类 cut、轴值校验、非法 `cut/fs/prf`
  - `cfar_alpha`：标量基准值
  - `ca_cfar`：直接复用 Python 测试思路，覆盖 1D/2D、ones、点目标检测、非法 guard/reference 组合
  - `mvdr`：`calc_cov=true/false`、shape mismatch、`num_sensors > num_snapshots` 失败、权重与 Python 基准一致
- perf 重点：
  - 每个 operator 至少 1 个 perf case
  - `gpu_e2e_perf` 继续保持 host 输入 + H2D + GPU 计算，不包含 `get()`
  - `gpu_kernel_perf` 对所有 GPU 算子为真实非零计算时间
  - `--emit-report` 后确认 `generated/input` 和 `output_samples` 都落盘，且 CPU/GPU 两份样本齐全
- 全量回归：
  - `./scripts/test/run_all_tests.sh --emit-report`

## Assumptions

- 本轮版本固定为 `V2.10`。
- `radartools` 的实现范围就是当前头文件中声明的全部公开 API，不额外扩展任务级 demo。
- 数值行为优先级固定为：
  1. 仓内 Python `radartools.py` / `beamformers.py`
  2. 仓内 Python `test_radartools.py`
  3. 已提交的 reference 数据
- `ambgfun` 保持 Python 数值路径，因此 `prf` 仅保留 API 兼容与参数校验，不额外引入偏离 Python 的数值分支。
- `mvdr` 的 ZQ500 GPU 路径允许新增 `cuBLAS/cuSOLVER` 构建依赖；这是本轮唯一新增的 CUDA 数值依赖。
