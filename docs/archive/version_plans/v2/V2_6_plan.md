# V2.6 `filter_design` / `filtering` 模块完整实现

## Summary

- 当前子版本定为 `V2.6`。本轮目标是参考现有 `waveforms` / `windows` 的实现与测试链路，把 `filter_design` 和 `filtering` 两个模块从占位实现补成可用实现。
- 公开接口保持 `V2.4` / `V2.5` 语义不变：
  - `cpu::*` 继续是 host 输入输出
  - `zx_gpu_backend::*` 继续支持 host/device 双输入，数组输出继续为 device 对象
  - `include/` 中现有 API 注释块全部保留，只做最小必要的参数/返回类型对齐，不重写说明
- 本轮同时补齐：
  - CPU/CUDA 真实实现
  - `tests/unit/filter_design` 与 `tests/unit/filtering`
  - `data/reference` / `data/generated` / `data/reports`
  - `run_all_tests.sh` / `clean_data.sh` 接入
  - `docs/archive/version_plans/v2/V2_6_plan.md` 与 `docs/submission/READMEV2_6.md`
  - `README.md` 当前版本入口更新到 `V2.6`

## Key Changes

### 1. 基础约束与公共实现

- 新增 `src/common/filter_design_detail.hpp` 和 `src/common/filtering_detail.hpp`，承接公共校验、轴遍历、padding、polyphase、频域 mask、输出长度计算、状态维度约定、FFT 包装与数值辅助。
- 不新增新的公开类型，不再改 `include/cusignal/*/*.hpp` 的签名结构；只把实现补齐。
- FFT 依赖沿用当前仓库约定：
  - CPU FFT-heavy 路径使用 `third_party/fftw/install` 的 FFTW
  - CUDA FFT-heavy 路径使用系统 CUDA Toolkit 的 `cuFFT`
- 测试与报告流程保持 `waveforms/windows` 现状，不新起测试框架；新模块各自维护自己的 `*_test_support.cu`。

### 2. `filter_design` 完整实现

- 保持以下公开 API 全量实现：`kaiser_beta`、`kaiser_atten`、`cmplx_sort`、`firwin`、`firwin2`。
- `kaiser_beta` / `kaiser_atten` 保留现有公式与异常语义，收敛到公共 detail。
- `cmplx_sort`：
  - CPU：稳定排序，实数按值，复数按模长。
  - CUDA：改为 device 端排序，不再 `get()` 回 host；采用 device key 生成 + `thrust::stable_sort_by_key`，结果和索引都留在 device。
- `firwin`：
  - 支持单 cutoff 和多 cutoff 两个重载。
  - 完整支持 `width` 覆盖为 Kaiser 窗、`pass_zero` 的 bool/字符串语义、`scale`、`nyq/fs` 解析、偶 tap 的 Nyquist 约束、显式窗数组与命名窗规格。
  - CPU：按理想冲激响应公式生成 tap，再乘 `cpu::windows::get_window(...)`。
  - CUDA：device 端生成 tap，调用 `zx_gpu_backend::windows::get_window(...)` 获取窗并做 device 端逐点乘；复用 `V2.5` 风格的 workspace/scratch。
  - `scale=true` 时按首个通带的单位增益规则做归一化。
- `firwin2`：
  - 完整支持 `nfreqs`、重复频点阶跃、Type I-IV、`antisymmetric`、当前已有的 `WindowSpec/ZxGpuWindowSpec` 规格。
  - CPU：频率插值后用 FFTW 生成时域系数，再乘窗。
  - CUDA：频率插值后用 `cuFFT` 做 device 端生成与后处理，再乘窗。
  - 默认 `nfreqs` 固定为 `1 + 2^ceil(log2(numtaps))`，并要求严格大于 `numtaps`。

### 3. `filtering` 完整实现

- 保持以下公开 API 全量实现：`wiener`、`firfilter`、`lfilter`、`firfilter_zi`、`lfilter_zi`、`firfilter2`、`filtfilt`、`sosfilt`、`hilbert`、`hilbert2`、`detrend`、`freq_shift`、`channelize_poly`、`decimate`、`resample`、`resample_poly`、`upfirdn`。
- `wiener`：
  - 默认无参版本按每轴窗口边长 `3` 处理。
  - CPU/CUDA 都按 separable box filter 计算局部均值和方差，再按 Wiener 公式恢复。
- `firfilter` / `lfilter` / `sosfilt`：
  - 沿指定 `axis` 做一维滤波，其余维度视作独立 line。
  - CPU：逐 line 直接型递推。
  - CUDA：并行到 line，单 line 内顺序递推；这是本轮固定实现口径。
  - `zi` 形状约定固定为：与输入同 rank，且滤波轴长度替换为状态长度；`final_state` 保持同形状返回。
- `lfilter_zi` / `firfilter_zi`：
  - `lfilter_zi` 按 SciPy 风格稳态初始条件求解。
  - `firfilter_zi` 直接复用 `lfilter_zi(b, {1})` 语义。
  - CUDA 允许用 common/CPU helper 先求小尺寸状态，再一次 H2D 返回，因为结果本身就是小状态向量。
- `firfilter2` / `filtfilt`：
  - `pad` 路径完整支持 `odd/even/constant/none`。
  - `gust` 路径按你已选定的口径执行：
    - CPU：完整实现 Gustafsson 初始条件求解。
    - CUDA：采用混合实现，common/CPU helper 负责 Gustafsson 状态求解，CUDA 负责主滤波与 device 返回。
    - `gust` 只进入 accuracy case，不进入 perf case。
