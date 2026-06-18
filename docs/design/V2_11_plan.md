# V2.11 `spectral` 模块完整接入

## Summary

- 当前版本按顺序推进为 `V2.11`。本轮把 `spectral` 按现有主线模式完整接入，不做“只补 CPU”或“只补接口”。
- 行为基准固定为仓内 Python 版：
  - `cusignal/python/cusignal/spectral_analysis/spectral.py`
  - `cusignal/python/cusignal/test/test_spectral_analysis.py`
- 约束保持不变：
  - 不改公开函数签名和接口模式。
  - `cpu::*` 继续 host in/out。
  - `zx_gpu_backend::*` 继续 host/device 双输入、device 输出。
  - `include/` 注释块结构和风格保留，只删除占位语义。
  - 测试、数据、报告组织继续对齐当前 canonical unit schema。
- 本轮只实现当前头文件里已有的公开 API：
  - `lombscargle`
  - `periodogram`
  - `welch`
  - `csd`
  - `spectrogram`
  - `stft`
  - `istft`
  - `coherence`
  - `vectorstrength`
- 不额外新增 Python 里存在但头文件未暴露的接口，如 `check_COLA` / `check_NOLA`。

## Key Changes

### 1. 公共实现与数值基线

- 新增 `src/common/spectral_detail.hpp`，统一承接：
  - 轴与 shape 规范化
  - `nperseg/noverlap/nfft` 默认推导
  - window 解析
  - `detrend` 规则
  - one-sided / two-sided 频率轴生成
  - scaling 与 average 规则
  - segment 提取、boundary/padded 规则
  - overlap-add 与 iSTFT 归一化
- 共享实现核心按“一个内部谱分析/STFT 核心 + 多个公开 API 封装”组织，避免 `periodogram/welch/csd/spectrogram/stft/coherence` 各写一套。
- FFT-heavy 路径继续沿用当前仓库约定：
  - CPU 使用 `third_party/fftw/install` 的 FFTW
  - CUDA 使用系统 CUDA Toolkit 的 `cuFFT`
- 不新增公开类型；继续复用 `spectral_api::*Result` 结构。

### 2. CPU 实现

- 重写 `src/cpu/spectral.cpp`，补齐全部公开 API。
- `lombscargle`
  - 直接按 Python/SciPy 语义实现非均匀采样周期图。
  - 支持 `precenter` 与 `normalize`。
- `periodogram`
  - 实现 real-input 子集。
  - 支持 `window`、`nfft`、`detrend`、`return_onesided`、`scaling`、`axis`。
- `welch` / `csd`
  - 建立在共享分段谱核心之上。
  - 支持 `average="mean"/"median"`。
- `spectrogram`
  - 支持 `mode="psd"/"complex"/"magnitude"/"angle"/"phase"`。
  - 返回 `frequencies/times/values`。
- `stft` / `istft`
  - 支持 `boundary="even"/"odd"/"constant"/"zeros"/"none"`、`padded`、`input_onesided`、`time_axis/freq_axis`。
  - `istft` 使用 overlap-add 和 window-squared 归一化。
- `coherence`
  - 建立在 `welch + csd` 上，按 `|Pxy|^2 / (Pxx * Pyy)` 实现。
- `vectorstrength`
  - 同时支持标量周期和周期数组。
  - 返回 `strength` 与 `phase`。
- 重要范围约束：
  - 以当前 C++ 头文件为准，`periodogram/welch/csd/spectrogram/stft/coherence` 只实现 `RealArray` 输入子集。
  - 不为对齐 Python 测试去扩展到复数输入签名。

### 3. ZQ500 GPU 实现与显存复用

- 重写 `src/zhongkexin/spectral.cu`，全部改为真实 device-native 实现，不再返回零张量。
- 引入 `thread_local SpectralWorkspace`，按算子族复用 scratch：
  - `LombWorkspace`：输入归一化、输出缓冲
  - `SegmentWorkspace`：window、segment、detrend、batch FFT 缓冲
  - `SpectrogramWorkspace`：mode 转换缓冲、频率/时间轴缓冲
  - `IstftWorkspace`：overlap-add 缓冲、window-squared 累加缓冲
- `g_last_kernel_ms` 改为真实累计整个 GPU 计算阶段：
  - kernel
  - `cuFFT`
  - 必要的 device reduction
- `gpu_kernel_perf` 不允许系统性为 `0.000`。
- 各 API 的 GPU 实现原则：
  - `lombscargle`：按频率点并行计算，直接 device 输出。
  - `periodogram/welch/csd/spectrogram/stft/coherence`：全部建立在共享分段 + batched `cuFFT` 核心上。
  - `istft`：GPU 上完成逆变换、重叠相加和归一化，不回退 CPU。
  - `vectorstrength`：GPU 上做复指数累加与相位/模长归约，不回退 CPU。
