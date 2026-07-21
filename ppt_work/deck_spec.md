# 比赛答辩 PPT 内容规划（20 页 / 8 分 33 秒技术主线）

> 依据：`ppt_work/evidence.md` 当前仓库审计。
> 汇报上限：10 分钟。
> 主讲目标：20 页、513 秒（8:33）。
> 机动余量：87 秒，不分配给任何页面。
> 当前状态：P03～P19 已生成技术页初稿；P09、P11、P14、P16 已由 ZQ500 正式 L1–L6 报告重绘。性能图只使用结构化报告导出，不由生图模型补造。

## 1. 结构选择

### 1.1 推荐采用哪一种结构

推荐采用您去年答辩结构的“升级版混合方案”：

```text
封面 / 团队（用户自制，快速带过）
  → 赛题重述：交付对象、验收目标、技术难题
  → 两层技术路线
      公共算子库优化 / 应用级算法构建
  → 三项公共算子技术（原理与效果各一页）
      Wiener Tile/Halo / IIR Affine Scan / FFT-PSD R2C+Fusion
  → 两个应用任务（流程与性能各一页）
      Task1 雷达检测 / Task2 多域特征融合与跟踪
  → 软件架构、算子覆盖与公共执行机制
  → 正式 L1-L6 正确性/性能数据槽位与 81 算子性能分布
  → 改进方向、核心亮点与 AI 使用说明
  → 致谢（用户自制）
```

不继续采用旧规划中“Wiener、IIR、FFT 各拆 2～3 页，再单列大量性能页”的 22 页结构。原因不是技术内容变少，而是新版仓库已经形成更清晰的两层技术体系：

- 底层是可跨算子复用的执行与资源机制。
- 上层是 Task1 的公开算子组合和 Task2 的 batched/score-only 应用特化。

赛题重述之后，三大代表技术各保留一张 40 秒核心页，每页完整讲清“问题 → 方法 → 效果 → 边界”；两条应用都严格采用“流程与核心技术 → 性能与正确性”两页结构。这样既与两层技术路线完全对应，又能把主讲压到 8:33，给 10 分钟答辩留出 87 秒真实余量。

### 1.2 为什么不完全照搬去年的术语

去年“GPU 参数优化框架、缓冲区池、融合内核”的层次仍可参考，但当前项目必须按真实代码改名：

| 去年可参考概念 | 本项目准确表述 | 原因 |
|---|---|---|
| 多算子间自动数据转换优化 | **C++17 `std::variant` Host/Device 双态 + Device 返回值驻留 + 链尾显式 `.get()`** | 当前代码确实解决了任务链重复往返，但不是 Unified Memory、零拷贝或隐式自动迁移 |
| GPU 参数优化框架 | **shape-aware 多路径策略分派 + 正确性/性能门禁** | 当前没有参数搜索器、在线 autotuner 或策略数据库 |
| 统一缓冲区池 | **RAII 共享所有权 + core capacity cache + 模块 prepared cache + 精确 Host 内容缓存** | 四者分别解决生命周期、分配、重复准备和重复上传，不是一个池管理全部 raw buffer |
| 融合内核 | **算子内 fusion + Task2 score-only 特化** | 公共算子融合与任务私有融合必须分层说明 |
| 应用算法优化 | **Task1 public pipeline + Task2 mixed specialized pipeline** | 两个任务的工程边界不同 |

这一改名本身也是答辩可信度的一部分：只讲代码中真实存在的能力。

## 2. 时间与内容预算

| 部分 | 页码 | 页数 | 时间 | 主讲占比 | 作用 |
|---|---:|---:|---:|---:|---|
| 开场、团队、赛题与路线 | 1～4 | 4 | 58 s | 11.3% | 封面/团队快速带过，明确赛题与技术地图 |
| 公共算子库三项技术 | 5～7 | 3 | 120 s | 23.4% | 三个代表技术逐页讲原理、效果与边界 |
| 两个应用级算法 | 8～11 | 4 | 140 s | 27.3% | 每个应用一页流程、一页真实性能证据 |
| 架构、覆盖与公共机制 | 12～13 | 2 | 36 s | 7.0% | 说明技术如何落入真实代码和 81 算子体系 |
| 正确性、性能与瓶颈 | 14～17 | 4 | 112 s | 21.8% | 当前运行、全库分布、Scaling 和瓶颈解释 |
| 亮点、结论与致谢 | 18～20 | 3 | 47 s | 9.2% | 提炼贡献、收束并致谢 |
| **主讲合计** | **1～20** | **20** | **513 s** | **100%** | **8:33** |

正式预算为 `513 s 主讲 + 87 s 机动 = 600 s`。机动时间用于翻页、动画、停顿、口误和评委短暂打断；正常演练不主动占用。

公共技术、应用算法、架构和公共机制（P5～P13）占 296 秒；性能证据与瓶颈（P14～P17）占 112 秒。两者合计约 79.5%，符合技术型赛题应把绝大多数时间用于“为什么难、怎么做、为什么有效、还差什么”。

### 2.1 演练检查点

| 翻到页面 | 累计目标时间 | 超时时的动作 |
|---|---:|---|
| P04 结束 | 0:58 | 赛题页只讲交付、验收和三类瓶颈；路线页不逐项解释标签 |
| P07 结束 | 2:58 | 三个公共技术页各只讲一个瓶颈、一个方法、一个效果 |
| P11 结束 | 5:18 | 应用性能页不逐级读完 L1～L6，也不逐行读历史优化表 |
| P17 结束 | 7:46 | 全库性能与瓶颈页只保留最能解释差异的两个例子 |
| P20 结束 | 8:33 | 剩余 1:27 用于临场机动 |

## 3. 证据状态与发布规则

### 3.1 页面证据角标

每张含数据的页面右下角使用统一角标：

- `CURRENT CODE`：当前源码/契约结构事实。
- `RUN 2026-07-20 SNAPSHOT`：`current-20260720-task-optimized-l6` 已发布运行快照；当前源树与该快照存在 4 项 source drift，正式答辩前须复验冻结。
- `HISTORICAL BEFORE/AFTER`：V5/V6/V7 历史优化前后；这是不同版本或开关下的对照，不是两条任务运行链路。
- `DERIVED`：从结构化 JSON 的 repeat/case 重算。
- `FINAL L1-L6 · 2026-07-21`：ZQ500-Q QUAD-0 上的正式测评；每点 7 次，首轮 warm-up 排除，CPU/GPU total 取其余 6 次中位数，speedup 直接计算为 CPU/GPU。

