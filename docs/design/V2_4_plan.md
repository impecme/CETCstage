# V2.4 CUDA Backend Host/Device 双输入迁移方案

## Summary

- 当前版本定为 `V2.4`，本轮只做一件核心事：把全量 `zx_gpu_backend` 公共接口迁移为“数组输入支持 host/device 双态，数组输出统一为 device ndarray 风格对象，显式 `get()` 才 D2H”。
- `cpu` 路径不改；`zx_gpu_backend` 直接替换现有接口，不保留当前 host-returning 旧签名作为主路径。
- 同步编写 `V2_4.md`，并保持 `include/` 里每个 API 的原有注释风格与内容口径，不因迁移删改说明文字，只做必要的参数/返回类型更新。

## Key Changes

- `core` 层新增统一设备容器与双态输入类型：
  - `DeviceSignal<T>`、`DeviceArray<T>`
  - `RealSignalLike`、`ComplexSignalLike`
  - `RealArrayLike`、`ComplexArrayLike`、`IndexArrayLike`
  - `get()` 作为唯一显式 D2H 入口，返回现有 host 容器类型
- `zx_gpu_backend` 全量公开接口统一改造：
  - 所有数组输入改为 `*Like`
  - 所有数组输出改为 `DeviceSignal` / `DeviceArray`
  - 标量返回值不改
  - 所有复合返回结构体里的数组字段同步改为 device 类型
- 输入语义固定：
  - 传 host：函数入口自动上传到 device
  - 传 device：直接复用，不额外 H2D
  - 所有数组型参数都遵循此规则，不只主输入
  - 包括 `width/duty`、`cutoff`、`freq/gain`、`zi`、`sos`、显式窗数组等辅助数组参数
- CUDA 专用规格类型同步补齐：
  - 对含数组参数的 spec，新建 CUDA 专用版本，例如 `ZxGpuWindowSpec`
  - 显式数组规格支持 host/device 双态
- 内部实现约束：
  - 各 `.cu` 文件先把 `*Like` 归一为 device view，再进入 kernel/cuFFT 主路径
  - 现有零散 `DeviceBuffer` 收敛到公共设施，不再每个模块各自维护一套接口边界
- 迁移顺序固定：
  1. `core` 新类型与 host/device 归一化辅助
  2. 全量 `include/cusignal/*/*.hpp` 的 `zx_gpu_backend` 签名切换
  3. 全量 `.cu` 实现迁移
  4. tests 仅做接口迁移
  5. 文档补齐 `V2.4`

## Public Interfaces

- `include/` 中所有 `zx_gpu_backend` API 注释必须保留原有说明结构和语义：
  - 不删现有注释块
  - 不压缩、不重写风格
  - 仅在参数类型和返回类型变化处做最小必要更新
- `cpu` 命名空间接口保持不变
- `zx_gpu_backend` 新接口原则：
  - 输入：host/device 双态
  - 输出：device ndarray 风格对象
  - `get()` 外部显式取回 host 数据
- 聚合头继续可用，但会导出新的 device 类型与 `*Like` 类型

## Test Plan

- 测试流程保持原样，不新增“类型与基础能力测试”或额外行为测试分类。
- 现有 unit runner 只做接口迁移：
  - 继续用 host 输入组织 case
  - 继续走现有 accuracy / perf / report 流程
  - accuracy 对比时，在需要与 CPU/reference 比较的节点显式 `get()`
- GPU 性能统计口径固定：
  - `gpu_kernel_perf`：保持 kernel-only
  - `gpu_e2e_perf`：输入为 host，包含函数入口自动 H2D 和 ZQ500 GPU 计算，但**不包含 `get()`**
- 不新增新的性能字段，不改现有报告主 schema，只调整实现口径与 runner 调用方式

## Documentation

- 新增 `docs/submission/READMEV2_4.md`
- 内容聚焦：
  - V2.4 版本目标
  - ZQ500 GPU API 从 host-returning 迁移到 device-output 的规则
  - host/device 双输入语义
  - `get()` 的使用方式
  - 测试与性能口径说明
- 顶层 `README.md` 的版本说明与快速开始引用同步指向 `V2.4`

## Assumptions

- 本轮只做接口迁移与文档同步，不单独新增新的验证体系。
- 所有数组型 CUDA 输入都支持 host/device 双态，这是统一规则，不分主输入和辅助参数。
- unit tests 中为 correctness 做的显式 `get()` 不影响性能口径；性能统计明确不包含 `get()`。
- `V2.4` 作为当前版本名称使用，文档文件名按 `READMEV2_4.md` 落地。
