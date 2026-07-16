# V6 智能体协作规则

## 文档定位

本文档定义 V6 性能优化阶段的智能体分工、文件所有权、Skill 路由和 ZQ500 容器协作方式。阶段范围、顺序和关闭门禁仍以 `README.md`、`plans/V6_1_plan.md` 至 `plans/V6_8_plan.md` 为准；执行事实和结果只写入 `optimization_change_log.md`。

V6 沿用 V5 的核心原则，但不再常驻 A-H 八个角色。当前模式为：

> 主智能体单一落地，阶段 Owner 并行分析，证据守门独立验收，审查角色按 patch 临时启用。

`plans/` 和优化台账是唯一任务与状态来源。当前不增加 GitHub issue、`.scratch` ticket 或另一套阶段状态，避免与 V6 工作包重复。

## 核心规则

1. 主智能体是唯一常驻写入者，负责最终 patch、文档、容器同步、验证命令和台账。
2. 辅助智能体默认只读；只有主智能体显式声明独占文件范围时，worker 才能修改文件。
3. 同一文件同一时刻只允许一个写入者；`demo/task2_features/task2_features_zx_gpu.cu`、`src/zhongkexin/*.cu` 等热点大文件不得并行修改。
4. 每轮只处理一个候选，形成完整的 `probe -> patch -> 单算子 -> task smoke -> A/B -> 回退/保留` 纵向闭环。
5. `gpu_04` 是全局串行测量资源，同一时刻只运行一个正式构建、probe 或 benchmark。
6. correctness、dtype、14 步和 V5.5 schema 是硬门禁；性能结论由证据守门复核后才能进入台账。
7. 不撤销用户已有改动。脏工作区审查必须限制到本轮文件和 before/after SHA，不用全仓 `HEAD` diff 混入无关变化。

## 动态角色

| 角色 | 职责 | 默认权限 | 激活条件 |
| --- | --- | --- | --- |
| 主智能体 / Integrator | 确定当前工作包、合并分析、实施唯一 patch、同步容器、取回日志、更新计划和台账 | 全项目写；不得撤销无关改动 | 常驻 |
| Task2 Owner | `cwt/spectrogram/correlate/filter/demod/fusion/kalman` 调用图、热点和候选分析 | 默认只读；获独占范围后可写 Task2 或对应算子文件 | V6.1-V6.3 |
| Task1 Owner | FFT、`pulse_compression/pulse_doppler/ca_cfar/ambgfun/mvdr` 调用图、热点和候选分析 | 默认只读；获独占范围后可写 Task1 或 radar 文件 | V6.4-V6.5 |
| Runtime Owner | stream/event、FFT plan、workspace、cache、allocation/copy 和 ZQ500 平台探针 | 只读或独占 runtime/probe 文件；不得同时改任务算法 | V6.1 探针、V6.3、V6.4、V6.6 |
| Evidence Guard | 解析容器归档、校验 SHA/退出码、A/B 统计、correctness、dtype、14 步和报告 schema | 永久只读 | 每轮验证和阶段关闭 |
| Review Pair | Standards 轴检查代码质量和文件边界；Spec 轴检查对应 `V6.x-NN`、门禁和性能声明 | 永久只读、按 patch 临时启动 | patch 完成后、昂贵全量回归前 |
| Researcher | 只查官方文档、开源实现和论文，把算法候选转成可证伪 probe | 永久只读，不直接把论文方案写进生产代码 | 新算法或平台能力不确定时 |

角色是所有权，不是新的长期上下文。一个辅助智能体完成本轮输出后立即释放；不得为了“保持分工”持续占用角色。

## 阶段激活矩阵