禁止把不同角标的数据放进同一个公式继续计算。例如历史 before 与当前 GPU 时间不能相除得到新的“总优化倍数”。

### 3.2 当前证据黄线

当前报告 `FILES.sha256` 338/338 通过；当前复核时 `SOURCE_FILES.sha256` 为 691/695，差异包含两个 task demo、BUILD_AND_RUN 与探索脚本。14/14 个正式步骤同时有误差和 GPU event 字段。正式出图仍保留三条黄线：

1. provenance 为 `git_commit=null`、dirty 状态未记录；最终版本应绑定答辩 commit。
2. task total 已含 input construction，但 CPU 是场景/Host 参数构造，GPU 是已生成输入上传/Device 参数准备；只能称 application-total，不是纯 backend 加速。
3. Task2 measurement contract 仍写 copy helper，而默认代码/报告为 Device storage alias、0 ms；benchmark README 对 8 aggregate 的描述也落后于 JSON。
4. 已发布报告是 2026-07-20 的 source snapshot；两份 task demo 之后已漂移。数据页只写“已发布快照”，最终答辩必须在冻结 commit 复验。

### 3.3 仍待团队补充的事实

- P02 的成员、实际分工和 AI 工具使用事实由团队确认；当前精简仓库没有完整 AI 使用台账。
- P03 的赛题重述应引用官方赛题说明或 README，不在规划阶段编造赛题条款。
- P01/P20 的团队名称、致谢和 Q&A 文案由团队确认。

## 4. 页面统一设计原则

### 4.1 示例 PPT 提炼后的统一母版

已审阅 `CICC0900702_北方华创_总决赛_答辩PPT.pptx`（17 页）和 `凌波驭算_10_25改.pptx`（15 页）。本项目沿用其中真正有效、且适合技术答辩的结构语言：

- 固定顶部导航：`团队介绍 / 赛题解析 / 技术路线 / 核心技术 / 技术指标 / 创新点`，本页栏目用亮蓝圆角块高亮；不复制示例中的学校、企业或赛事 Logo。
- 白底、深蓝标题、浅蓝信息底、青绿色 GPU、灰色 CPU、橙色优化动作；页脚只保留证据角标与必要口径，不使用深色科技背景。
- 每页只有一个中心论点和一个主视觉；流程图使用正交箭头，技术图使用“原始问题 → 结构重写 → 证据/边界”的三段式，而不是无标签图标墙。
- 数字页不使用生图模型伪造柱状图或曲线，统一由结构化 JSON 生成；图表依然使用同一页眉、页脚、配色与结论条。

P03 V03 是已确认的视觉基线：右侧只保留承担流程语义的输入、接口、算子分组、双后端与任务对照；CPU reference 与 ZQ500 GPU 必须同时覆盖 Task1、Task2，不使用无解释的图标或装饰图片。

每个技术页只证明一个核心判断，固定包含：

1. 标题：使用“问题或动作”，不写空泛的“技术介绍”。
2. 顶部结论句：一句完整判断，3 秒内可读完。
3. 一个主视觉：架构、执行流、内存图或数据图，只表达一个主要关系。
4. 一组证据：规模、时间、误差、版本/协议和路径脚注。
5. 一个边界：红色细注说明 fallback、适用条件或不能外推的范围。

视觉约束：

- 16:9，白色或极浅灰底；正文不做满屏深色科技风。
- CPU 固定灰色，GPU 固定青绿色，优化动作固定橙色，限制/回退固定红色，证据固定蓝色。
- 性能图必须有 `1x` 参考线；跨度大时用 log 轴。
- 不使用 3D 柱状图、仪表盘、虚构 GPU 芯片或由 AI 生成的性能/运行结果。
- AI 可生成无文字的波形、频谱、内存块、数据张量等技术底图；架构、thread/block、Halo、scan、真实依赖、公式和数据必须在可编辑 SVG/PPT 层精确覆盖。
- 不在页面中堆完整文件路径；路径、run id、warmup/repeat 放脚注或演讲者备注。
- 代码片段每页最多 8～15 行，字号不低于 16 pt。

## 5. 逐页内容规划

### P01 封面：面向 ZQ500 的信号处理算子库与任务加速（10 秒）

**核心结论**

> 81 个算子、CPU/ZQ500 双后端、两条端到端任务，核心工作是算法级并行重构。

**页面内容**

- 主标题：`面向 ZQ500 的信号处理算子库与端到端加速`。
- 副标题：比赛名称、团队名称、日期。
- 底部三个事实：`12 modules · 81 operators · 2 task pipelines`。

**主视觉**

纯排版 + 一条极简线性符号：`signal → operator kernels → task → ZQ500`。封面不放性能数字和目录。

**讲解**

“我们完成了面向 ZQ500 的 81 个信号处理算子和两条应用任务，重点汇报三个并行难题与两条任务的组合优化。”

**证据**：`README.md`、`operator_sets.json`。
**待补**：团队名称、成员。
**禁止**：不确定来源的 ZQ500 产品照片。

---

### P02 团队成员与分工（用户自制，10 秒）

本页由团队自行完成，不纳入技术提示词和生图资产范围。

建议只保留：成员姓名、职责、交叉复核关系；AI 使用说明可用 1 行真实事实放在页脚，以满足赛题要求。

**禁止**：根据 Git 作者推断成员，或填写无法验证的 AI 贡献比例。

---

### P03 赛题重述：信号处理算子库的 ZQ500 迁移与任务验证（20 秒）

**核心结论**

> 赛题的交付对象不是单个 GPU kernel，而是一套保持信号处理语义的 CPU/ZQ500 双后端算子库，以及两条可验证的端到端任务。

**页面布局**

参考“赛题重述 + 右侧对象示意 + 底部三列表”的结构：

- 左侧 `x=5%～70%`：标题下用两句话重述交付对象与难点。
- 左下 `x=5%～70%, y=52%～88%`：`场景 / 交付要求 / 本项目应对` 三列表。
- 右侧 `x=74%～96%, y=18%～88%`：垂直技术示意，使用透明 PNG；不让 AI 生成赛题文字。

**左侧赛题重述文案**

`面向中科芯 ZQ500 平台，构建兼顾 CPU reference 与 GPU 执行的 C++17 信号处理算子库，覆盖 12 个模块、81 个公开算子。`

`在保持参数、shape、axis 与数值语义可验证的前提下，完成雷达处理和特征提取两条端到端任务，并给出正确性、性能与报告证据。`

**三列表内容**

