# V2.12 `wavelets` 模块完整接入

## Summary

- 当前 `wavelets` 现状很明确：头文件已定义接口，但 [src/cpu/wavelets.cpp](/home/ziheng/CETC/src/cpu/wavelets.cpp) 和 [src/zhongkexin/wavelets.cu](/home/ziheng/CETC/src/zhongkexin/wavelets.cu) 仍是占位实现；`tests/unit`、`data/reference`、`data/generated`、`run_all_tests.sh` 里都还没有 `wavelets` 链路。
- 本轮版本定为 `V2.12`，按和 `bsplines / radartools / spectral` 相同的模式，把 `wavelets` 完整接入：
  - 真实 CPU/ZQ500 GPU 实现
  - 单算子单入口 unit tests
  - canonical data/report schema
  - 一键测试与版本文档接入
- 行为基准固定为仓内 Python 与测试，冲突时以测试/SciPy 语义为准，尤其 `qmf` 按 SciPy/test 语义实现，不照搬当前 Python 文件里的 `_qmf_kernel`。

## Key Changes

### 1. 实现层

- 重写 [src/cpu/wavelets.cpp](/home/ziheng/CETC/src/cpu/wavelets.cpp) 和 [src/zhongkexin/wavelets.cu](/home/ziheng/CETC/src/zhongkexin/wavelets.cu)，完整实现：
  - `qmf`
  - `morlet`
  - `ricker`
  - `morlet2`
  - `cwt`
- `qmf`
  - CPU/CUDA 都实现为 `out[i] = hk[n - 1 - i] * ((i % 2 == 0) ? 1 : -1)`。
  - 空输入直接返回空输出。
- `morlet`
  - `x` 在 `[-s * 2π, s * 2π]` 上等间距采样。
  - 支持 `complete=true/false`。
  - `points=0` 返回空；`points=1` 直接按 `x=0` 生成。
- `ricker`
  - 按标准公式实现，输出实数。
- `morlet2`
  - 按现有签名实现，默认 `w=5.0`。
- `cwt`
  - 只支持当前头文件允许的 `"ricker"` 与 `"morlet2"`。
  - 只覆盖当前 C++ 签名可表达的实输入子集，不扩展到 callable wavelet 或复输入。
  - 每个 `width` 的实现固定为：
    - `length = min(10 * int(width), data.size())`
    - 生成 wavelet
    - `conj(...)[::-1]`
    - 与输入做一维 `same` 卷积
  - 不依赖当前 `correlate` 模块，`wavelets` 内部自带一维 `same` 卷积实现。
  - 返回类型保持 `ComplexArray` / `ZxGpuComplexArray`；`ricker` 路径虚部为 0。
- 新增 `src/common/wavelets_detail.hpp`，承接公共公式、参数校验、采样坐标和 `cwt` 的共享辅助，避免 CPU/CUDA 分叉。

### 2. ZQ500 GPU 实现与复用

- `zx_gpu_backend::*` 保持现有 host/device 双输入、device 输出模式，不改签名。
- 在 [src/zhongkexin/wavelets.cu](/home/ziheng/CETC/src/zhongkexin/wavelets.cu) 引入 `thread_local WaveletsWorkspace`，至少复用：
  - host 输入归一化 scratch
  - `widths` 上传缓冲
  - `cwt` 中间输出/临时卷积缓冲
  - 必要的参数缓冲
- 返回值始终是独立 device 对象；workspace 只复用内部 scratch，不暴露别名。
- 增加 `wavelets_test_hooks::consume_last_kernel_ms()`，并让 `g_last_kernel_ms` 统计真实 GPU 计算阶段；`gpu_kernel_perf` 不允许系统性 `0.000`。
- ZQ500 GPU 路径固定为：
  - `qmf / morlet / ricker / morlet2`：逐元素 kernel
  - `cwt`：按尺度逐行并行的 direct-convolution kernel
  - 禁止完整输入/输出回退 CPU

### 3. 测试、数据与集成