| 阶段 | 必需角色 | 可选角色 | 禁止并行事项 |
| --- | --- | --- | --- |
| V6.1-V6.2 | 主智能体、Task2 Owner、Evidence Guard | Runtime Owner、Researcher、Review Pair | 两个 Task2 候选同时改同一 `.cu`；并行 GPU A/B |
| V6.3 | 主智能体、Task2 Owner、Runtime Owner、Evidence Guard | Review Pair | execution context 与 Task2 算法在同一 patch 同时重写 |
| V6.4-V6.5 | 主智能体、Task1 Owner、Runtime Owner、Evidence Guard | Researcher、Review Pair | Task2 Owner 提前改 Task1；多个 FFT cache 实现并行落地 |
| V6.6 | 主智能体、Runtime Owner、对应任务 Owner、Evidence Guard | 架构审查、Review Pair | 未完成模块设计就横跨多个 backend 推广 |
| V6.7 | 主智能体、对应模块 Owner、Evidence Guard | Review Pair | 多个轻度优化混成一个不可归因批次 |
| V6.8 | 主智能体、Evidence Guard、Review Pair | 无 | 新增算法优化或报告 schema 变化 |

当前 V6.2 correctness 前置只激活主智能体、Task2 Owner 和 Evidence Guard；V6-0021 patch 使用 Review Pair 审查。Task1 Owner 不提前写代码。

## Skill 路由

Skill 只提供方法，不改变角色、所有权、阶段门禁或容器串行规则。

| 信号 | 方法 | 必须产出 |
| --- | --- | --- |
| correctness 失败、性能回退、波动或环境异常 | `diagnosing-bugs` | 可判红命令、最小复现、可证伪假设、根因证据 |
| 单算子优化、缺陷修复、内部接口新增 | `tdd` | red/green seam、最小 patch、局部与扩大回归 |
| patch 准备进入昂贵容器回归 | `code-review` | Standards 与 Spec 两轴结论；阻塞问题先修复 |
| V6.6 跨模块 runtime/FFT/workspace 设计 | `codebase-design`，必要时只读 `improve-codebase-architecture` | 候选、模块接口、依赖顺序和测试 seam；另立工作包后才实施 |
| 语义、术语或取舍仍不明确 | `grilling` / `domain-modeling` | 明确决策；必要时更新本文件或阶段计划 |

不为当前 V6.2 运行完整 issue-tracker setup。`to-tickets` 的窄而完整切片思想直接映射到现有 `V6.x-NN` 工作包；`wayfinder` 只在 V6.6 出现跨单次上下文的未决设计时采用，并把结论回写到 `plans/`。

## 每轮任务包

主智能体在修改前必须形成以下任务包；短任务可在对话中给出，复杂任务写入阶段计划或台账。

```text
台账 ID：V6-NNNN（全局递增） / 阶段工作包：V6.x-NN
当前阶段与门禁：
目标算子/任务步骤：
可写文件：
只读依赖：
基线与可判红命令：
候选及可证伪预测：
最低验证：
成功标准：
回退条件：
容器锁与固定归档名：
回传产物：
```

未列入“可写文件”的路径默认只读。新发现若超出范围，只登记为后续候选，不顺手修改。

## 辅助智能体输出

辅助智能体必须使用可合并的短格式，不直接扩写台账：

```text
角色：
方法：
范围：
证据：
结论：
建议：
风险：
需要验证：
涉及文件：
```

分析结论必须区分事实、推断和候选。没有容器 A/B 的方案不得写成性能收益。

## 文件所有权与并发

| 文件范围 | 默认 Owner | 并行限制 |
| --- | --- | --- |
| `demo/task2_features/`、Task2 直接相关算子 | Task2 Owner | Runtime Owner 只能分析 event/workspace，不同时写算法 |
| `demo/task1_radar/`、`src/zhongkexin/radartools.cu` | Task1 Owner | Task2 Owner 默认只读 |
| stream/event/FFT plan/workspace/cache 公共基础设施 | Runtime Owner | 跨两个以上调用方时拆成“基础能力 -> 调用方接入”顺序 patch |
| `tests/unit/<module>/` | 对应算法 Owner | Evidence Guard 和 Review Pair 只审查，不改测试来迁就错误结果 |
| `docs/performance/v6_0/` | 主智能体 | 辅助角色只提供素材；状态由主智能体统一更新 |
| `/home/usr_04/CETC_garbage/` | Evidence Guard 分析、主智能体归档 | 不进入 git；不同轮次使用唯一目录和固定 latest 别名 |