| 场景 | 交付要求 | 本项目应对 |
|---|---|---|
| 公共算子库 | 12 模块、81 公开算子；CPU/GPU 一致语义 | 双后端、共享类型/shape/axis 语义、契约测试 |
| ZQ500 并行执行 | GPU 运行并证明性能收益 | 按访存、递归依赖、频谱冗余重构算法 |
| 两条端到端任务 | 雷达处理与特征提取完整运行 | Task1 公开算子驻留组合；Task2 batched score-only 特化 |
| 可交付验证 | 正确性、性能、报告可追溯 | unit/contracts/demo/reports 与正确性/性能回退门 |

**右侧示意内容**

```text
信号输入
  ↓
12 模块 / 81 算子
  ↓
CPU reference  ║  ZQ500 GPU
        ╲           ╱
      CPU/GPU 双后端对照
        ├───────┬───────┤
        ↓       ↓
Task1 雷达检测      Task2 特征融合与跟踪
        ╲           ╱
correctness / performance / provenance
```

图中 CPU reference 与 ZQ500 GPU 是每条任务的双后端对照，不是“CPU 只运行 Task1、GPU 只运行 Task2”的任务分工。

**讲解**

只说明“库、平台、任务、证据”四个交付层，不在此页讲具体 Tile、Scan、R2C 或任何加速倍数；这些内容由 P04 之后的技术页展开。

**证据**：`README.md`、`tests/contracts/operator_sets.json`、`tests/contracts/task_step_contracts.json`、`data/reports/summary.json`。

---

### P04 技术路线：“3 + 2 + 5” 分层技术体系（18 秒）

**核心结论**

> 三类通用公共机制提供跨算子执行基础；代表算子负责展开算法级并行重构，两条应用沿五类路径组合构建。

**页面布局**

参考“左侧公共库、右侧应用构建、底部总结带”的结构，不使用横向六阶段流程：

```text
┌──────────────────┐     ┌─────────────────────────────────────────────┐
│ 底层公共库优化   │     │ 应用级算法构建                              │
│    3 通用机制    │     │                 2 构建         5 路径        │
│                  │     │  Task1 雷达检测  ───────→ Task1 五项优化    │
│ Tile/Halo        │     │  Task2 特征跟踪  ───────→ Task2 五项优化    │
│ Cache / Fusion   │     │                                             │
└──────────────────┘     └─────────────────────────────────────────────┘
└────── 3 类通用机制 + 2 条应用 + 5 类可组合优化路径 ──────┘
```

**左侧：3 类通用公共机制**

1. `访存与资源复用`：单算子内以 Tile/Halo 消除邻域重复 global read；以 `DeviceStorage` capacity、prepared plan/table 和精确 Host 内容缓存避免重复分配、准备或上传。
2. `并行结构重构`：按算法依赖将串行递推、归约等改写为线程块映射、分层 scan/reduction 等可并行结构。
3. `shape-aware 分派与算子内 Fusion`：按 shape/阶数/窗口选择 direct、tiled、FFT、scan 路径；在单算子内部融合可合并的前后处理，减少中间读写和 launch。

左下放三组代表证据：Wiener Tile/Halo、IIR Affine Scan、Periodogram R2C/Fusion。P05～P07 的叙事必须先写“通用机制”，再用代表算子证明它如何落到真实单算子内核；不能把代表算子误说成整个公共库只优化了这三个算子。

**右侧：2 条应用与 5 类组合路径**

| 应用构建 | 正式测评状态 | 对应组合优化 |
|---|---:|---|
| Task1 雷达检测 | 正式 L6 `33.09x` | template cache、scale fusion、transpose+shift、row prefix、two-stage peak |
| Task2 特征融合与跟踪 | 正式 L6 `1048.78x` | batch+residency、AOT correlate、band score、CWT max-score、fusion+peak+Kalman |

五类路径是跨应用归纳的技术方法，不暗示两条任务机械地各用同一组五项：`Device-resident/batch`、`prepared/cache reuse`、`fusion/direct write`、`parallel scan/reduction`、`score-only/compact output`。Task1 重点使用 cache、fusion、矩阵重排、row-prefix 与两级归约；Task2 重点使用 batch/residency、AOT preparation、四路 score 裁剪与融合跟踪。

**讲解**

先报“3、2、5”：前三项是单算子层可复用的优化类别，P05～P07 用代表算子解释每类机制如何落到内核；后两项才是多算子应用构建。Task1 证明全公开算子组合，Task2 证明算子库 + 私有 helper 的 mixed 组合。五类应用路径按任务特征自由组合。

**证据角标**：Wiener 使用 `RUN 2026-07-20 SNAPSHOT · unit benchmark`；Task1/Task2 分别标注 `FINAL L1-L6 · 2026-07-21 · L6 median`。
**边界**：P04 的两个 L6 数字可与 P09/P11 对照，但不得和历史优化前后对比、旧 `scales/` 或独立 `final/` 数字继续相除、相乘或合并归因。

---

### 技术页的赛题一致性约束（不单独占页）

1. **Task1**：六个正式处理步骤展示为公开算子库的 GPU 实现组合；不得画成任务私有 kernel 绕开算子库。
2. **Task2**：展示为“公开算子库 + 私有 batched/score-only helper”的 mixed 流程。private helper 只承担任务级批处理、紧凑输出或融合；与库算子协同调用仍属于算子库任务构建，不能包装成独立第三后端。
3. **GPU 覆盖不等同于每例都更快**：对 E2E 小于 CPU 的公共 case，P15 如实显示为固定成本/规模边界；不能因为 CPU 更快就把 GPU 路径替换为 CPU 并称为 GPU 实现。只有代码中显式声明的 shape/dtype/correctness fallback 才能使用，且必须在页面脚注说明。
4. P05～P07 固定标为“通用机制 + 代表算子”：它们分别解释访存/资源复用、并行结构重构、shape-aware 分派与算子内 fusion 如何落在真实算子内核，不声称这三类机制或三个算子穷尽全部 81 个实现。
5. **机制效果的归因口径**：只有存在“仅开/关某一机制”的同配置独立消融，才可写为“该机制 `X×`”。目前可严格独立归因的是 Periodogram setup cache `1.70×`（E2E 下降 `41.24%`）；Wiener Tile/Halo `61.27×`、IIR `1267.88×`、Periodogram R2C+fusion `108.98×` 都只能写为“代表路径整体前后对比”，不得拆分或宣称为该通用机制在全库的最高收益。当前 CPU/GPU E2E 则是成品算子性能，不属于任一机制的独立收益。

---

### P05 通用机制一：访存与资源复用——以 Wiener Tile/Halo 为代表（40 秒）

**核心结论**

