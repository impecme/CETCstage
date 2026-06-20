# V2.5 `waveforms` / `windows` 显存复用与内部零拷贝优化

## Summary

- 当前版本定为 `V2.5`。本轮只做内部实现优化，不改公开 API、不改 `include/` 注释、不改测试流程和报告 schema。
- 优化目标有两块：
  - `waveforms`：把当前“定义了 workspace 但基本没复用”的实现改成真实的跨调用 scratch/buffer 复用。
  - `windows`：保留现有 `thread_local` 思路，但去掉内部仍然存在的 D2H/H2D 往返，改成真正的 device 端生成与返回。
- 同步新增 `docs/submission/READMEV2_5.md`，并把顶层 `README.md` 的当前版本说明与入口文档指向更新到 `V2.5`。

## Key Changes

### 1. 公开接口与版本约束

- `include/cusignal/*/*.hpp` 不做签名修改，`cpu::*` 和 `zx_gpu_backend::*` 接口保持 `V2.4` 语义不变。
- `include/` 中现有注释块保持原样，不重写、不压缩。
- 本轮所有优化都限定在 `src/zhongkexin/waveforms.cu`、`src/zhongkexin/windows.cu` 及必要的共享内部辅助层。

### 2. `waveforms` 内部复用落地

- 把 `src/zhongkexin/waveforms.cu` 中现有未真正使用的 `Workspace` 结构改成实际参与执行的 `thread_local` 工作区。
- 不再让 host 输入归一化依赖每次调用新建的局部 `ZxGpuRealSignal t_storage`；改为使用 workspace 中持久存在的 scratch `ZxGpuRealSignal`，让 `reserve/resize` 的容量复用真正发生。
- 各算子的复用策略固定为：
  - `chirp`：复用 host 输入上传缓冲；复数路径直接写 `ZxGpuComplexSignal`，不再保留“实部/虚部分离后再额外组包”的多余临时路径。
  - `gausspulse`：复用 host 输入上传缓冲；返回值仍为独立结果对象。
  - `sawtooth` / `square`：复用 `t` 上传缓冲和逐点 `width/duty` 上传缓冲。
  - `unit_impulse`：保持直接写返回值，不强行引入无意义 workspace。
- 移除已经没有价值的遗留 helper 和空壳式 workspace 定义，避免“看起来有复用，实际上没走到”。

### 3. `windows` 内部零拷贝优化

- `src/zhongkexin/windows.cu` 中 `WindowWorkspace` 保留并继续使用 `thread_local`，但职责升级为完整 device 工作区：
  - 缓存普通窗输出 scratch
  - 缓存系数上传缓冲
  - 缓存 `chebwin` 频谱缓冲
  - 缓存 `cuFFT` plan
- `launch_window_kernel(...)` 改成直接产出 `ZxGpuRealSignal`，不再走“device 计算 -> D2H 到 `RealSignal` -> `from_host(...)` 回 device”的路径。
- `general_cosine(...)` 改成纯 device 路径：
  - host 系数时上传到 workspace
  - device 系数时直接使用 device 指针
  - 不再对 `ZxGpuRealSignal` 系数执行 `.get()`
- 依赖 `general_cosine` 或 `launch_window_kernel` 的窗函数统一切到纯 device 返回链，包括：
  - `blackman`
  - `blackmanharris`
  - `flattop`
  - `general_hamming`
  - `hamming`
  - `hann`
  - `nuttall`
  - 以及其他当前仍经由 host 回绕的普通窗
- `chebwin(...)` 固定改法：
  - 频域模板允许继续在 host 构造后一次上传
  - `cuFFT` 执行后新增 device postprocess kernel，在 GPU 上完成重排、实部提取、归一化和 truncation
  - 不再把整段 FFT 结果 D2H 后在 host 重建窗函数
- `get_window(...)` 保持 `V2.4` 语义：
  - host 显式数组 spec：一次 H2D 后返回 device 信号
  - device 显式数组 spec：直接返回
  - 命名窗规格全部走优化后的纯 device 实现

### 4. 性能统计与文档

- `gpu_e2e_perf` 口径保持不变：host 输入 + 自动 H2D + ZQ500 GPU 计算，**不包含 `get()`**。
- `gpu_kernel_perf` 对 `windows` 的统计更新为“算子全部 GPU 计算阶段总时长”：
  - 普通窗：完整 kernel 时长
  - `chebwin`：`cuFFT + postprocess kernel` 总 GPU 计算时长
- 新增 `docs/submission/READMEV2_5.md`，内容固定覆盖：
  - V2.5 版本定位
  - `V2.4` host/device 双输入语义继续保留
  - `waveforms` 的真实 workspace/buffer 复用
  - `windows` 的内部零拷贝与 `chebwin` device 化
  - 性能口径说明
  - 构建与一键测试命令
- 更新 `README.md`：
  - 当前版本说明改为 `V2.5`
  - 详情入口改到 `docs/submission/READMEV2_5.md`
- 不删除 `READMEV2_4.md`，保留历史版本文档。

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
- 回归测试：
  - `./scripts/test/run_all_tests.sh --module waveforms --emit-report`
  - `./scripts/test/run_all_tests.sh --module windows --emit-report`
- 重点验收项：
  - `waveforms` 与 `windows` accuracy 全通过
  - `windows/get_window` 与 `windows/kaiser` 继续通过严格 reference 阈值
  - `gpu_e2e_perf` 不包含 `.get()`，`unit_impulse` 路径保持这一口径
  - `windows` 普通窗函数内部不再出现 device-to-host materialization
  - `chebwin` 内部不再把 FFT 结果整段 D2H 重建
- 静态验收：
  - `src/zhongkexin/waveforms.cu` 中 workspace 被真实调用，而不是只定义不用
  - `src/zhongkexin/windows.cu` 中除显式 host array spec 上传外，不再有内部 `.get()` 回 host 的实现路径

## Assumptions

- 本轮不新增 caller-provided output buffer API，也不改 `DeviceSignal` / `DeviceArray` 的拥有语义。
- 返回给用户的结果对象保持独立有效；复用的是内部 scratch、上传缓冲和 `cuFFT` plan，不是把 workspace 输出别名暴露给调用方。
- `chebwin` 允许继续在 host 侧根据标量参数生成频域模板并上传；要消除的是后半段不必要的 D2H 重建。
- 测试流程、CLI、报告字段和 `include/` 注释全部保持现状，只做实现优化与版本文档同步。