跨 Owner 改动必须顺序执行。示例：先由 Runtime Owner 完成有界 FFT plan cache 和独立测试，再由 Task1 Owner 接入 pulse 路径；不得在同一轮同时重写 cache、task graph 和报告 schema。

## ZQ500 容器锁

1. 主智能体发布容器任务前声明唯一台账 ID 和固定归档名；台账 ID 按全局流水号递增，归档名可沿用对应执行脚本的名称。
2. 源码同步后由命令核对目标文件 SHA；SHA 不一致时不运行 benchmark。
3. 用户在 `gpu_04:/CETC` 内串行执行；不得在同一 GPU 同时启动另一正式性能任务。
4. 命令必须捕获 stdout/stderr、真实退出码、源码 SHA、构建日志、JSON/CSV/Markdown 和必要 raw samples。
5. 主智能体只用精确 `docker cp` 取回固定别名，归档到 `/home/usr_04/CETC_garbage/`。
6. Evidence Guard 先判断日志是否覆盖目标源码和门禁，再允许主智能体登记收益或进入下一候选。
7. `data/reports/` 中间目录在归档后清理；仓库长期只保留阶段或最终汇总。

容器锁是测量锁，不只是写锁。即使两个候选修改不同文件，也不能并行测量后直接比较。

## Patch 与审查门禁

执行顺序固定为：

1. 确认当前阶段、工作包、Owner、可写文件和容器锁。
2. 有红灯时先走诊断闭环；没有可判红信号，不进入修复。
3. 使用 TDD 或等价的 red/green seam 实施最小 patch。
4. 本地执行 diff、语法、静态和可运行的 CPU/host 回归。
5. Review Pair 分别检查 Standards 和 Spec；阻塞项修复后再同步容器。
6. 容器按单测、单算子、task smoke、L1-L6、all81/阶段门禁逐级扩大。
7. Evidence Guard 复核归档，主智能体更新台账并决定保留、回退或暂缓。

脏工作区下，Review Pair 的输入必须包含：工作包 ID、允许文件、目标 plan 条目、目标文件 before/after SHA 和限定 diff。不得把用户无关删除/新增纳入本轮结论。

## 停止与回退

- correctness 未通过：停止性能结论，先诊断；不得同时启动下一热点实现。
- 单 stage 收益低于 5%且 Task total 低于 2%，连续三轮稳定复现：停止该候选。
- 复杂度明显增加而 Task total 收益低于 3%：回退或暂缓。
- L1/L2 退化超过 10%：增加 shape threshold；无法隔离则回退。
- ZQ500 平台能力不明确：Runtime Owner 先做最小 probe，不允许 Researcher 依据 CUDA 通用资料直接判定支持。
- Review Pair 发现 scope creep、schema 变化或无法验证的性能声明：阻断容器全量回归。

## 方法来源

- V5 协作基线：`../v5_0/agent_collaboration.md`
- Matt Pocock Skills：https://github.com/mattpocock/skills
- diagnosis：https://github.com/mattpocock/skills/tree/main/skills/engineering/diagnosing-bugs
- TDD：https://github.com/mattpocock/skills/tree/main/skills/engineering/tdd
- two-axis review：https://github.com/mattpocock/skills/tree/main/skills/engineering/code-review
- architecture review：https://github.com/mattpocock/skills/tree/main/skills/engineering/improve-codebase-architecture
- tracer-bullet tickets：https://github.com/mattpocock/skills/tree/main/skills/engineering/to-tickets
- wayfinding：https://github.com/mattpocock/skills/tree/main/skills/engineering/wayfinder