> 对同一输入、同一准备资源和相邻输出的重复访问，应在单算子内部优先转化为“加载/准备一次，多次复用”；Wiener Tile/Halo 是这一机制的代表。

**主视觉**

严格采用“通用复用对象 → Wiener Tile/Halo 落地 → 真实效果与边界”三段图：

- 左：三类单算子复用对象：`capacity`（复用可容纳的 Device allocation）、`prepared`（复用 plan/window/table）、`邻域输入`（相邻输出共享输入）。只画“命中 → 直接执行 / 未命中 → 创建后回收”，不画多算子链。
- 中：代表算子 Wiener：三个相邻窗口重复读取同一 global 区域，重构为 `16×16 output tile` 与 `(16+2r)×(16+2c)` shared Tile；线程协作加载 Tile/Halo 后，多输出复用同一块数据。
- 右：按归因强度分三类：`严格独立消融` 的 Periodogram setup cache；`代表路径整体前后对比` 的 Wiener Tile/Halo；`RUN SNAPSHOT` 的成品 Wiener CPU/GPU E2E。三者不得相除、相乘或混写成一个机制的收益。

**效果**

- `[严格独立消融 · setup cache]` `0.659052→0.387250 ms = 1.70x`，E2E 下降 `41.24%`；只证明命名窗口、scale 和频率轴的重复准备复用。
- `[代表路径整体前后对比 · Wiener Tile/Halo]` `214.44→3.50 ms = 61.27x`；记录的主变更是 `16×16 shared-memory tiled stencil`，但当前没有“仅开/关 Tile”的独立消融，因此不得外推为所有邻域算子的机制上限。
- `[RUN CURRENT REPORT · 成品算子]` 1,048,576 点：CPU/GPU E2E `646.387/3.52033 ms = 183.615x`；mixed error `9.75527e-7`。该值不归因给单一机制。

**讲解**

先说明“复用”是单算子层的共同思想，再用 Wiener 的重叠面积解释访存复用如何落地，最后区分块内数据复用与 setup cache 两种收益，不能笼统包装为“一个融合内核”。

**证据**：`src/zhongkexin/filtering.cu:989`、`:4301`；`docs/PERFORMANCE.md:78`；当前 unit summary。
**边界**：Wiener Tile/Halo 仅覆盖 rank=2、两维奇数窗口且每维 `<=31`；auto-noise 标量回传和 mean/variance 中间量仍存在。缓存只对 key 命中资源复用，不是 Unified Memory 或 zero-copy。

---

### P06 通用机制二：并行结构重构——以 IIR Affine Prefix Scan 为代表（40 秒）

**核心结论**

> GPU 不能直接消除数据依赖；必须把递推、归约等算法结构改写为可分块、可结合、可分层的并行结构，IIR Affine Scan 是代表。

**主视觉**

```text
长串行状态链
  → sample affine transform
  → tile-local scan
  → tile transform scan
  → block initial state
  → parallel apply
```

顶部先放“串行依赖 → 结构变换 → 分层并行”的通用箭头；再只放两行 IIR 公式：`s_n=A_n s_(n-1)+v_n` 与 affine compose。中部用红色长链和青绿色 scan 树对比临界路径，底部标出 `tile scan → transform scan → initial state → parallel apply`。

**效果**

- `[代表路径整体前后对比]` lfilter 特定灾难性旧路径 `455.17→0.359 ms = 1267.88x`。该路径同时包含 `BA→单节 SOS` 快路径与 prefix scan 的复用；当前没有“仅开/关 Scan”的独立消融，不能把总收益全部归因给 Scan。
- `[RUN CURRENT REPORT · 成品算子]` 当前较短 lfilter case：GPU event 工作 `1.457x`，但 E2E `0.504x`，说明固定开销足以反转结论。

**讲解**

先说这是单算子内的依赖变换，不是多算子流水；再说明“并行结构问题已经解决，短序列固定成本仍未解决”。这页同时给出技术价值和现实边界。

**证据**：`filtering.cu:2162`、`:2190`、`:2284`、`:3118`；`docs/PERFORMANCE.md:74`；当前 unit summary。
**边界**：fast path 仅低阶、无 state、单连续长线；通用高阶、多线和短序列回退；scan 仍有多阶段 launch 与少量初态串行传播。

---

### P07 通用机制三：Shape-aware 分派与算子内 Fusion——以 Periodogram 为代表（40 秒）

**核心结论**

> 不同 shape、实复类型和算法约束需要不同单算子路径；分派选择正确路径，再融合可合并前后处理，才能同时减少无效计算、读写与 launch。

**主视觉**

页面中央先放 `shape / dtype / order / window → direct | tiled | scan | FFT/R2C` 的分派门；下方再用 Periodogram 展示一条被选中的频谱路径：

```text
旧：detrend → window → C2C FFT → full spectrum → power → crop → scale
新：cached setup → fused prepare → 独立 R2C FFT → fused PSD output
```

完整双边谱与单边谱按真实体积比例绘制；FFT library call 必须保持独立节点。右侧用三张小卡分别标注“R2C 少算负频率”“fusion 少写中间量”“setup cache 少准备”；不能画成 FFT、PSD 和 cache 的一个万能 kernel。

**效果**

- `[代表路径整体前后对比 · R2C+fusion]` `72.91→0.669 ms = 108.98x`；没有 R2C-only 或 Fusion-only 的独立消融，不得分摊给二者之一。
- `[严格独立消融 · setup cache]` `0.659052→0.387250 ms = 1.70x`，E2E 下降 `41.24%`，kernel 基本不变。
- `[RUN CURRENT REPORT · 成品算子]` Periodogram CPU/GPU E2E `1.41709/0.366592 ms = 3.866x`，不归因给单一机制。

**讲解**

先讲分派的决策边界，再用三种颜色分别对应“少算负频率、少写中间量、少做重复 setup”；代表算子说明机制如何落地，不将 Periodogram 当成整个公共库的唯一优化对象。

**证据**：`spectral.cu:1990`、`:2041`、`:2060`、`:2095`；`docs/PERFORMANCE.md:77`；当前 unit summary。
**边界**：FFT 与 PSD 不是单 kernel；plan 为单槽复用；CSD/spectrogram 部分 R2C 因 ZQ500 数值问题保留 C2C。

---

### P08 应用算法一：Task1 按五类路径组合公开算子链（40 秒）

**核心结论**

> Task1 不依赖任务私有 GPU kernel，而是把六个公开算子组合成入口上传、链内驻留、边界统一回传的雷达检测算法。

**主视觉：主链与采用路径一一对应**