- 保持 `V2.4/V2.5` 语义：
  - host 输入自动 H2D
  - device 输入直接复用
  - 输出统一返回 device 对象
  - `gpu_e2e_perf` 不包含 `get()`

### 4. 测试、数据、脚本与文档

- 新增 `tests/unit/spectral/`，每个公开 API 一个 runner：
  - `lombscargle`
  - `periodogram`
  - `welch`
  - `csd`
  - `spectrogram`
  - `stft`
  - `istft`
  - `coherence`
  - `vectorstrength`
- `tests/unit/CMakeLists.txt` 接入 `add_subdirectory(spectral)`。
- `scripts/test/run_all_tests.sh` 新增 `spectral` 注册项，支持 `--module spectral`。
- `scripts/clean_data.sh` 保持现有通用清理逻辑，不单独定制。
- 新增数据脚本：
  - `scripts/data/generate_spectral_data.py`
- 数据组织继续对齐现有 schema：
  - `data/reference/unit/spectral/<op>/manifest.json`
  - `data/generated/unit/spectral/<op>/manifest.json`
  - `data/reports/unit/spectral/<op>/...`
- accuracy 数据提交入库；perf 输入继续运行时生成，`--emit-report` 时写回 `generated/input`。
- `output_samples` 命名按当前规范：
  - 单实值谱：`__cpu__frequencies.csv`、`__cpu__values.csv`，GPU 同理
  - 复值谱/STFT：`__cpu__frequencies.csv`、`__cpu__values.csv`、必要时 `times`
  - `istft`：`__cpu__times.csv`、`__cpu__signal.csv`，GPU 同理
  - `vectorstrength`：`__cpu__strength.csv`、`__cpu__phase.csv`，GPU 同理
- 文档新增：
  - `docs/design/V2_11_plan.md`
  - `docs/submission/READMEV2_11.md`
- 更新 `README.md`：
  - 当前版本改为 `V2.11`
  - 入口指向 `READMEV2_11.md`
  - 当前状态说明加入 `spectral` 已接入 unit 链路

## Public Interfaces

- 不改任何现有公开函数签名或返回类型。
- 不新增新的公开类型。
- `include/cusignal/spectral/spectral.hpp` 只做注释修正：
  - 去掉 placeholder/零张量描述
  - 保留原注释块结构和风格
- 重要兼容说明：
  - 实现范围严格以当前头文件签名为准。
  - 即使 Python 基线支持更多输入类型，C++ 侧也不扩签名；reference 和 unit case 只覆盖当前签名可表达的子集。

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
  - 单独确认全部 `spectral_*` target 编译通过
- 模块回归：
  - `./scripts/test/run_all_tests.sh --module spectral`
  - `./scripts/test/run_all_tests.sh --module spectral --emit-report`
- accuracy 重点：
  - `lombscargle`：`precenter/normalize` 组合、非均匀采样、不同输出频率长度
  - `periodogram`：`window`、`scaling`、`return_onesided`、`axis`
  - `welch` / `csd`：`nperseg/noverlap/nfft`、`average=mean/median`
  - `spectrogram`：`mode` 五种分支、`times/frequencies` 正确性
  - `stft` / `istft`：`boundary`、`padded`、`input_onesided`、重建误差
  - `coherence`：与 `welch/csd` 组合结果一致
  - `vectorstrength`：标量周期和周期数组
- perf 重点：
  - 每个 operator 至少 1 个 perf case
  - `gpu_e2e_perf` 保持 host 输入 + H2D + GPU 计算，不包含 `get()`
  - `gpu_kernel_perf` 对全部 ZQ500 GPU 算子为真实非零时间
  - `--emit-report` 后确认 `generated/input` 与 `output_samples` 都落盘，且 CPU/GPU 两套样本齐全
- 全量回归：
  - `./scripts/test/run_all_tests.sh --emit-report`

## Assumptions

- 本轮版本固定为 `V2.11`。
- `spectral` 的实现范围严格等于当前头文件中已声明的公开 API。
- 数值行为优先级固定为：
  1. `cusignal/python/cusignal/spectral_analysis/spectral.py`
  2. `cusignal/python/cusignal/test/test_spectral_analysis.py`
  3. 已提交的 reference 数据
- 对 Python 测试里存在但当前 C++ 头文件无法表达的输入类型，reference 与 unit case 只覆盖当前 C++ 签名可表达的子集，不扩接口。
- 本轮不新增 `check_COLA` / `check_NOLA` 等头文件未暴露接口。
