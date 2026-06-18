# V2.13 `correlate` / `demod` / `estimation` / `peak_finding` 完整接入

## Summary

- 本轮覆盖现有 `V2.13` 文档，把这 4 个模块按当前主线模式完整接入：真实 CPU/ZQ500 GPU 实现、单算子单入口 unit tests、canonical data/report schema、一键测试与版本文档。
- 公开接口模式保持现状：
  - `cpu::*` 继续 host in/out
  - `zx_gpu_backend::*` 继续 host/device 双输入、device 输出
  - 不新增公开类型，不改函数签名
- 版本上的额外约束已锁定：
  - 直接覆盖现有 `V2.13`
  - `estimation::KalmanFilter` 保持当前接口，不做公开类型升级
  - `KalmanFilter(dtype)` 这轮只接受 `"float32"`，传 `"float64"` 显式报不支持
- 代码、测试、数据、文档都按 `wavelets / spectral / radartools / filtering` 的现有成熟模式落地。

## Key Changes

### 1. `correlate`

- 重写 `src/cpu/correlate.cpp` 和 `src/zhongkexin/correlate.cu`，完整实现：
  - `correlate`
  - `correlate2d`
  - `correlation_lags`
- `correlate`
  - `method="fft"` 与 `method="auto"` 走 FFT 路径，支持当前头文件声明的 N 维 real/complex 输入。
  - `method="direct"` 按 Python cuSignal 语义只支持 1D；对 rank>1 显式报错。
  - `auto` 规则固定为：1D 且规模较小时走 direct，其余走 fft。
  - real/complex 都按 `convolve(in1, reverse(conj(in2)))` 的相关定义实现。
- `correlate2d`
  - real/complex 都做真实 2D 相关。
  - `boundary` 完整支持 `"fill" / "wrap" / "symm"`，固定走空间域实现，不走 FFT。
  - `mode="full/same/valid"` 语义对齐 SciPy。
- `correlation_lags`
  - 精确对齐 Python/SciPy 当前公式，尤其 `same` 和 `valid` 的偶奇长度切片规则。
  - CUDA 返回 `ZxGpuIndexSignal`，不回退 host。
- ZQ500 GPU 侧显存复用：
  - 引入 `thread_local CorrelateWorkspace`
  - 复用 FFT 输入输出缓冲、反转/conj 缓冲、2D 空间域临时缓冲、lag 生成缓冲
  - 返回值始终是独立 device 对象
- `gpu_kernel_perf`
  - `fft` 路径累计 `cuFFT + kernel`
  - `correlate2d` 路径累计真实 kernel 时间
- 头文件注释修正：
  - 去掉“占位实现返回零张量”描述

### 2. `demod`

- 重写 `src/cpu/demod.cpp` 和 `src/zhongkexin/demod.cu`，完整实现 `fm_demod`。
- 数值语义固定为 Python 当前实现：
  - `unwrap(angle(x), axis)` 后做 `diff(..., axis)`
  - 输出沿目标轴长度减 `1`
- 约束固定：
  - 输入必须是复数；对实输入抛 `std::invalid_argument`
  - `axis` 支持负索引
- ZQ500 GPU 侧实现固定为三段式 device-native：
  - 相位提取
  - 沿 line 的 unwrap
  - 沿 line 的 diff
- 显存复用：
  - `thread_local DemodWorkspace`
  - 复用输入归一化 scratch、相位缓冲、unwrap 缓冲、输出缓冲
- 头文件注释修正：
  - 返回形状从“与输入同形状”改为“沿指定轴长度减 1”

### 3. `estimation`

- 重写 `src/cpu/estimation.cpp` 和 `src/zhongkexin/estimation.cu`，完整实现当前头文件声明的 `KalmanFilter` 类。
- 公开接口不变，但运行时语义固定为：
  - `dtype` 仅接受 `"float32"`
  - `"float64"` 明确抛 `std::invalid_argument`