```text
template + pulses → entry H2D
  ├→ pulse compression → Doppler/shift → power ─┬→ CFAR → detections ─┐
  │                                             └─────────────────────┴→ two-stage peak
  └→ template → ambgfun side branch
  → output/validation materialize
```

页面右侧必须以“**本任务实际采用的 5 条路径**”列出下列五项，并从每条路径用细连接线指向主链的真实落点；不只在流程上漂浮编号。

1. `Device-resident`：入口仅一次 H2D，六步公开算子 Device 输出直接成为下游输入，验证边界统一 materialize。
2. `prepared/cache reuse`：pulse compression 复用内容完全相同模板的归一化 template FFT。
3. `fusion/direct write`：frequency scale 与 `transpose + fftshift` 在相邻步骤内直接写目标布局。
4. `parallel scan/reduction`：CA-CFAR 用 256-thread row-prefix/integral image；final detection 用两阶段 peak reduction。
5. `compact output`：只将最终 detection list `(r, v, snr, ...)` 回传，不回传全功率图和 dense mask。

用一条青绿色 Device-resident 包围带覆盖入口 H2D 到最终 materialize；ambgfun 必须是模板旁路，peak 同时接收 power 与 detections。底部放“**历史优化前后对比（版本候选，非当前正式 L6；不同 run，不能累加）**”证据带：template cache L6 stage `-7.43%` / total `-2.14%`；transpose+shift L6 stage `-11.57%` / total `-2.03%`；row-prefix CA-CFAR L6 stage `-28.68%` / total `-4.79%`；two-stage peak L6 stage `-43.95%` / total `-4.12%`。Device-resident 没有同配置的独立关闭消融，只作结构事实展示。另设蓝色角标：`任务总效果见 P09：FINAL L6 33.09×`，不得把它归因给任一路径。

**讲解**

先沿主链证明六步调用的是公开 API，不是 task-private bypass；随后从右侧按“驻留、缓存、融合、scan/reduction、紧凑输出”逐条指回真实落点。底部“历史优化前后对比”只说明版本候选曾在独立 run 中降低对应 stage/total，不代表当前运行仍切换该旧路径，不能相加成 `33.09×`；该端到端总效果由 P09 的正式统一测评给出。

**证据**：`task1_radar_demo.cpp:1221`、`:1236`～`:1287`、`:1759`～`:1790`；`types.hpp:923`～`:948`；任务契约；路径级历史优化前后对比见 `docs/PROJECT_LEDGER_notsub.md` 的 `V6-0045`、`V6-0046`、`V6-0048`、`V6-0049`。
**边界**：当前步骤逐次同步计时，不是 multi-stream pipeline；input construction 不属于六个正式计算步骤。
**赛题一致性**：页面中的每个正式步骤必须标为对应公开算子库 GPU 实现；即使某些极小 public case 的 GPU E2E 慢于 CPU，也不能把 Task1 的 GPU 链画成 CPU shortcut。

---

### P09 Task1 性能证据：正式 L1～L6 ZQ500 实测（35 秒）

**核心结论**

> 原 final-input 已纳入新 L6；Task1 在统一协议下保持 `25.53×～33.09×`，L6 中位数为 CPU `364.798 ms`、GPU `11.023 ms`。

**主视觉**

- 左侧：实测 Task1 L1～L6 `speedup = CPU median total / GPU median total` 曲线，L6 橙色标记为原 final-input 配置。
- 中部：新 L6 的 CPU/GPU 中位 total、已计算 `33.09×`；标注 7 次运行且首轮 warm-up 排除。
- 右侧：固定/改变项对照：`固定窗口、CFAR 参数、公开算子链；改变任务输入规模`。
- 下方：Expected/CPU/GPU 检测位置一致，CFAR threshold mixed error `0.276398 < 0.5`，PASS。

**讲解**

这一页不展示旧 task scale 或独立 final-input 数字。答辩时先说明统一协议，再读新 L6 的时间、加速比和正确性；曲线只解释规模效应，不把参数调优混入其中。

**实测数据源**：`data/reports/demo/task1_radar/scales/L1…L6/metrics.json`、`ppt_work/data_tables/task_scaling.csv`。
**边界**：仓库没有独立 NVIDIA/其他传统 GPU 运行记录；仅比较 CPU reference 与 ZQ500 GPU。`application-total` 的输入准备口径仍须在新 run 中同时记录。

---

### P10 应用算法二：Task2 按五类路径构建 Batched Score-Only 流程（40 秒）

**核心结论**

> Task2 不再逐帧物化完整相关、谱图和小波张量，而是批量直接生成四路 score，再完成融合、峰值选择和状态跟踪。

**主视觉：主链与采用路径一一对应**

上方灰色 CPU reference：`for frame → full correlate / spectrogram / CWT → host postprocess`，每步产生大型二维/三维中间量。

下方青绿色 GPU 主路径：

```text
entry H2D per input → batch/residency
  ├→ radix-2 correlate score
  ├→ band-score spectrogram
  ├→ CWT max-score
  └→ filter/demod score
→ weighted + smooth → independent peak → Kalman state chain → materialize
```

右侧必须用“**本任务实际采用的 5 条路径**”面板，并以细连接线逐项对应到下方 GPU 主链，不能只列五个泛化图标：

1. `Device-resident / batch`：输入一次 H2D 后按 `B=8` Device batch 进入主链；任务中间对象不逐帧 `.get()`。
2. `prepared / AOT`：已知 shape 的 correlate、spectrogram 使用预编译 radix-2 / 预准备执行路径；是任务级 helper，与公共库协同而非第三后端。
3. `direct write / task fusion`：filter/demod、相关、谱图和小波直接产出各路 task score；加权/平滑属于 private feature helper，peak 仍是独立 kernel，不能画成万能融合 kernel。
4. `parallel reduction`：band-score、CWT max-score 与 row peak 在频带、尺度或行内提前归约；此处不宣称使用 prefix scan。
5. `score-only / compact output`：不物化全相关/谱图/CWT 张量，只保留四路 score、peak 和 Kalman state/track。

用数据轮廓表现“三维张量 → 一维 score → 每帧一个 peak”。底部放“**历史优化前后对比（版本候选，非当前正式 L6；不同 run，不能累加）**”证据带：Task2 AOT correlate L6 hotspot `-61.66%` / total `-9.77%`；AOT spectrogram L6 hotspot `-43.37%` / total `-7.78%`。其余路径没有独立关闭消融时标“结构已采用，待独立归因”，不得凭 Task2 总加速倒推。另设蓝色角标：`任务总效果见 P11：FINAL L6 1048.78×`，不是任一路径的单独收益。