- 新增 `tests/unit/wavelets/`，采用当前主线的单算子单入口模式：
  - `CMakeLists.txt`
  - `wavelets_test_support.hpp/.cu`
  - `test_qmf.cpp`
  - `test_morlet.cpp`
  - `test_ricker.cpp`
  - `test_morlet2.cpp`
  - `test_cwt.cpp`
- `tests/unit/CMakeLists.txt` 接入 `add_subdirectory(wavelets)`。
- `scripts/test/run_all_tests.sh` 新增 5 个注册项，支持 `--module wavelets`。
- 新增 `scripts/data/generate_wavelets_data.py`，生成：
  - `data/reference/unit/wavelets/<op>/manifest.json`
  - accuracy 输入/期望 CSV
  - `data/generated/unit/wavelets/<op>/manifest.json`
- perf 输入继续采用运行时生成；`--emit-report` 时落盘 `generated/input` 和 `output_samples`。
- 样本命名沿用当前 canonical 规范：
  - `qmf / ricker`：`__cpu__signal.csv`、`__gpu__signal.csv`
  - `morlet / morlet2`：同名 `signal.csv`，按复数 CSV 写
  - `cwt`：`__cpu__values.csv`、`__gpu__values.csv`
- `reports` 保持现有 schema，不新增字段。

### 4. 文档与版本

- 新增：
  - `docs/archive/version_plans/v2/V2_12_plan.md`
  - `docs/submission/READMEV2_12.md`
- 更新 [README.md](/home/ziheng/CETC/README.md)：
  - 当前版本改为 `V2.12`
  - 入口指向 `READMEV2_12.md`
  - 当前状态说明加入 `wavelets` 已接入 unit 链路
- [include/cusignal/wavelets/wavelets.hpp](/home/ziheng/CETC/include/cusignal/wavelets/wavelets.hpp) 只做最小注释修正：
  - 去掉 `cwt` 的“占位入口”描述
  - 保留原注释块结构和风格
  - 不改任何签名

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
  - 单独确认全部 `wavelets_test_*` target 编译通过
- 模块回归：
  - `./scripts/test/run_all_tests.sh --module wavelets`
  - `./scripts/test/run_all_tests.sh --module wavelets --emit-report`
- accuracy 重点：
  - `qmf`：已知滤波器系数、奇偶长度、空输入
  - `morlet`：`complete=true/false`、`points=0/1`、不同 `w/s`
  - `ricker`：不同 `a`、峰值位置、边界点数
  - `morlet2`：不同 `s`、默认 `w=5.0`
  - `cwt`：`"ricker"` 与 `"morlet2"` 两条路径、不同 `widths` 长度、输出 shape、`same` 卷积数值
  - 异常路径：`points < 0`、`s <= 0`、`a <= 0`、`widths` 为空、非法 `wavelet` 名、`width <= 0`
- perf 重点：
  - 每个 operator 至少 1 个 perf case
  - `gpu_e2e_perf` 保持 host 输入 + H2D + GPU 计算，不包含 `get()`
  - `gpu_kernel_perf` 对全部 ZQ500 GPU 算子为真实非零时间
  - `--emit-report` 后确认 `generated/input` 与 `output_samples` 都落盘，且 CPU/GPU 两套样本齐全
- 全量回归：
  - `./scripts/test/run_all_tests.sh --emit-report`
  - 预期总数从当前 `68` 增加到 `73`

## Assumptions

- 版本固定为 `V2.12`。
- `wavelets` 只实现当前头文件中已有的 5 个公开 API，不扩展 callable wavelet。
- 数值行为优先级固定为：
  1. `cusignal/python/cusignal/test/test_wavelets.py`
  2. 其隐含的 SciPy 语义
  3. `cusignal/python/cusignal/wavelets/wavelets.py`
  4. 已提交 reference 数据
- `qmf` 明确按 SciPy/test 语义实现，不照搬当前 Python `_qmf_kernel`。
- `cwt("morlet2", ...)` 固定使用默认 `w=5.0`，因为当前 C++ 签名没有额外参数。
- `cwt` 的 `widths` 统一要求 `> 0`；否则抛 `std::invalid_argument`，避免 `int(width)` 导致零长度 wavelet 的未定义路径。
