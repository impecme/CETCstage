# V5.0 性能优化阶段智能体协作计划

## 文档定位

本文档定义 V5.0 性能优化阶段的多智能体协作方式。当前项目已经完成 CPU reference + 中科芯 ZQ500 GPU 全量迁移，V5 依次完成工程与平台兼容基础、任务流水线、核心 53 和全库 81 算子优化。

本阶段采用“多智能体并行分析，主智能体统一落地”的模式。除主智能体外，其他智能体默认只负责阅读、定位、提出方案和风险说明，不直接提交大范围代码修改。

## Skill 与智能体的组合方式

Agent A-H 的职责和文件所有权保持不变。Skill 不新增常驻智能体，而是作为各角色执行任务时
采用的标准方法，由主智能体根据任务信号自动路由。

| 场景 | 负责角色 | 自动采用的 Skill | 产出 |
| --- | --- | --- | --- |
| 指标、显存或算子发生性能回退 | 对应 Agent A-D | `diagnosing-bugs` | 可判红复现命令、最小案例、可证伪假设和根因证据 |
| 实施单算子优化或缺陷修复 | 对应 Agent B-D/F/H | `tdd` | 固定 seam 的失败测试、最小修复和逐级回归结果 |
| 审核代码、精度、报告和阶段交付 | Agent E 配合领域 Owner | `code-review` | Standards 与 Spec 两轴结论 |
| 最终验收后的模块治理 | 主智能体组织相关 Owner | `improve-codebase-architecture` | 只读架构候选报告，确认后另立工作包 |

主智能体派发分析任务时，在原有格式中增加一行 `方法：`：

```text
模块：
方法：diagnosing-bugs / tdd / code-review / architecture-review
发现：
建议：
风险：
需要验证：
涉及文件：
```

默认路由规则：

1. 新功能、修复或单算子优化直接进入 `tdd`，不要求用户额外点名。
2. 已出现错误、异常、波动或回退时先进入 `diagnosing-bugs`，根因明确后才进入修复。
3. 每个可交付 patch 在扩大验证范围前执行 `code-review`。
4. `improve-codebase-architecture` 只用于架构分析；V5.5 关闭前不据此实施大范围拆分。
5. 不因使用 Skill 改变文件 Owner、阶段门禁、容器验证要求或主智能体单一落地原则。

## 阶段计划门禁

V5 性能优化的阶段索引为 `docs/performance/v5_0/README.md`，具体计划位于 `docs/performance/v5_0/plans/`。后续工作必须遵守以下规则：

- 当前阶段计划是范围、顺序和关闭标准的最高优先级依据。
- 本文档后续的工作流和命令属于通用执行模板；与阶段计划冲突时，以当前阶段计划为准。
- 当前阶段未关闭时，辅助智能体不得提前修改下一阶段所属模块。
- 主智能体每轮开始前必须指出当前阶段、当前门禁和本轮对应的计划条目。
- 阶段状态变化必须同时更新计划索引和性能优化台账。

## 当前协作模式

当前开发与验证链路固定如下：

1. 主智能体在宿主机 `/home/usr_04/CETC` 中阅读项目、修改代码、修改脚本和更新文档。
2. 主智能体在宿主机执行同步：

   ```bash
   cd /home/usr_04/CETC
   ./copy_to_container.sh gpu_04
   ```

3. 主智能体把同步脚本打印出的容器内替换命令交给用户。
4. 用户进入容器后执行 `/CETC.incoming.<timestamp>/replace_container_project.sh /CETC`。
5. 用户在容器 `/CETC` 内运行指定验证命令。
6. 用户把日志、报错或报告结果带回宿主机，主智能体据此进入下一轮修改。

由于容器内替换和验证由用户手动执行，多智能体协作必须保持每轮改动小、目标明确、验证命令可复制，避免一次性修改多个无关模块后难以定位问题。

替换脚本会保留唯一构建目录 `/CETC/build-zx`，源码替换后由 CMake 自动增量重配；报告和源码仍以本轮同步内容为准。若需要彻底清理构建，应在容器显式删除 `build-zx`，不再通过每次同步隐式清理。

每次进入容器或新开 shell 后，必须先执行 `cd /CETC && source /zq500/sdk/env.sh`。任务和单元测试脚本也会主动加载该环境，避免 `dlcc` 可见但 `LD_LIBRARY_PATH` 不完整时出现 `libLLVM-15.so` 缺失。