- 默认成员初始化对齐 Python 当前类语义：
  - `x = 0`
  - `P/Q/F/R = identity`
  - `H = 0`
  - `alpha_sq = 1`
  - `B/u` 按当前维度初始化
- `predict()`
  - 使用成员 `F/Q/alpha_sq`
  - 若 `dim_u > 0` 且 `B/u` 有效，则执行 `x = F x + B u`
  - 协方差更新固定为 `P = alpha_sq * F P F^T + Q`
- `predict(control)`
  - 先缓存到成员 `u`，再执行同一预测方程
  - `control` 形状必须与 `[points, dim_u, 1]` 一致
- `update(measurement)`
  - 使用成员 `H/R`
  - 固定采用标准 KF 更新：
    - `y = z - Hx`
    - `S = HPH^T + R`
    - `K = PH^T S^{-1}`
    - `x = x + Ky`
    - `P = (I - KH) P`
  - 同时缓存 `z`
- ZQ500 GPU 实现固定为 device-native，不回退 CPU：
  - `predict` 和 `update` 使用每个 point 一个 block 的 shared-memory 小矩阵内核
  - `S^{-1}` 在 kernel 内做小型高斯消元
- 显存复用：
  - `thread_local EstimationWorkspace`
  - 复用 point 级临时矩阵缓冲、单位阵缓冲和内核参数缓冲
- 头文件注释修正：
  - 去掉“占位更新逻辑”表述
  - `dtype` 改成“当前仅支持 float32，float64 显式不支持”

### 4. `peak_finding`

- 重写 `src/cpu/peak_finding.cpp` 和 `src/zhongkexin/peak_finding.cu`，完整实现：
  - `argrelextrema`
  - `argrelmin`
  - `argrelmax`
- 保持现有 C++ 接口：
  - comparator 仍是字符串 `"greater"` / `"less"`
  - 语义映射到 Python/SciPy 的严格比较 callable
- 数值行为固定为 Python `_boolrelextrema`：
  - `order >= 1`
  - `mode` 支持 `"clip"` / `"wrap"`
  - 严格比较，不识别平顶峰
  - 返回“每个维度一个索引数组”
- CPU 实现：
  - 先生成 bool mask，再展开为各轴索引数组
- ZQ500 GPU 实现：
  - device 端生成 bool mask
  - 设备端压缩得到 flat hit indices
  - 再把 flat index 转换成每轴坐标，生成 `DeviceAxisIndices`
- 显存复用：
  - `thread_local PeakFindingWorkspace`
  - 复用 mask、flat-index、axis-index 缓冲
- 头文件注释只保留当前接口约束：
  - callable comparator 仍不支持
  - 不再保留占位语义

### 5. 测试、数据、脚本与文档

- 新增 `tests/unit/correlate/`，单算子单入口：
  - `test_correlate.cpp`
  - `test_correlate2d.cpp`
  - `test_correlation_lags.cpp`
- 新增 `tests/unit/demod/`：
  - `test_fm_demod.cpp`
- 新增 `tests/unit/estimation/`：
  - `test_kalman_filter.cpp`
- 新增 `tests/unit/peak_finding/`：
  - `test_argrelextrema.cpp`
  - `test_argrelmin.cpp`
  - `test_argrelmax.cpp`
- 每个模块都新增对应 `*_test_support.hpp/.cu`，沿用当前 canonical runner 模式：
  - host 输入组织 case
  - accuracy 时显式 `get()`
  - `gpu_e2e_perf` 不包含 `get()`
  - `gpu_kernel_perf` 由各模块 `*_test_hooks::consume_last_kernel_ms()` 提供
- `tests/unit/CMakeLists.txt` 接入这 4 个模块。
- `scripts/test/run_all_tests.sh` 注册：
  - `correlate` 3 个算子
  - `demod` 1 个算子
  - `estimation` 1 个算子
  - `peak_finding` 3 个算子