**讲解**

重点解释应用语义允许“只保留 score”，这是任务特化能够显著压缩工作量的根本原因。随后按右侧五条路径指回主链；明确 AOT 两项有历史优化前后对比，驻留、score-only 等只有结构证据，不能把 `1048.78×` 平摊到它们。

**证据**：`task2_features_demo.cpp:1660`～`:1671`、`:1894`～`:2106`；`task2_features_zx_gpu.cu:2830`、`:3051`、`:3206`、`:3398`、`:3457`；AOT 路径历史优化前后对比见 `docs/PERFORMANCE.md:208`～`:209`。
**边界**：这是 mixed task-specialized pipeline；radix-2 pad 最大 4096；weighted+smooth 与 peak 是独立 kernel；Kalman 跨帧仍串行。Task2 total 同时包含 CPU 逐帧/输入准备与 GPU batch/特化的工作流差异，不能称为纯公共算子或单 kernel 加速比。
**赛题一致性**：private helper 是与公开算子库协同的任务级 GPU 支路，不是绕过库的第三后端；图中必须同时保留 library-operator 和 helper 的边界。

---

### P11 Task2 性能证据：正式 L1～L6 ZQ500 实测（35 秒）

**核心结论**

> 将原 final-input 设为新 L6；冻结 filter/spectrogram/CWT/track 与 score-only 语义，仅改变帧数，端到端加速从 `415.96×` 提升至 `1048.78×`。

**主视觉**

- 左侧：实测 Task2 L1～L6 加速比曲线，L6 为原 final-input 配置。
- 中部：L6 CPU/GPU 中位 total：`28363.050 ms / 27.044 ms = 1048.78×`。
- 右侧：统一协议，固定 batch、score-only、feature/track 门限；只改变输入规模。
- 下方：CPU/GPU 轨迹一致；track RMSE `0.477855 < 2`，feature-score mixed error `9.83703e-5 < 1e-4`，PASS。

**讲解**

P10 已证明 score-only 如何删去中间量；本页用新统一曲线证明这种结构在可比规模下的端到端效果。局部优化开关的保留或回退仍要同时满足正确性和 E2E，但不与规模曲线混算。

**实测数据源**：`data/reports/demo/task2_features/scales/L1…L6/metrics.json`、`ppt_work/data_tables/task_scaling.csv`。
**对比边界**：仅比较 CPU reference 与 ZQ500 GPU；不宣称“相比传统 GPU”。

---

### P12 代码架构：公共语义下的 CPU/ZQ500 双后端与 Task2 特化支路（18 秒）

**核心结论**

> 公共 API 与共享语义定义一致行为，CPU 提供 reference，ZQ500 后端承担并行执行，Task2 helper 是 GPU 侧明确的任务特化支路。

**主视觉**

```text
任务 / 测试 / 用户
        ↓
include/cusignal 公共接口
        ↓
src/common 共享参数、shape、axis、数学语义
        ↓
┌────────────────┬─────────────────────────┐
│ CPU reference  │ ZQ500 GPU backend       │
│ FFTW           │ kernels + FFT/BLAS/Solver│
└────────────────┴───────────┬─────────────┘
                             └→ Task2 specialized helper
        ↓
contracts / unit / demo / reports
```

**讲解**

不逐目录朗读，只指出统一语义、双后端和 Task2 支路三个边界。

**证据**：`CMakeLists.txt:195`、`:226`、`:250`；`docs/ARCHITECTURE.md`。
**边界**：当前只支持 `ZHONGKEXIN` 构建；CUDA-like API 名称来自平台 ABI，不代表 NVIDIA 执行后端。

---

### P13 算子覆盖与公共执行机制：81 个算子共享驻留、复用和门禁能力（18 秒）

**核心结论**

> 12 个模块、81 个注册算子不是 81 套孤立实现；数据驻留、资源复用、shape-aware 分派和正确性/性能门禁构成共同执行基础。

**主视觉**

上半部：12 模块紧凑计数条：`5 | 3 | 23 | 5 | 17 | 6 | 9 | 5 | 3 | 1 | 1 | 3 = 81`。

下半部四条机制：

1. `std::variant Host/Device → entry H2D → Device returns → chain-end .get()`。
2. `shared_ptr<DeviceStorage> → shallow alias → capacity/best-fit reuse`。
3. `prepared key / exact Host content → plan/table/uploaded-copy reuse`。
4. `shape-aware dispatch → correctness gate → E2E gate → fallback`。

**讲解**

只说明 P05～P11 的优化不是任务中的孤立技巧，而是落在完整算子库和公共执行机制中。

**证据**：`operator_sets.json`、`types.hpp:722`、`:866`、`:923`；`filtering.cu:219`；`spectral.cu:264`；`radartools.cu:492`。
**边界**：不是 Unified Memory、zero copy 或 autotuner；Task helper 不计入 81。

---

### P14 正确性与任务运行验证：正式 L6 实测结果（24 秒）

**核心结论**

> 81 个公开算子有性能记录；两条任务的 12 个正式规模点均通过，L6 正确性、性能与统计口径来自同一运行报告。

**主视觉**

- 左侧保留代码与契约覆盖：`81/81 公开算子`、`2/2 端到端任务`、`14/14 正式计算步骤`。
- 右上展示 Task1 L6：Expected/CPU/GPU 检测位置、CFAR error、PASS。
- 右下展示 Task2 L6：CPU/GPU 轨迹一致性、RMSE/feature error、PASS。

**讲解**

不沿用旧 final-input 误差。新 L6 的性能、误差和 run id 必须同源，任何一项未过门限都不能填成 PASS。

**实测数据源**：`data/reports/demo/task{1,2}_*/scales/L6/metrics.json`、`ppt_work/data_tables/l6_correctness.csv`；覆盖事实来自 `tests/contracts/` 与 `data/reports/units/benchmarks/summary.json`。

---

### P15 当前全库性能：81/81 有性能记录，69/78 个详细 case 加速（30 秒）

**核心结论**

> 81 个公开算子都有性能记录；细粒度 case 的收益跨度由算法结构和固定成本共同决定。

**主视觉**

顶部先显示 `81/81 公开算子有性能记录`。主图是 78 个 `case_detail` 按 speedup 排序的 log-scale 散点图，完整保留 `1x` 以下 9 点；右侧显示 `69 快 / 9 慢`、median `17.463x`、geomean `10.113x`。

只标注 Top5、Bottom5、Wiener 和 lfilter。用 Wiener `183.615x` 与 lfilter event `1.457x`、E2E `0.504x` 解释两端。

**讲解**