## 协作原则

- 单一落地入口：只有主智能体负责最终代码修改、文档修改和验证命令发布。
- 并行只做分析：辅助智能体可以并行阅读不同模块、整理热点、提出方案，但不得同时改同一文件。
- 小批次推进：每轮只关闭一个明确主题，例如“指标采集”、“device cache 参数化”或“`filtering/lfilter` 专项优化”。
- 先观测后优化：先补齐显存、allocation、copy 和 cache 指标，再修改核心算子。
- 精度优先：任何性能优化不得绕过现有 `mixed_error`、`max_abs_error`、`rmse` 和任务级 validation gate。
- 文档同步：凡影响构建、性能、精度、显存、报告字段或验证流程的关键变化，都必须进入台账或阶段文档。

## 高效推进规则

为减少宿主机与容器之间的往返，每轮工作必须先形成一个小型任务包，再进入代码修改。任务包由主智能体维护，辅助智能体只补充分析结论。

每轮任务包必须包含：

- 目标：本轮只解决一个问题，写清算子、脚本或指标名称。
- 文件范围：列出允许修改的文件；未列出的文件默认只读。
- 验证阶梯：给出 smoke、单算子、模块、全量四级验证中本轮需要执行的最低层级。
- 成功标准：写清性能、显存、误差和报告字段的判定口径。
- 回退条件：写清什么情况需要放弃本轮方案或缩小改动。
- 计划工作包：引用 `V5.x-NN`，不得用临时描述替代阶段编号。
- 回传产物：列出用户需带回的日志、JSON/CSV 和 summary 路径。

辅助智能体分析时只允许输出以下格式：

```text
模块：
方法：
发现：
建议：
风险：
需要验证：
涉及文件：
```

主智能体在落地前必须把多个辅助智能体的结论合并为一个最小 patch，不直接叠加多个互相独立的方案。

计划中尚未实现的命令行参数、脚本或 CMake target 必须在对应工作包内先创建并完成 smoke；后续工作包才能引用。不得要求用户执行仓库中尚不存在的入口。

## 智能体分工

| 智能体 | 负责范围 | 主要文件/模块 | 输出物 | 不负责事项 |
| --- | --- | --- | --- | --- |
| 主智能体 | 统一计划、改代码、改文档、给验证命令、合并结论 | 全项目，重点为 `docs/`、`scripts/platform/`、`scripts/test/`、`include/cusignal/core/`、`src/zhongkexin/` | 可应用 patch、验证命令、阶段总结、台账记录 | 不在未验证前宣布阶段完成 |
| Agent A：指标与报告 | Stage4 指标扩展、显存时间序列、benchmark CSV/Markdown schema、可观测性 | `scripts/platform/run_zhongkexin_stage4.sh`、`scripts/platform/sample_gpu_memory.py`、`scripts/test/benchmark_all_ops_scales.py`、`scripts/test/plot_all_ops_benchmark.py`、`tests/unit/common/report.hpp` | 指标字段方案、报告字段变更清单、兼容风险、验证命令 | 不改核心算子算法 |
| Agent B：显存池与 workspace | device storage cache、模块内 `DeviceBuffer`、workspace 预热和复用策略 | `include/cusignal/core/types.hpp`、`include/cusignal/core/platform_zx_gpu_compat.hpp`、各 `src/zhongkexin/*.cu` 的 `Workspace` / `DeviceBuffer` | cache 参数化方案、显存预算策略、低风险 patch 候选 | 不调整算法数值路径 |
| Agent C：Filtering 热点 | `filtering` 模块慢算子专项优化 | `src/zhongkexin/filtering.cu`、`include/cusignal/filtering/filtering.hpp`、`tests/unit/filtering/` | `lfilter`、`filtfilt`、`wiener` 热点定位、优化方案、精度风险 | 不改 spectral/radar 模块 |
| Agent D：FFT/Spectral/Radar | FFT-heavy 与 radar-heavy 路径优化 | `src/zhongkexin/spectral.cu`、`src/zhongkexin/radartools.cu`、`include/cusignal/spectral/`、`include/cusignal/radartools/`、对应 unit support | FFT plan cache、窗口/segment cache、`periodogram`、`ambgfun`、`mvdr` 优化方案 | 不改 filtering 递推逻辑 |
| Agent E：正确性与交付守门 | 验证矩阵、误差对比、文档台账、回归风险 | `docs/performance/v5_0/optimization_change_log.md`、`docs/submission/`、`scripts/test/README.md`、benchmark 报告目录 | 每轮验证清单、误差变化摘要、文档更新建议 | 不提出未经验证的性能结论 |
| Agent F：类型与算子契约 | 五种实数类型、`complex64`、模板容器、CPU/GPU 接口和 Doxygen 审计 | `include/cusignal/`、`src/common/`、`src/cpu/`、`src/zhongkexin/`、`tests/unit/` | 81 算子类型适用性、接口差异、模板迁移和测试缺口 | 不把不适用类型强加给纯浮点算子 |
| Agent G：平台兼容 | CUDA 11.7 Driver/Runtime 和六类科学计算库完整清单 | `复赛说明文件/`、`CMakeLists.txt`、`scripts/platform/`、平台兼容文档 | 完整 API 矩阵、禁止清单、编译/运行探针和平台限制 | 不运行设备复位等破坏性探针 |
| Agent H：任务流水线 | Task1/Task2 步骤算子化、逐步计时和逐步精度 | `demo/task1_radar/`、`demo/task2_features/`、任务依赖模块 | 私有计算清单、公共算子迁移方案、步骤报告契约和任务回归矩阵 | 不在 V5.2 工程门禁前实施任务重构 |