- `hilbert` / `hilbert2` / `resample` / `channelize_poly`：
  - CPU 使用 FFTW，CUDA 使用 `cuFFT`。
  - `hilbert`/`hilbert2` 走频域掩码法。
  - `channelize_poly` 走 polyphase + batched FFT，结果形状保持当前约定 `[n_pts, n_chans]`。
  - `resample` 的 `domain="time"` 完整支持；`domain="freq"` 在当前 `RealArray` 签名下固定支持“可由实信号表示的实值/Hermitian 兼容频域输入”这一子集，accuracy case 也只覆盖这一子集。
  - 带 `t` 的 `resample` 返回新时间轴，长度为 `num`，按输入时间轴等间距外推。
- `detrend`：
  - 支持 `constant/c` 与 `linear/l`，支持 `bp` 分段断点。
- `freq_shift`：
  - 按复指数逐点相乘实现。
- `decimate` / `resample_poly` / `upfirdn`：
  - `upfirdn` 作为底层原语实现正确长度与多相路径。
  - `resample_poly` 建立在 `firwin + upfirdn` 之上。
  - `decimate` 建立在低通 FIR + 抽取之上；`zero_phase=true` 走前后向滤波，`false` 走单向滤波再抽取。

### 4. 测试、数据、脚本与文档

- 新增 `tests/unit/filter_design/`：
  - runner 按 API 拆分：`kaiser_beta`、`kaiser_atten`、`cmplx_sort`、`firwin`、`firwin2`
- 新增 `tests/unit/filtering/`：
  - runner 按 API 拆分：`wiener`、`firfilter`、`lfilter`、`firfilter_zi`、`lfilter_zi`、`firfilter2`、`filtfilt`、`sosfilt`、`hilbert`、`hilbert2`、`detrend`、`freq_shift`、`channelize_poly`、`decimate`、`resample`、`resample_poly`、`upfirdn`
- `tests/unit/CMakeLists.txt` 增加 `add_subdirectory(filter_design)` 和 `add_subdirectory(filtering)`。
- `scripts/test/run_all_tests.sh` 增加这两个模块及全部 operator 注册；默认流程继续保持 `full`、host 输入、`gpu_e2e_perf` 不含 `get()`。
- `scripts/clean_data.sh` 扩展到清理这两个模块的 `generated` / `reports`。
- 新增：
  - `data/reference/unit/filter_design/<op>/`
  - `data/generated/unit/filter_design/<op>/`
  - `data/reference/unit/filtering/<op>/`
  - `data/generated/unit/filtering/<op>/`
- reference 数据生成方式固定为：
  - 新增 `scripts/data/` 下的 Python 生成脚本，使用 SciPy 生成 accuracy 黄金数据与 manifest
  - 生成后的 CSV/manifest 提交入库
  - 这些脚本只服务数据刷新，不参与构建和运行时依赖
- 报告 schema 继续完全复用现有格式：
  - `latest_summary.md`
  - `latest_metrics.json`
  - `latest_cases.csv`
  - `cpu_perf` / `gpu_e2e_perf` / `gpu_kernel_perf`
  - `gpu_e2e_speedup` / `gpu_kernel_speedup`
- 文档新增：
  - `docs/archive/version_plans/v2/V2_6_plan.md`
  - `docs/submission/READMEV2_6.md`
  - `README.md` 当前版本说明改到 `V2.6`

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
  - 单独确认新增 `filter_design_*` 与 `filtering_*` target 都能编过
- 模块回归：
  - `./scripts/test/run_all_tests.sh --module filter_design --emit-report`
  - `./scripts/test/run_all_tests.sh --module filtering --emit-report`
  - `./scripts/test/run_all_tests.sh --emit-report`
- `filter_design` accuracy：
  - `kaiser_beta` / `kaiser_atten` 标量值
  - `cmplx_sort` 的实数、复数、重复模长稳定排序
  - `firwin` 的 lowpass/highpass/bandpass/bandstop、多 cutoff、`width` 覆盖、显式窗数组
  - `firwin2` 的 Type I-IV、重复频点、不合法 `freq/gain/nfreqs`
- `filtering` accuracy：
  - `wiener` 的 1D/2D/ND
  - `firfilter` / `lfilter` / `sosfilt` 的 axis、`zi`、最终状态
  - `firfilter2` / `filtfilt` 的 `pad` 与 `gust`
  - `hilbert` / `hilbert2` / `resample` / `channelize_poly` 的 FFT 路径
  - `detrend` 的 constant/linear/breakpoints
  - `decimate` / `resample_poly` / `upfirdn` 的长度与数值
- perf 验收：
  - 每个 operator 至少 1 个 perf case
  - `gust` 不进入 perf
  - `gpu_e2e_perf` 保持 host 输入 + H2D + ZQ500 GPU 计算，不包含 `get()`
  - 抽样核对终端摘要、JSON、CSV 三处一致

## Assumptions

- 本轮版本名称固定为 `V2.6`，版本文档文件名固定为 `docs/submission/READMEV2_6.md`。
- 不改任何现有公开函数签名，不新增新的公开类型，只补实现、测试、数据和文档。
- `gust` 按你选定的口径执行：CPU 完整实现，CUDA 采用混合实现，并且只做 accuracy、不做 perf。
- `resample(domain="freq")` 在当前 `RealArray` 签名下只支持可由实信号表示的实值/Hermitian 兼容频域输入；测试和 reference 只覆盖这一定义域。
- reference 黄金数据使用 Python + SciPy 生成并提交，运行时仍只依赖当前 C++/CUDA/FFTW/cuFFT 链路。
