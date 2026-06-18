# V2.6.x `filtering` 全 GPU 化与测试数据组织统一

## Summary

- 现在 `data/generated` 组织不一致的原因已经确认：
  - `waveforms` 的 `emit_report` 会同时写 `cpu` 和 `gpu` 两套样本。
  - `windows`、`filter_design`、`filtering` 的 `emit_report` 目前只写了 `gpu` 样本，所以目录和文件命名都更简化。
  - `filtering` 的 ZQ500 GPU 后端当前基本仍是 `to_host_* -> cpu::filtering::* -> from_host(...)` 的 hybrid 路径，所以 `gpu_kernel_perf` 经常是 `0.000`，这也和 `waveforms/windows` 的真实 GPU 实现不一致。
- 本轮版本继续算 `V2.6.x`，不新开 `V2.7`。
- 本轮目标分两部分一起完成：
  - 把 `windows`、`filter_design`、`filtering` 的 `generated/output_samples` 全部对齐到 `waveforms` 风格。
  - 把 `filtering` 的全部算子改成真实 GPU 实现；只有 `gust` 允许继续用 CPU helper 求初值，其余主计算路径全部 device-native。

## Key Changes

### 1. `generated` / `reports` 数据组织统一到 `waveforms`

- 以 `waveforms` 为唯一标准，统一 `windows`、`filter_design`、`filtering` 的 perf 落盘逻辑。
- `generated/input` 保持每个 perf case 的输入或规格文件。
- `generated/output_samples` 统一同时输出 `cpu` 和 `gpu` 两套样本，不再只写 `gpu`。
- 文件命名固定为“`case_id + backend + logical_field`”：
  - `windows`：
    - `__cpu__window.csv`
    - `__gpu__window.csv`
  - `filter_design`：
    - 标量输出：`__cpu__value.csv`、`__gpu__value.csv`
    - 向量输出：`__cpu__values.csv`、`__gpu__values.csv`
    - 排序索引：`__cpu__indices.csv`、`__gpu__indices.csv`
  - `filtering`：
    - 主输出：`__cpu__output.csv`、`__gpu__output.csv`
    - 可选最终状态：`__cpu__state.csv`、`__gpu__state.csv`
    - 可选时间轴：`__cpu__time.csv`、`__gpu__time.csv`
- `report.artifacts` 同步登记两套后端文件，不再只记录 `gpu` 产物。
- `latest_cases.csv`、`latest_metrics.json`、`latest_summary.md` 的 schema 不改，只补齐 artifacts 和样本落盘一致性。
- 实现方式采用公共 helper 抽取：
  - 把 `waveforms` 的 backend-tagged sample writer 抽成可复用工具。
  - `windows`、`filter_design`、`filtering` 的 test support 改为共用这套命名和写盘逻辑，避免以后再次分叉。

### 2. `filtering` ZQ500 GPU 后端改为真实 device-native

- 公开 API、`include/` 注释、`cpu::*` 路径全部保持现状，不改签名。
- `src/zhongkexin/filtering.cu` 不再允许“完整 CPU 计算后再上传”：
  - 禁止对完整输入执行 `get()` 后交给 `cpu::filtering::*`
  - 禁止对完整输出走 `from_host(...)`
  - 只允许 `gust` 的初值求解在 host 侧完成，随后立即上传小状态向量，主滤波仍在 GPU
- 保留 `V2.4/V2.5` 语义：
  - 输入继续支持 host/device 双态
  - host 输入自动 H2D
  - device 输入直接复用
  - 输出统一返回 device 对象
  - `gpu_e2e_perf` 继续是“host 输入 + H2D + GPU 计算”，不包含 `get()`

### 3. `filtering` GPU 实现分组方案

- 公共基础：
  - 在 `src/zhongkexin/filtering.cu` 内按算子族引入 `thread_local` workspace。
  - 缓存中间 `ZxGpuRealArray/ZxGpuComplexArray`、系数缓冲、反转缓冲、平方缓冲、polyphase 系数缓冲、FFT 频谱缓冲和 `cuFFT` plan。
  - 返回值始终是独立 device 对象；workspace 只复用 scratch，不把内部存储别名暴露给调用方。
  - `g_last_kernel_ms` 改为真实统计整个 GPU 计算阶段；多 kernel / `cuFFT` 的算子要累计总 GPU 时长。

- 点运算与局部统计类：
  - `freq_shift`：逐点复指数 kernel。
  - `detrend`：
    - `constant`：每条 line 做均值归约再逐点减均值。
    - `linear`：每段用 GPU 归约得到拟合系数，再逐点减拟合直线。
  - `wiener`：
    - 对输入和平方输入分别做按轴的 separable box filter。
    - 先得到局部均值和局部方差，再用单独 kernel 应用 Wiener 公式。
    - `noise < 0` 时用全局 `mean(local_variance)`，保持与当前 reference 语义一致。