## 文件所有权与并发规则

多智能体并行分析时按文件所有权分区，避免重复阅读和冲突结论：

| 文件范围 | 默认 Owner | 并行限制 |
| --- | --- | --- |
| `scripts/platform/run_zhongkexin_stage4.sh`、`scripts/test/benchmark_all_ops_scales.py`、绘图脚本 | Agent A | Agent E 可审查字段兼容性，但不提出代码级重写 |
| `include/cusignal/core/types.hpp`、`platform_zx_gpu_*` | Agent B | Agent A 可提出指标需求，实际 cache 方案由 Agent B 归口 |
| `src/zhongkexin/filtering.cu`、`tests/unit/filtering/` | Agent C | 其他智能体不得同时提出 filtering 算法改动 |
| `src/zhongkexin/spectral.cu`、`src/zhongkexin/radartools.cu` | Agent D | Agent B 可只分析 workspace 复用，不改 FFT/radar 算法 |
| `docs/performance/v5_0/optimization_change_log.md`、`docs/submission/` | Agent E | 主智能体最终落地，其他智能体只提供记录素材 |
| `include/cusignal/*/*.hpp`、公共模板和类型矩阵 | Agent F | 各算法 Agent 提供适用类型，Agent F 统一接口和契约 |
| `复赛说明文件/*.xlsx`、平台探针和禁止 API 清单 | Agent G | 其他 Agent 只能提交所需 API，不自行判定平台支持 |
| `demo/task1_radar/`、`demo/task2_features/` | Agent H | 算法实现归入对应模块 Owner，Demo 只保留编排和报告 |

若一个优化跨越多个 Owner，例如 Stage4 指标需要改 `types.hpp` 和 benchmark CSV，必须由主智能体拆成两个顺序 patch：

1. 先落地底层统计能力。
2. 再接入报告生产和消费链路。

禁止把跨 Owner 的底层 cache、核心算子和报告 schema 改动混在同一轮容器验证中。

## 模块边界

### 指标采集边界

指标采集优先覆盖以下内容：

- GPU 显存：benchmark 前后 free/total、算子运行期间峰值、全量运行峰值。
- device allocation：分配次数、释放次数、分配字节、缓存命中/未命中。
- 数据搬运：H2D/D2H 次数和字节量。
- workspace：模块内长期驻留 buffer 的容量和当前有效 size。
- 计时：保留现有 `gpu_e2e_median_ms` 和 `gpu_kernel_median_ms`，新增字段不得破坏历史 CSV 的核心列。

新增字段必须在生产端、消费端、README 或测试说明中同步说明。

### 显存优化边界

显存优化允许优先尝试：

- 将 `DeviceStorageCache` 的总缓存上限和单块上限从编译期常量改为环境变量。
- 增加 cache 统计计数器。
- 在 Stage4 或单算子 benchmark 前增加可选 warmup。
- 将模块内重复 `cudaMalloc/cudaFree` 的 `DeviceBuffer` 接入统一缓存或改为更稳定的复用策略。

