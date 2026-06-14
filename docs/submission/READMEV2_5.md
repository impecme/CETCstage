# cuSignal C++ V2.5 README

## 版本信息

- 版本名称：`V2.5 waveforms/windows 显存复用与内部零拷贝优化`
- 完成时间：`2026-04-04`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.5` 建立在 `V2.4` 的 host/device 双输入、device 输出接口语义之上，本轮不改任何公开 API，而是继续把 CUDA 后端内部实现做实：

- `waveforms`：把之前只停留在定义层面的 workspace 改成真正参与执行的跨调用 scratch/buffer 复用。
- `windows`：把之前仍然存在的内部 D2H/H2D 回绕去掉，改成真正的 device 端生成、device 端后处理和 device 端返回。

## 本轮核心变更

### 1. `waveforms` 真实工作区复用

本轮将 `src/cuda/waveforms.cu` 中原先未真正用起来的 workspace 结构改成了实际参与执行的 `thread_local` 工作区。

当前复用策略如下：

- `chirp`：复用 host 输入上传缓冲；复数路径直接写 `CudaComplexSignal`，不再额外拆成实部/虚部再组包。
- `gausspulse`：复用 host 输入上传缓冲。
- `sawtooth` / `square`：复用 `t` 上传缓冲以及逐点 `width/duty` 上传缓冲。
- `unit_impulse`：保持直接写返回值，不引入没有实际收益的工作区。

这样做以后，`DeviceSignal::reserve/resize` 的容量复用能力终于能在跨调用场景下真正生效，而不是每次函数进入都新建局部 scratch 对象。

### 2. `windows` 纯 device 返回链

本轮保留并扩展了 `src/cuda/windows.cu` 中的 `thread_local WindowWorkspace`，使其真正承担完整的 device 工作区职责：

- 缓存普通窗输出 scratch
- 缓存系数上传缓冲
- 缓存 `chebwin` 频谱缓冲
- 缓存 `cuFFT` plan
- 缓存归一化用的 reduction scratch

内部行为变化如下：

- `launch_window_kernel(...)` 不再返回 host `RealSignal`，而是直接产出 `CudaRealSignal`。
- 普通窗函数不再走“device 计算 -> D2H -> `from_host(...)` 回 device”的旧路径。
- `general_cosine(...)` 不再对 device 系数调用 `.get()`，而是直接消费 device 指针。
- `blackman`、`blackmanharris`、`flattop`、`general_hamming`、`hamming`、`hann`、`nuttall` 等路径全部切到纯 device 返回链。

### 3. `chebwin` device 化

`chebwin` 现在保留“标量参数在 host 侧构造频域模板并一次上传”这一步，但去掉了后半段整段 FFT 结果 D2H 重建的旧路径。

当前流程为：

1. host 构造频域模板
2. 上传到 workspace 频谱缓冲
3. `cuFFT` 在 GPU 上执行
4. GPU postprocess kernel 完成频谱重排
5. GPU reduction 求最大值
6. GPU normalize kernel 完成归一化
7. GPU copy/truncate 到最终 `CudaRealSignal`

因此 `chebwin` 的后处理现在已经全部留在 device 侧。

### 4. 性能口径保持不变

本轮没有更改 `V2.4` 已经确定的测试与性能口径：

- `gpu_e2e_perf`：host 输入 + 自动 H2D + CUDA 计算，**不包含 `get()`**
- `gpu_kernel_perf`：记录 GPU 计算阶段耗时

其中 `windows` 的 `gpu_kernel_perf` 现在包含：

- 普通窗：完整 kernel + 输出整理阶段
- `chebwin`：`cuFFT + postprocess + reduction + normalize + truncate/copy`

这让报告里的 kernel 统计更加贴近算子真实 GPU 计算成本。

## 对外接口状态

本轮对外语义保持与 `V2.4` 一致：

- `cpu::*` 路径仍为 host 输入输出
- `cuda_backend::*` 仍支持 host/device 双输入
- `cuda_backend::*` 数组输出仍统一为 device ndarray 风格对象
- 仍然只有显式 `get()` 才执行 D2H

`include/` 中现有 API 注释也保持不变。

## 构建与运行

### 构建

```bash
./scripts/build/build_v1.sh
```

### 一键测试

```bash
./scripts/test/run_all_tests.sh
./scripts/test/run_all_tests.sh --emit-report
./scripts/test/run_all_tests.sh --module waveforms --emit-report
./scripts/test/run_all_tests.sh --module windows --emit-report
```

## 当前结论

`V2.5` 没有再扩公开接口范围，而是把 `V2.4` 的接口语义向内部实现真正兑现了一步：

- `waveforms` 的 scratch/buffer 复用不再是“定义了但没走到”
- `windows` 的普通窗与 `chebwin` 不再依赖内部 host 回绕

这样后续继续推进 `filter_design`、`filtering`、`spectral` 等模块时，可以直接复用当前更稳的 CUDA 内部执行模式。
