# V5.0 全算子库性能优化总计划

## 总目标

- 覆盖 Task1、Task2、赛题核心 53 算子和全库 81 算子。
- 在正确性不退化的前提下优化 GPU kernel、数据搬运、显存复用和任务端到端性能。
- 同时完成目录规范、算子封装、数据类型、CUDA 11.7 API 和科学计算库兼容性验收。
- 每项性能结论必须具备同口径耗时、误差、显存/cache 和复现命令。

## 固定阶段

| 阶段 | 目标 | 交付文件 | 状态 |
| --- | --- | --- | --- |
| V5.1 | 可观测性与性能基线 | `docs/submission/READMEV5_1.md` | 已完成 |
| V5.2 | 目录规范、类型体系、算子契约、平台兼容 | `docs/submission/READMEV5_2.md` | 进行中 |
| V5.3 | Task1/Task2 和 27 个依赖算子优化 | `docs/submission/READMEV5_3.md` | 待开始 |
| V5.4 | 核心 53 算子规范化与性能优化 | `docs/submission/READMEV5_4.md` | 待开始 |
| V5.5 | 全库 81 算子优化、全量验证与交付 | `docs/submission/READMEV5_5.md` | 待开始 |

## 类型口径

- 正式实数类型固定为 FP32、FP16、INT32、INT16、INT8，但按原始 cuSignal/SciPy 语义逐算子确定适用类型。
- 纯浮点算子不强制提供整数实现；不适用类型必须进入契约矩阵并验证明确拒绝行为。
- FP16 GPU 路径允许 FP32 中间累加；整数路径必须明确累加宽度、输出转换和溢出规则。
- 默认返回或处理复数的算子只支持 `complex64`：CPU 使用 `std::complex<float>`，GPU 使用 `cuFloatComplex`/`cuComplex`，存储语义对应 `float2`。
- ZQ500 不支持 double，因此不实现 `complex128`，也不增加 FP16 复数或整数复数类型。

## 算子工程口径

- 每个公开算子独立封装为函数，CPU/GPU 名称、参数和结果语义对应。
- 每类算子保持一个模块声明头文件、一个 CPU 实现文件和一个中科芯 GPU 实现文件。
- 公共声明使用 Doxygen 注释说明功能、输入、输出、类型、异常和平台限制。
- 每个算子有独立 correctness、边界、非法参数、适用类型和性能测试。
- 公共信号与数组容器按模块渐进模板化，保留现有 FP32 别名兼容调用方。

## 平台兼容口径

- 完整覆盖 `CUDA 11.7 driver api.xlsx`、`CUDA 11.7 runtime API.xlsx` 和 `科学计算库实现列表.xlsx`。
- `supported` 项执行编译探针和安全运行探针；`part supported` 项验证边界；`unsupported` 项进入禁止清单。
- 设备复位、跨设备、外部资源等有破坏性或环境依赖的接口只做编译验证，并记录原因。
- CMake 提供独立兼容性探针目标，项目实际使用 API 必须全部通过。

## 总关闭标准

- README 目录职责、81/81 算子契约、类型适用性和完整平台兼容矩阵可审计。
- Task1/Task2 每一步均调用公共算子库，均有 CPU/GPU 计时和逐步精度。
- 27/27 任务依赖、53/53 核心算子和 81/81 全库算子均有最终状态。
- 81 算子 L1-L6 共 486 行 benchmark、12 模块 correctness 和两个任务 L1-L6 全部通过。
- 优化台账和 `READMEV5_0.md` 至 `READMEV5_5.md` 记录措施、证据、限制和复现命令。

## 执行规则

- 阶段未关闭不进入下一阶段；独立热点允许提前完成，但必须归入新阶段。
- correctness 未通过时不接受性能收益结论。
- 不通过无用显存驻留制造显存利用率提升。
- 用户执行容器命令，Codex 负责宿主机修改、同步准备、结果解析和文档更新。

## 工作包执行规范

每个阶段拆成编号工作包，严格按编号推进。每个工作包必须同时给出：允许修改范围、交付文件、宿主机静态检查、容器命令、用户回传产物和通过/回退条件。

- 单轮只实施一个工作包；跨模块任务先拆成公共基础和模块接入两轮。
- 代码完成后先执行 L0 静态检查，再同步到容器；容器验证失败时不叠加下一工作包。
- 报告目录固定使用 `data/reports/zhongkexin/v5_<stage>_<topic>/`，benchmark 使用 `data/reports/unit/benchmarks/v5_<stage>_<topic>/`。
- 每轮回传最少包含终端 PASS/FAIL、`latest_metrics.json` 或阶段 summary、目标 CSV 行和显存 summary。
- 每个工作包关闭后立即更新 `optimization_change_log.md` 和对应 `READMEV5_x.md`，不等阶段末统一补写。

## 固定集合接口

V5.2 建立 `scripts/test/operator_sets.json`，作为数量和阶段范围的唯一机器可读来源：

- `task27`：两任务 27 个唯一依赖算子。
- `core53`：任务 27 加核心非任务 26。
- `extended28`：核心 53 之外的 28 个算子。
- `all81`：完整公开算子库。

测试和 benchmark 脚本统一接受 `OPERATOR_SET=<name>`；阶段关闭时由脚本断言集合数量，禁止人工复制长算子列表作为最终验收依据。