显存优化不得引入以下内容，除非先通过平台 probe 证明中科芯 SDK 支持：

- CUDA stream ordered memory pool。
- CUDA graph capture。
- runtime IPC/external memory。
- 未在复赛说明文件中确认可用的 driver API。

### 热点算子边界

下表是技术热点优先级，只在当前阶段允许范围内排序；全局阶段优先级始终是任务依赖 27 > 核心 53 > 全库 81：

| 优先级 | 算子 | 当前现象 | 负责智能体 |
| --- | --- | --- | --- |
| P0 | `filtering/filtfilt` | 最大规模约 `910 ms`，GPU 明显慢于 CPU | Agent C |
| P0 | `filtering/lfilter` | 最大规模约 `455 ms`，GPU 明显慢于 CPU | Agent C |
| P1 | `filtering/wiener` | 最大规模约 `213 ms`，仍有优化空间 | Agent C |
| P1 | `radartools/ambgfun` | 最大规模约 `176 ms`，FFT/二维计算重 | Agent D |
| P1 | `spectral/periodogram` | 最大规模约 `73 ms`，speedup 很低 | Agent D |
| P2 | `radartools/mvdr` | e2e 受矩阵路径和搬运影响 | Agent D |
| P2 | `wavelets/ricker`、部分 `windows/*` | 单核/公式类 kernel 可能并行度或访存不理想 | Agent B/D 按归属分析 |

## 工作流

### 第 0 步：建立 V5.0 协作与基线文档

主智能体新增或更新：

- `docs/performance/v5_0/README.md`
- `docs/performance/v5_0/agent_collaboration.md`
- `docs/performance/v5_0/`

本步只改文档，不改执行链路。

### 第 0.5 步：生成每轮任务包

每轮开始前，主智能体先写出本轮任务包。示例：

```text
V5.0-R1 指标补齐
目标：给 DeviceStorageCache 增加 allocation/cache 统计，并在单算子 metrics 中可读。
允许修改：include/cusignal/core/types.hpp、tests/unit/common/report.hpp、scripts/test/benchmark_all_ops_scales.py。
不修改：src/zhongkexin/filtering.cu、spectral.cu、radartools.cu。
最低验证：filtering/wiener L6 concise benchmark。
成功标准：benchmark 通过，新增字段非空，mixed_error 不变或仍通过 gate。
回退条件：新增统计导致编译失败、benchmark schema 破坏、或单算子耗时明显异常。
```

任务包不必写入文档，但必须在每轮对用户的交付说明中体现。

### 第 1 步：指标补齐

Agent A 分析现有 Stage4 和 unit report，提出最小字段集。主智能体落地后，用户在容器运行轻量验证：

```bash
cd /CETC
RUN_TASK_SWEEP=0 \
BENCH_MODULES=filtering \
BENCH_OPERATORS=wiener \
BENCH_SCALE_LEVELS=6 \
BENCH_WARMUP=1 \
BENCH_REPEAT=3 \
BENCH_REPORT_MODE=concise \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/v5_metrics_probe \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage5_metrics_probe.log
```

通过后再扩展到热点子集。

### 第 2 步：显存池参数化和观测

Agent B 给出 cache 上限、单块上限、统计字段和环境变量方案。主智能体落地后，用户对同一热点子集分别运行默认配置和扩大缓存配置，比较：

- `gpu_e2e_median_ms`
- `gpu_kernel_median_ms`
- GPU 显存峰值
- allocation/cache hit 统计
- `mixed_error`

只有同时满足性能可解释且精度通过，才保留该机制。

### 第 3 步：V5.2 工程规范与平台兼容

按 `plans/V5_2_plan.md` 执行。Agent F 完成 81 算子接口和类型契约，Agent G 完成三个复赛表的全量兼容矩阵与探针，主智能体分模块落地公共模板和测试基础。本阶段不把计划类型写成已实现能力。

### 第 4 步：V5.3 任务与 27 个依赖算子

按 `plans/V5_3_plan.md` 执行。Agent H 先审计任务私有计算，算法 Owner 将其迁入公共模块；每一步同时提供 CPU/GPU 计时、speedup 和精度。随后按阶段耗时优化 27 个依赖算子和任务数据流。

### 第 5 步：V5.4 核心 53 算子