不读 Top5 榜单，只回答“为什么有的快、为什么有的没有更快”。

**证据**：`data/reports/units/benchmarks/summary.json/csv`。
**边界**：78 个 detailed case 来自 73 个算子；另外 8 个算子只有 `summary_aggregate`。后者不混入 case 排名，但完整 81 算子的 CPU/GPU 时间与直接计算 speedup 见 `ppt_work/data_tables/operator_performance_81.csv`。

---

### P16 端到端 Scaling 与热点：正式 L1～L6 实测（30 秒）

**核心结论**

> Task1 曲线受固定开销影响而在 `25.53×～33.09×` 间波动；Task2 随 batch 规模释放并行度，L6 Top3 已给出下一轮优化优先级。

**主视觉**

- 上方两张独立坐标小图：Task1 / Task2 实测 L1～L6 speedup 曲线；统一使用 `speedup = CPU median total / GPU median total`。
- 下方两张 Top3 表：`ambgfun / input_construction / pulse_doppler` 与 `cwt / input_construction / spectrogram`，使用 L6 final-run GPU event 时间占比。
- 页脚明确：L6 是原 final-input 配置，L1～L5 只改变输入规模；不混入旧 scales/final 数据。

**讲解**

规模曲线回答“并行度何时释放”；热点回答“下一步先优化哪里”。新数据出来后只讲趋势、L6 和各任务 Top1，不逐点读曲线。

**实测数据源**：`data/reports/demo/task{1,2}_*/scales/L1…L6/metrics.json`、`ppt_work/data_tables/l6_hotspots.csv`。
**边界**：GPU event 仅表示 stream work，不解释成单 kernel profiler 时间；在没有同协议 DRAM bytes/FLOPS 时不画 Roofline。

---

### P17 性能优势、边界与改进方向（28 秒）

**核心结论**

> 不把规模变化与参数调优混在同一曲线：先用统一协议建立可比基线，再对参数和热点做独立消融。

**主视觉**

三列短卡，不列尚未复测的任务性能数字：

| 已实现的结构优势 | 统一复测先解决的问题 | 后续参数优化方向 |
|---|---|---|
| Tile/Halo 邻域复用；Affine Scan 递归转并行；R2C+Fusion 减少写回；Device-resident 减少回传 | L6 对齐原 final-input；L1～L5 仅变输入规模；speedup 自动计算；误差与性能同一 run | Block/Halo 尺寸独立消融；CFAR `guard/reference/pfa` 独立消融；batch/shape 独立消融；按新 L6 Top3 优先 |

**讲解**

先说“当前结构已经解决什么”，再说“为什么这次必须统一协议”，最后说明分块、阈值、batch/shape 是**下一步的独立实验变量**，不是本轮 L1～L6 曲线的暗变量。

**边界**：仍不把不存在的 profiler 计数、传统 GPU 基线或尚未完成的参数消融写成结果。

---

### P18 核心亮点：公共算法结构重构与任务级语义裁剪（22 秒）

**核心结论**

> 亮点不在堆叠孤立 kernel，而在于将不适合 GPU 的访存、递归和中间量结构，重写为可复用的 ZQ500 执行结构。

**主视觉**

三张“问题 → 方法 → 价值”卡：

| 亮点 | 问题 | 方法 | 价值 |
|---|---|---|---|
| 邻域访存重构 | 相邻窗口重复读 | Tile/Halo 块内复用 | 服务 Wiener 类算子 |
| 递归与频谱重构 | IIR 递归、双边频谱 | Affine Scan / R2C | 重写为并行结构 |
| 任务级语义裁剪 | 完整中间量物化 | Device-resident / score-only | 只保留 score/轨迹 |

统一复测完成后，再把同一 L1～L6 协议下的新端到端结果填入相应亮点的“效果”位置；本页不使用旧独立 final-input 数字。

---

### P19 AI 工具使用说明（15 秒）

**核心结论**

> AI 用于技术表达与材料整理；所有性能、正确性与源码结论均由仓库文件、结构化 JSON 和人工复核确认。

**页面内容**

- 已确认用途：使用 ChatGPT/Codex 辅助答辩结构梳理、代码/报告审计、图像提示词和 PPT 版面汇编。
- 不用于：生成或改写性能数字、伪造运行截图、替代代码测试或正确性判断。
- 人工复核：README/源码、`metrics.json`、性能表、契约/正确性报告逐项确认；新统一 L1～L6 复测结果仍需由真实运行生成。

**讲解**

10～15 秒带过，准确说明人机边界；如团队还有其他真实 AI 用途，应在制作前补充，不虚构使用记录。

---

### P20 致谢（用户自制，10 秒）

本页由团队自行完成，不纳入技术提示词和生图资产范围。

建议仅保留简洁致谢与 Q&A 提示，不新增数据、技术名词或未验证的结论。

## 6. 页面之间的论证链

整场口播必须形成连续因果关系：

```text
封面 / 团队（快速带过）                       P01-P02
  → 重述赛题交付、验收与三类难题             P03
  → 两层技术路线概括公共优化与两条应用       P04
  → 三页分别证明邻域、递归和频谱优化         P05-P07
  → Task1 流程与性能形成第一组应用证据       P08-P09
  → Task2 流程与性能形成第二组应用证据       P10-P11
  → 回到代码架构、81 算子与公共执行基础      P12-P13
  → 用正确性、全库分布、Scaling 建立证据位     P14-P16
  → 先统一测评，再对参数与热点做独立消融       P17
  → 亮点收束，说明 AI 使用边界，再致谢         P18-P20
```

过渡句建议：

- P03→P04：“赛题要求同时回答算子、任务和证据三件事，下面用两层技术路线组织回答。”
- P04→P05：“先展开技术路线的第一层：三个公共技术分别解决访存、依赖和频谱冗余。”
- P07→P08：“公共算子解决单点结构问题，下一步看它们如何进入完整雷达算法。”
- P09→P10：“Task1 证明公开算子可直接组合；Task2 则进一步利用任务只需要 score 的语义裁剪工作量。”
- P11→P12：“两条应用的统一测评协议已经明确，下面快速说明这些能力如何落在真实代码和 81 算子体系中。”
- P13→P14：“架构和覆盖只是交付范围，最终仍要回到正确性与结构化报告。”
- P16→P17：“统一曲线和热点表会给出可比基线；下一步把规模变化与参数调优拆开做独立消融。”

## 7. 正式图表和素材生成规则

### 7.1 需要生成的主图

