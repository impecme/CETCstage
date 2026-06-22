# V5.2 工程规范与平台兼容交付文档

## 版本信息

- 当前状态：已完成。
- 对应计划：`docs/performance/v5_0/plans/V5_2_plan.md`。

## 阶段交付要求

- 根 README 的代码目录和模块职责说明。
- 81/81 算子的声明、CPU/GPU 实现、测试、类型、依赖和平台库契约。
- FP32、FP16、INT32、INT16、INT8 实数适用性矩阵。
- 仅 `complex64` 的复数口径及 CPU/GPU 表示说明。
- 两个 CUDA 11.7 API 表和科学计算库表的完整兼容矩阵、禁止清单和探针结果。
- CMake 兼容性探针目标及项目实际 API 验证结果。

## 当前进度

- V5 阶段已经按工程基础、任务、核心 53、全库 81 重排。
- 根 README 已补充目录职责及 V5 类型原则。
- 81 算子契约、公共类型基础和完整 API 探针均已完成，等待最终阶段回归。
- V5.2-07 已通过，阶段关闭并进入 V5.3。

## 工作包状态

| 工作包 | 状态 |
| --- | --- |
| V5.2-01 注册表与集合 | 已关闭 |
| V5.2-02 目录与接口审计 | 已关闭 |
| V5.2-03 类型基础设施 | 已关闭 |
| V5.2-04 逐算子类型契约 | 已关闭 |
| V5.2-05 复赛表与兼容矩阵 | 已关闭 |
| V5.2-06 CMake 平台探针 | 已关闭 |
| V5.2-07 阶段回归与交付 | 已关闭 |

## V5.2-01 验证结果

- 容器日期：2026-06-21。
- `registry_count=81`，`source_path_check=passed`，总状态 `passed`。
- `task27=27`、`core53=53`、`extended28=28`、`all81=81`。
- 81 行契约骨架已生成，后续工作包不再重新定义算子范围。

## V5.2-02 验证结果

- 静态审计 81 个算子，`passed_count=81`、`failed_count=0`。
- 每项检查公共 CPU/GPU 声明、CPU 定义、ZQ500 GPU 定义、独立测试 target 和 Doxygen。
- 函数注释要求 `@brief`、`@return`，有参数时要求 `@param`；`KalmanFilter` 按上游 class API 单独审计类和构造函数。
- 2026-06-21 容器 smoke：`operator_count=81`、`passed_count=81`、`failed_count=0`、`status=passed`。
- 本工作包已关闭，进入 V5.2-03。

## V5.2-03 宿主机结果

- 公共类型：FP32=`float`、FP16=`__half`、INT32/INT16/INT8 使用固定宽度整数，complex64=`std::complex<float>`。
- GPU complex 存储显式使用 `cuFloatComplex`/`cuComplex`，与现有 `float2` ABI 等价。
- FP16 累加为 FP32，INT8/INT16 累加为 INT32，INT32 累加为 INT64。
- 新增五类型 host/device 别名和通用 `SignalLike<T>`/`ArrayLike<T>`。
- 宿主机缓存 SDK 下完整构建 CPU/GPU 库和 `cusignal_type_contract_tests` 通过。
- 2026-06-21 容器 CTest 1/1 通过，直接运行输出 `[core/types] PASS real_types=5 complex_types=1`，本工作包已关闭。

## V5.2-04 宿主机结果

- 81/81 算子唯一分配到 13 个类型策略，无遗漏和重复。
- 正式实数类型恰好为 FP32、FP16、INT32、INT16、INT8；复数类型只有 complex64。
- 20 个算子涉及 complex64，8 个算子涉及整数输入或输出并具备明确整数策略。
- `current_types` 与目标类型分开，后续按 task27/core53/extended28 实施模板和 dtype 测试。
- 2026-06-21 容器复验结果与宿主机一致，本工作包已关闭。

## V5.2-05 宿主机结果

- 使用 Python 标准库逐行解析三个 XLSX，不引入容器依赖。
- 覆盖 900 个非空源行、816 个 API 行、830 个唯一 API。
- 每行保留来源文件、sheet、row、模块、API、支持状态、限制和探针模式。
- 315 个明确禁止 API 独立输出；科学库中只有三个不受平台支持的 double FFT API 进入禁止清单，数据类型或参数限制记为 `partial`。
- 所有探针仍标为 pending，等待 V5.2-06 实际验证。
- 2026-06-21 容器复验计数全部一致，本工作包已关闭。

## V5.2-06 宿主机结果

- 新增固定目标 `zx_compat_compile_probes`、`zx_compat_runtime_probes` 和 `zx_forbidden_api_scan`。
- Runtime/Driver 高影响且受支持的声明采用 compile-only，不执行设备复位、IPC 或跨设备操作。
- Runtime 基础调用及 FFT、BLAS、DNN、SOLVER、SPARSE、RAND 六库完成编译和链接。
- 315 项禁止 API 全符号扫描无命中，项目 API 报告 `violation_count=0`、`unresolved_count=0`。
- 源表漏列 DNN handle 生命周期 API，且将 `cusparseDestroy` 拼错；三个例外已机器化记录并强制由运行探针验证。
- 2026-06-21 容器两个 CTest 2/2 通过，安全运行探针七项平台类别全部 passed，禁止 API 和未解析 API 均为 0，本工作包已关闭。

## V5.2-07 门禁

- `run_v5_2_gate.sh` 统一执行集合、接口、类型、兼容矩阵、禁止 API 和 CTest 门禁。
- 全量构建并运行 81 个算子的 accuracy case，要求 81/81 通过且每项有新报告。
- `summarize_v5_2_gate.py` 只在前序命令全部成功后生成最终 JSON/Markdown；缺失报告和失败算子均阻止阶段关闭。
- 最终报告目录：`data/reports/zhongkexin/v5_2_gate_latest/`。
- 2026-06-21 容器结果：81/81 accuracy、3/3 CTest、全部 8 项 checks 通过，无缺失报告和失败算子。

## 完成判定

- 不把计划支持类型写成已实现能力。
- 不强制纯浮点算子实现整数路径。
- 不实现 FP64、`complex128`、FP16 复数或整数复数。
- 三个复赛表全部有可追溯结论，项目实际使用 API 全部通过。
