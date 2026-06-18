# cuSignal C++ V2.4 README

## 版本信息

- 版本名称：`V2.4 CUDA backend host/device 双输入迁移`
- 完成时间：`2026-04-04`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.4` 聚焦于 ZQ500 GPU 后端公开接口迁移，不再让 `zx_gpu_backend::*` 在函数内部固定执行 D2H 并返回 host 容器，而是统一改成：

- 数组输入同时支持 host 与 device 两种形态
- 数组输出统一为 device ndarray 风格对象
- 只有用户显式调用 `get()` 时才执行 D2H

本轮不改 `cpu::*` 接口，CPU 路径继续保持 host 容器输入输出，作为数值基线与 reference 路径。

## 本轮核心变更

### 1. `core` 层新增设备容器与双态输入类型

当前新增以下基础类型：

- `core::DeviceSignal<T>`
- `core::DeviceArray<T>`
- `core::ZxGpuRealSignal`
- `core::ZxGpuComplexSignal`
- `core::ZxGpuRealArray`
- `core::ZxGpuComplexArray`
- `core::ZxGpuIndexArray`
- `core::RealSignalLike`
- `core::ComplexSignalLike`
- `core::RealArrayLike`
- `core::ComplexArrayLike`
- `core::IndexArrayLike`

语义约定如下：

- 当 `zx_gpu_backend` 接口收到 host 输入时，会在入口处自动上传到 device。
- 当 `zx_gpu_backend` 接口收到 device 输入时，会直接复用，不额外进行 H2D。
- `DeviceSignal` / `DeviceArray` 统一提供 `get()`，由外部显式触发 D2H。

### 2. `zx_gpu_backend` 公开接口迁移

本轮已将 `include/` 中 `zx_gpu_backend` 分支的数组型公开接口统一切换为：

- 输入参数使用 `*Like`
- 输出参数使用 `DeviceSignal` / `DeviceArray`
- 标量返回值保持原样
- 复合返回结构体中的数组字段同步改为 device 类型

其中：

- `cpu::*` 命名空间接口保持不变
- `zx_gpu_backend::*` 注释块保留原有说明结构与内容口径，只在参数类型和返回类型变化处做必要更新

### 3. CUDA 专用规格类型

为承接含数组参数的 ZQ500 GPU API，本轮补齐了 CUDA 专用规格类型：

- `core::ZxGpuWindowSpec`

它在原有 `WindowSpec` 基础上，允许显式窗数组既来自 host，也来自 device。

### 4. 测试接口迁移

本轮没有新增新的测试分类，`tests/unit/` 继续沿用原有流程，只做接口迁移：

- 测试输入继续由 host 侧 case 组织
- `zx_gpu_backend` 调用阶段自动完成 H2D
- 与 CPU/reference 做 correctness 对比时，在测试支撑层显式调用 `get()`
- 报告 schema 不新增字段，不改既有字段名

## 性能口径说明

`V2.4` 对 GPU 性能统计口径做了明确约束：

- `gpu_kernel_perf`：保持 kernel-only 统计
- `gpu_e2e_perf`：输入为 host，包含函数入口自动 H2D 和 ZQ500 GPU 计算，但**不包含 `get()`**

因此：

- correctness 路径里为了做 CPU/reference 对比而发生的 `get()`，不会混入 `gpu_e2e_perf`
- 用户在真实使用中可以把一个 `zx_gpu_backend` 输出直接作为下一个 `zx_gpu_backend` 输入，不需要中间 D2H

## 使用方式

### host 输入

```cpp
const cusignal::core::RealSignal t = /* host data */;
const auto y = cusignal::zx_gpu_backend::waveforms::sawtooth(t, 0.5);
const cusignal::core::RealSignal host_y = y.get();
```

### device 输入

```cpp
cusignal::core::ZxGpuRealSignal t_device = cusignal::core::ZxGpuRealSignal::from_host(t_host);
const auto y_device = cusignal::zx_gpu_backend::waveforms::sawtooth(t_device, 0.5);
const auto z_device = cusignal::zx_gpu_backend::waveforms::square(y_device, 0.5);
```

说明：

- 第一种写法适合单次调用和测试对比。
- 第二种写法表达了 V2.4 的核心目标，即 ZQ500 GPU 链路以 device 对象作为边界。
- 只有在显式 `get()` 时，结果才会下载回 host。

## 当前状态

本轮已完成：

- `core` 层 device 容器与 `*Like` 输入规格
- `include/` 下 `zx_gpu_backend` 公开签名迁移
- 现有 CUDA 源文件签名与测试支撑层接口迁移
- `waveforms`、`windows` 现有单测链路适配
- 构建脚本 `./scripts/build/build_v1.sh` 重新打通

本轮不单独新增新的验证体系，也不改变现有 CPU 路径 API。

## 构建与运行

### 构建

```bash
./scripts/build/build_v1.sh
```

### 一键测试

```bash
./scripts/test/run_all_tests.sh
./scripts/test/run_all_tests.sh --emit-report
./scripts/test/run_all_tests.sh --module waveforms
./scripts/test/run_all_tests.sh --module windows
```

## 结论

`V2.4` 将当前项目的 ZQ500 GPU 后端接口从“host-returning 风格”切换为“host/device 双输入、device 输出、显式 `get()` 才 D2H”的统一语义，为后续 `filter_design`、`filtering`、`spectral` 等模块继续按 cuSignal 风格扩展打下了接口基础。