| 页面 | 图件 | 数据来源 |
|---|---|---|
| P03 | 赛题交付与三类难题图 | README、contracts、reports |
| P04 | 两层技术路线图 | 当前源码通用机制 + Wiener 单位 benchmark + 两条任务的正式 L6 中位数 |
| P05 | Wiener Tile/Halo + 历史/当前效果 | `filtering.cu`、历史优化前后对比、unit summary |
| P06 | IIR hierarchical scan + 两层时间结果 | affine compose、历史优化前后对比、unit summary |
| P07 | Periodogram before/after + 三类收益 | `spectral.cu` R2C/fusion/cache |
| P08/P09 | Task1 pipeline、正式 L1-L6 速度/正确性数据位 | Task1 source、`task1_radar/scales/L1-L6` metrics |
| P10/P11 | CPU逐帧 vs GPU score-only、正式 L1-L6 数据位 | Task2 source/helper、`task2_features/scales/L1-L6` metrics |
| P12 | 当前软件架构 SVG | CMake + `docs/ARCHITECTURE.md` |
| P13 | 12 模块计数 + 四条公共执行机制 | contracts、types、module caches |
| P14 | 正式 L6 正确性组合图 | 两任务 `scales/L6/metrics.json` |
| P15 | 78 detailed-case log speedup 点图 | benchmark `performance_cases[source=case_detail]`；8 aggregate 另注 |
| P16 | 两任务正式 L1-L6 scaling + 新 L6 Top3 | `scales/L1-L6` metrics |
| P17 | 正式测评与参数独立消融改进方向 | `scale_retest_plan.md`、`evidence.md` |
| P18 | 三项已实现核心亮点 | 当前源码与 `evidence.md` |
| P19 | AI 使用说明 | 团队确认的实际使用记录 |

### 7.2 数据图脚注模板

当前算子图：

```text
ZQ500-Q QUAD-0 | RUN 2026-07-20 SNAPSHOT | GPU warmup=5, repeat=30,
median | E2E includes host-side API path | source: data/reports/units/benchmarks/summary.json
```

统一 Task scaling（已完成）：

```text
ZQ500-Q QUAD-0 | FINAL L1-L6 · 2026-07-21 | 7 runs, first warm-up excluded,
median of remaining 6 | L6 = original final-input configuration |
speedup = CPU median total / GPU median total | application-total includes input preparation
```

历史优化前后对比：

```text
Historical retained candidate | version/protocol as recorded in docs/PERFORMANCE.md or ledger |
not recomputed from the current report
```

### 7.3 不应制作的图

- 无硬件计数器支撑的 Roofline。
- 把 `gpu_e2e_ms` 当成 kernel 时间的堆叠图。
- 把 task `gpu_kernel_ms` 当成单一 kernel profiler 时间；其语义是 GPU event 覆盖的 stream work。
- 把历史 before、当前 CPU 和当前 GPU 拼成一组“统一协议”柱状图。
- 只画 Top5、不画 1x 以下算子的选择性性能图。
- 把 Task2 application stage speedup 标成公共同名算子 speedup。
- 把 `std::variant` 驻留画成 Unified Memory、零拷贝或单次 runtime copy。
- 用 AI 生图生成性能点位、运行轨迹、公式、精确线程索引或真实依赖；AI 只能提供无文字技术底图，精确层由 SVG/PPT 和真实数据覆盖。

## 8. 超时与现场降级策略

若现场在 P11 结束时已经超过 5:20：

- P12 只讲统一语义、双后端、Task2 支路三个边界。
- P13 只报 `81 operators`，公共机制只点“驻留 + 复用”。
- P14 只报 81/81 覆盖和新 L6 的两项 PASS/FAIL。

若 P16 结束时超过 7:20：

- P17 只讲“规模固定参数、参数做独立消融”这一条原则。
- P18 只讲三个亮点中的前两项，不展开页面文字。
- P19 不超过 10 秒；P20 不超过 8 秒。

不可删的页面：P05～P11、P14～P17。它们构成“公共原理与效果 → 应用流程与效果 → 正确性与瓶颈”的完整技术主线。

## 9. 正式制作前门禁

- [ ] 主讲页严格为 20 页，封面和结尾已包含，不额外追加目录、章节页或纯感谢页。
- [ ] 正常语速完整演练不超过 8:33，至少两次演练低于 9:00。
- [ ] P03 的赛题重述有官方赛题/README 依据，P02 只保留真实团队与 AI 使用事实。
- [ ] P05～P07 每页同时有问题、原理、历史优化前后对比/当前单位 benchmark和边界。
- [ ] P08/P10 是应用流程与核心技术；P09/P11 是对应性能与正确性，页组关系清楚。
- [ ] P09/P11 明确说明仓库没有传统 GPU 基线，不出现 NVIDIA/其他 GPU 虚构对比。
- [ ] P13 明确区分设备驻留、RAII 所有权、capacity cache、prepared cache 和精确 Host 内容缓存。
- [ ] 全稿不把 Unified Memory、零拷贝、自动迁移、在线 autotuner、已上线 Graph/multi-stream 表述为当前已有能力；若用于边界说明，必须明确“不是/尚未”。
- [ ] P05～P07 的历史优化前后对比与当前单位 benchmark 使用不同角标；P09/P11/P14/P16 只使用正式 L1-L6 run。
- [x] P09、P11、P14、P16 已记录 ZQ500 `final_l1_l6_v1` 的规模、7 repeats/首轮 warm-up、CPU/GPU 中位数、P95、直接加速比和 raw metrics SHA-256；冻结答辩 commit 时仍须复验。
- [ ] P15 主图只统计 78 个 `source=case_detail`，并明确 81/81 有性能入口、另有 8 aggregate。
- [x] P16 仅使用正式 L1-L6 曲线和新 L6 Top3；未混入旧 task scale/final 数字。
- [ ] task `gpu_kernel_ms` 只标为 GPU event stream work，不解释成单 kernel/profiler 时间。
- [ ] 团队分工和 AI 使用由成员确认，不从 Git/旧删除文档推断。
- [ ] 每个数据图有版本、设备、规模、warmup/repeat、统计量和证据路径。
- [ ] 不增加备份页到正式 20 页文件；问答材料放演讲者备注或单独证据文档。

## 10. 一句话决策

> 采用“赛题重述 → 两层路线 → 三项公共技术 → 两组应用流程/正式测评 → 证据闭环”的结构：P05～P07 分别讲公共技术原理与效果，P08～P11 用“流程 + 正式 L1-L6 测评”两页一组讲两个应用；原 final-input 被纳入 L6，旧任务曲线不进入正式页。主讲 20 页、8 分 33 秒，保留 87 秒余量。