按 `plans/V5_4_plan.md` 执行。在任务 27 基础上处理核心非任务 26，完成接口、类型、测试和性能审计，最终达到核心 53/53。

### 第 6 步：V5.5 扩展 28 与全量回归

按 `plans/V5_5_plan.md` 完成扩展 28，达到全库 81/81。随后用户在容器执行全量 Stage5：

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage5_full \
STAGE4_REPORT_ROOT=data/reports/zhongkexin/stage5_full_latest \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage5_full.log
```

全量回归必须保持：

- Task1/Task2 L1-L6 通过。
- 81 个算子、486 行 benchmark 全部通过。
- 五种实数适用组合和 `complex64` 专项测试通过。
- 完整平台兼容探针和禁止 API 扫描通过。
- 图件生成通过。
- 新增性能/显存字段完整生成。
- 性能优化项有对应文档解释。

## 验证阶梯

每轮容器验证按从小到大的阶梯执行。除非上一级通过，否则不进入下一级。

| 阶梯 | 用途 | 典型命令 | 进入条件 | 退出条件 |
| --- | --- | --- | --- | --- |
| L0 静态检查 | 宿主机快速排错 | `bash -n`、`python3 -m py_compile`、`git diff --check` | 每轮 patch 后立即执行 | 无语法和格式错误 |
| L1 单算子 smoke | 验证最小运行闭环 | 单个 `BENCH_MODULES` + 单个 `BENCH_OPERATORS` + `BENCH_SCALE_LEVELS=6` | L0 通过 | 单算子 `status=passed`，新增字段完整 |
| L2 模块子集 | 验证同模块副作用 | 一个模块全算子或热点子集 | L1 通过且改动影响模块共享代码 | 模块内目标行通过，无明显误差峰值 |
| L3 任务 demo | 验证任务级副作用 | Task1/Task2 L3 或 L1-L6 | 改动影响 demo 依赖算子或报告字段 | `validation.pass=true` |
| L4 全量 Stage | 关闭阶段或合并大改 | 81 算子 486 行 full benchmark | 多个热点完成或报告 schema 改动完成 | 486/486 通过，图件和文档证据完整 |

默认情况下：

- 文档-only 改动只需要 L0。
- 指标字段改动需要 L1，若改 CSV/plot 消费端则需要 L2。
- `types.hpp` cache 改动至少需要 L2，稳定后再进入 L4。
- 单个热点算子算法改动需要 L1 + 对应模块 L2。
- 影响 Task1/Task2 依赖算子的改动需要追加 L3。
- 类型模板或公共接口改动至少需要适用类型编译矩阵和所属模块 L2。
- 平台兼容矩阵改动需要静态清单校验；探针代码改动需在容器执行对应 CMake probe target。

## 失败分流规则

容器验证失败后，用户只需要带回对应日志和最新报告路径。主智能体按以下顺序分流：

1. 编译失败：先看 `build-zx` 编译日志和首个 error，不继续分析性能。
2. 运行崩溃：先定位是否为非法内存、资源超限、FFT 点数或 SDK API 约束。
3. correctness 失败：先比较 `mixed_error`、`max_abs_error`、`rmse` 和 near-zero 统计，不继续做性能结论。
4. 性能退化：先看 allocation、copy、cache、显存峰值和 e2e/kernel 拆分。
5. 报告字段失败：先修生产端和消费端 schema，不改核心算子。

若同一轮同时出现 correctness 失败和性能退化，优先修 correctness。没有 correctness 通过的性能数据不能作为优化依据。

## 产物命名

为避免覆盖 V4 交付基线，V5 运行产物使用独立目录：

- 轻量指标 probe：`data/reports/unit/benchmarks/v5_metrics_probe`
- Filtering 单算子：`data/reports/unit/benchmarks/v5_filtering_<operator>`
- FFT/Radar 子集：`data/reports/unit/benchmarks/v5_fft_radar_probe`
- Stage5 full：`data/reports/unit/benchmarks/zhongkexin_stage5_full`
- Stage5 汇总：`data/reports/zhongkexin/stage5_full_latest`

日志文件命名统一使用：

```text
stage5_<topic>.log
```

不要覆盖 `stage4_full_v48.log`、`zhongkexin_stage4_full_v48/` 或当前 V4.8 关闭证据。

## 每轮交付格式

主智能体每轮修改结束时必须给出：

- 修改文件列表。
- 本轮目标。
- 预期影响。
- 宿主机已执行的静态检查。
- 用户需要在容器内执行的命令。
- 需要用户带回的日志或报告路径。

用户带回容器结果后，主智能体必须先判断：

- 是否通过 correctness。
- 是否通过性能 gate。
- 是否存在新误差峰值。
- 是否存在显存异常增长或泄漏。
- 是否进入下一轮，或需要回滚/修正本轮方案。

## 进入下一轮的门禁

满足以下条件才允许开始下一轮优化：

- 本轮允许修改的文件已经固定，没有遗留半成品。
- 用户带回的容器验证结果已经被记录或总结。
- 若本轮改了执行链路，至少有 L1 验证通过。
- 若本轮改了核心算子，至少有对应单算子 L1 通过。
- 若本轮失败，已经明确是修正继续、缩小范围还是放弃方案。

不满足门禁时，下一轮只能做修复或回滚，不能继续叠加新的性能优化。

## 文档与台账要求

V5.0 性能优化台账独立维护，不再写入 V4 迁移台账：

- V4 迁移台账：`docs/migration/zhongkexin/change_log.md`
- V5 性能优化台账：`docs/performance/v5_0/optimization_change_log.md`

只有发现新的中科芯平台迁移兼容性问题时，才回写 V4 迁移台账；普通性能优化、显存策略、benchmark 字段、workspace 改造和验证流程变化均写入 V5 台账。

以下变化必须记录到 `docs/performance/v5_0/optimization_change_log.md` 或 V5 阶段文档：

- 调整 device cache 策略或显存预算。
- 新增或修改 benchmark/report 字段。
- 修改核心算子算法、数值路径或 FFT/BLAS/SOLVER 调用方式。
- 调整 accuracy/performance gate。
- 引入平台相关 fallback。
- 因中科芯 SDK 限制放弃某个优化方案。

每个 V5 子阶段都必须维护对应交付文档，V5.0 总阶段关闭时再更新总交付：

```text
docs/submission/READMEV5_1.md
docs/submission/READMEV5_2.md
docs/submission/READMEV5_3.md
docs/submission/READMEV5_4.md
docs/submission/READMEV5_5.md
docs/submission/READMEV5_0.md
```

交付文档至少包含：

- V5.0 目标。
- 核心性能优化措施。
- 显存与 workspace 策略变化。
- 热点算子优化前后对比。
- 精度验证结果。
- 五种实数类型适用性和 `complex64` 专项结果。
- CUDA 11.7 与六类科学计算库兼容矩阵和探针结果。
- 全量 Stage4/Stage5 验证结果。
- 遗留风险。

## 禁止事项

- 禁止多个智能体同时修改同一文件。
- 禁止在没有容器验证结果时删除旧实现或扩大改动面。
- 禁止只用 GPU 利用率或显存占用率证明性能优化有效；必须同时给出耗时和误差结果。
- 禁止为了提高显存占用而保留无用 buffer。显存占用提高必须服务于减少分配、减少搬运、增加批量并行或复用 workspace。
- 禁止引入未确认的中科芯 SDK 高级 API。
- 禁止绕过 `scripts/platform/run_zhongkexin_stage4.sh` 和现有 unit report 链路另起不可复现的 benchmark。

## 第一轮建议（已完成）

第一轮只做低风险基础设施：

1. 指标方案落地。
2. `DeviceStorageCache` 增加可观测统计。
3. Stage4 报告新增公共 cache 指标。
4. 用 `filtering/wiener` L6 做轻量 probe。

第一轮公共 cache 字段包括：

- `device_cache_allocation_calls`
- `device_cache_allocation_mib`
- `device_cache_hits`
- `device_cache_misses`
- `device_cache_recycled_blocks`
- `device_cache_recycled_mib`
- `device_cache_cached_blocks`
- `device_cache_cached_mib`
- `device_cache_peak_cached_mib`

第一轮新增环境变量包括：

- `CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS`
- `CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB`
- `CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB`

显存峰值、GPU 利用率峰值、H2D/D2H copy 字节和模块内本地 `DeviceBuffer` 统计不放入第一轮；这些需要单独的采样或更大范围改造，待公共 cache probe 通过后再拆分推进。

第一轮不直接修改 `lfilter`、`filtfilt`、`periodogram` 或 `ambgfun` 算法，避免在缺少指标的情况下扩大风险。