- 递推滤波类：
  - `firfilter`、`lfilter`、`sosfilt`：
    - 按 `axis` 把其余维度视作独立 line。
    - GPU 上采用“每条 line 一个线程”的顺序递推实现，保证语义清晰、状态一致。
    - `zi` 和 `final_state` 全部保留在 device。
  - `firfilter_zi`、`lfilter_zi`：
    - 不再调用 CPU helper。
    - 在 GPU 上实现小规模线性方程求解，采用单 block 的 shared-memory Gaussian elimination。
  - `firfilter2`、`filtfilt`：
    - `pad` 路径全部 device-native，包含 pad、正向滤波、反向滤波、裁剪。
    - `gust` 只允许初值求解走 CPU helper；正反向滤波和最终输出必须在 GPU 完成。
  - `decimate`：
    - 复用 GPU `firwin` 设计 taps。
    - `zero_phase=true` 保持当前参考口径：`upfirdn + delay compensation` 的 GPU 实现。
    - `zero_phase=false` 走单向滤波再抽取。

- FFT / 频域类：
  - `hilbert`、`hilbert2`：
    - 用 `cuFFT` 做 FFT/IFFT。
    - 频域 mask 和重建全部在 device 上完成。
  - `resample`：
    - `domain="time"` 与 `domain="freq"` 都走 `cuFFT` 路径。
    - 窗函数调用 `zx_gpu_backend::windows::get_window(...)`，频域加窗在 device 上完成。
    - 带 `t` 的版本在 GPU 生成重采样时间轴。
  - `channelize_poly`：
    - 先做 polyphase FIR，再用 batched `cuFFT` 生成每个 channel 的频域输出。
    - `cuFFT` plan 按 `(n_pts, n_chans)` 缓存复用。

- 多相重采样类：
  - `upfirdn` 作为 GPU 底层原语重写，不再构造完整 upsampled host 中间量。
  - 采用 polyphase 系数布局，每个输出样本直接在 device 上累加对应 phase/tap。
  - `resample_poly` 建立在 GPU `upfirdn` 之上，完整保留当前 CPU/reference 的：
    - `gcd(up, down)` 约简
    - filter 乘 `up`
    - `n_pre_pad`
    - `n_pre_remove`
    - 最终裁剪
  - `decimate` 复用这套 GPU 路径，不另造一套下采样实现。

### 4. `filter_design` 与 `windows` 本轮边界

- `filter_design` 本轮不改公开数值语义，也不重做 GPU 算法；只做 `generated/output_samples` 的 CPU/GPU 双样本对齐。
- `windows` 本轮不改公开数值语义；只把 perf 落盘对齐到 `waveforms` 风格。
- `waveforms` 作为基线模块，不改 schema，只作为参考实现和统一模板。

### 5. 文档与版本说明

- 设计文档新增 `docs/design/V2_6_1_plan.md`，描述本轮 `V2.6.x` 的增量工作。
- `docs/submission/READMEV2_6.md` 新增 `V2.6.x` 章节，明确：
  - 统一后的 `generated/output_samples` 结构
  - `filtering` 已改为全 GPU 主计算
  - `gust` 是唯一允许 CPU helper 的例外
  - `gpu_e2e_perf` 与 `gpu_kernel_perf` 的口径
- 顶层 `README.md` 保持指向 `READMEV2_6.md`，只更新摘要说明，不改版本号。

## Public Interfaces

- 不改任何现有公开函数签名。
- 不改 `include/` 中任何 API 注释块的结构和语义。
- 变更仅体现在：
  - `generated/output_samples` 的文件组织与命名统一
  - `filtering` 的 ZQ500 GPU 实现从 hybrid 改为 device-native
  - `gpu_kernel_perf` 从大量 `0.000` 变为真实 GPU 计算时间

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
  - 单独确认全部 `filtering_*`、`filter_design_*`、`windows_*` target 编译通过

- 数据组织验证：
  - `./scripts/test/run_all_tests.sh --module windows --emit-report`
  - `./scripts/test/run_all_tests.sh --module filter_design --emit-report`
  - `./scripts/test/run_all_tests.sh --module filtering --emit-report`
  - 抽查 `data/generated/unit/<module>/<op>/output_samples/`：
    - 都同时存在 `cpu` / `gpu` 样本
    - `filtering` 的 `state/time`、`filter_design` 的 `indices` 都按 backend 双份落盘

- `filtering` correctness：
  - 全部算子 accuracy case 通过
  - 已经暴露过问题的 `wiener`、`hilbert2`、`resample`、`resample_poly`、`upfirdn` 重点回归
  - `gust` accuracy 单独回归，确认只有初值求解走 CPU helper，主输出仍与 reference 一致

- `filtering` GPU 落地验收：
  - `gpu_kernel_perf` 不再系统性为 `0.000`
  - `gpu_e2e_perf` 继续不包含 `get()`
  - device 输入串联调用时不发生额外 H2D
  - 用静态搜索确认 `src/zhongkexin/filtering.cu` 不再存在把完整输入/输出回落到 `cpu::filtering::*` 的路径

- 全量回归：
  - `./scripts/test/run_all_tests.sh --emit-report`
  - `latest_summary.md`、`latest_metrics.json`、`latest_cases.csv` 继续可生成，schema 不回退

## Assumptions

- 版本继续记为 `V2.6.x`，设计增量文档采用 `docs/design/V2_6_1_plan.md`。
- `gust` 是唯一允许继续使用 CPU helper 的 `filtering` 路径；其余算子全部要求主计算在 GPU 上完成。
- `filter_design` 本轮只做样本落盘统一，不扩大它的 GPU 改造范围。
- `generated/output_samples` 的统一标准以 `waveforms` 为准，不再维持模块各自不同的精简格式。
- 不新增新的测试类型，不改 CLI，不改报告主 schema，只补齐实现和样本组织。