- 新增数据脚本：
  - `scripts/data/generate_correlate_data.py`
  - `scripts/data/generate_demod_data.py`
  - `scripts/data/generate_estimation_data.py`
  - `scripts/data/generate_peak_finding_data.py`
- 数据组织继续对齐当前 schema：
  - `data/reference/unit/<module>/<op>/manifest.json`
  - `data/generated/unit/<module>/<op>/manifest.json`
  - `data/reports/unit/<module>/<op>/...`
- perf 输入继续运行时生成，`--emit-report` 时写回 `generated/input` 和 `output_samples`
- `output_samples` 命名固定：
  - `correlate/correlate2d`：`__cpu__values.csv` / `__gpu__values.csv`
  - `correlation_lags`：`__cpu__lags.csv` / `__gpu__lags.csv`
  - `fm_demod`：`__cpu__signal.csv` / `__gpu__signal.csv`
  - `kalman_filter`：`__cpu__x.csv`、`__cpu__P.csv`，GPU 同理
  - `peak_finding`：每个轴分别写 `__cpu__axis0_indices.csv` 等，GPU 同理
- 文档覆盖现有 `V2.13`：
  - 重写 `docs/design/V2_13_plan.md`
  - 重写 `docs/submission/READMEV2_13.md`
  - 重写 `docs/design/V2_13_api_audit.md`，改成“已解决的 API/语义差异记录”，不再保留“延后实现”结论
  - 更新 `README.md` 当前版本入口和模块状态

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
  - 单独确认全部 `correlate_*`、`demod_*`、`estimation_*`、`peak_finding_*` target 编译通过
- `correlate` accuracy：
  - `correlate`：1D real/complex，`full/same/valid`，`direct/fft/auto`
  - `correlate2d`：`fill/wrap/symm`，`full/same/valid`
  - `correlation_lags`：偶奇长度组合、`valid` 正负 lag bound
- `demod` accuracy：
  - 1D/2D 复输入
  - 不同 axis
  - 相位跨 `pi` 的 unwrap case
  - 实输入与越界 axis 的异常
- `estimation` accuracy：
  - 构造默认矩阵形状与初值
  - `predict()` 基础 case
  - `predict(control)` 的控制项路径
  - `update()` 基础 case
  - 多 point 并行 case
  - 非法 `dtype`、非法维度、非法 measurement/control shape
  - reference 由 Python 脚本按当前 KF 方程生成，不依赖仓内现有 Python test
- `peak_finding` accuracy：
  - 1D/2D/3D
  - `order=1/2`
  - `mode=clip/wrap`
  - `greater/less`
  - 平顶峰不检出
- perf：
  - 每个 operator 至少 1 个 perf case
  - `gpu_e2e_perf` 保持 host 输入 + H2D + GPU 计算，不包含 `get()`
  - `gpu_kernel_perf` 对 4 个模块都必须是实际非零时间
  - `--emit-report` 后确认 `generated/input` 与 `output_samples` 都存在，且 CPU/GPU 双样本齐全
- 全量回归：
  - `./scripts/test/run_all_tests.sh --emit-report`

## Assumptions

- 本轮版本固定为新的正式 `V2.13`，直接覆盖仓库里现有的 `V2.13` 延后文档。
- 不改任何公开函数签名；只有头文件注释和运行时语义修正。
- `KalmanFilter` 这轮不做公开 dtype 泛化；`dtype="float64"` 显式报不支持。
- `correlate(method="direct")` 按 Python cuSignal 语义只支持 1D；N 维由 `fft/auto` 覆盖。
- `peak_finding` 继续只支持字符串 comparator，不扩展到 Python callable。
- `demod` 和 `estimation` 没有现成 Python test 文件时，reference 由数据脚本按仓内 Python实现/SciPy/标准方程生成，并提交入库。
