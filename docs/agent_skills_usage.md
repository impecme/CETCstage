# Matt Pocock Skills 使用指南

## 已安装技能

技能安装在 `~/.codex/skills/`：

- `code-review`：按项目规范和需求目标审查代码变更。
- `tdd`：以测试先行方式实现功能、修复缺陷或优化算子。
- `diagnosing-bugs`：诊断错误、性能回退、显存异常和数值异常。
- `improve-codebase-architecture`：分析模块边界并生成架构审查报告。

同时安装了上述流程依赖的：

- `setup-matt-pocock-skills`
- `codebase-design`
- `domain-modeling`
- `grilling`

安装或更新技能后需要重启 Codex，当前会话可能无法发现新技能。

## 调用方式

技能路由已经写入 `AGENT.md` 和现有多智能体协作流程。重启 Codex 后只需正常描述任务，
不需要记忆或显式输入 skill 名称。例如：

```text
优化 filtering/wiener，并保证精度和显存不退化。
```

主智能体会自动采用 `tdd`；如果过程中出现性能回退，则切换到
`diagnosing-bugs`；形成 patch 后执行 `code-review`。

只有需要更换 issue tracker、启用 triage 或重建领域文档布局时，才运行
`setup-matt-pocock-skills`。日常代码优化不需要运行它。

## 日常调用

### 1. 审查当前改动

必须提供一个固定比较点，并尽量提供阶段计划或交付文档作为需求依据：

```text
使用 code-review 审查从 HEAD~1 到当前 HEAD 的改动。
需求依据是 docs/performance/v5_0/plans/V5_5_plan.md。
重点检查项目规范、数值正确性、性能证据和验证门禁。
```

审查未提交改动时可改为：

```text
使用 code-review 审查当前工作区相对 HEAD 的改动，
需求依据是 docs/performance/v5_0/plans/V5_5_plan.md。
```

注意：原始 `code-review` 流程主要面向提交之间的 diff。工作区审查无法直接使用时，让 Codex按相同的 Standards/Spec 两轴进行本地审查。

### 2. 测试驱动地优化一个算子

一次只处理一个算子，并明确公共测试接口：

```text
使用 tdd 优化 filtering/wiener。
测试 seam 是公开 cusignal 算子接口及现有 unit target。
先固定 CPU/GPU 精度、GPU e2e、kernel、显存和 cache 基线，
再按 red-green 循环修改。只做单个纵向切片，不扩大范围。
```

CETC 推荐验证阶梯：

```text
单算子 accuracy/benchmark
→ 所属模块 full
→ Task1/Task2 smoke（若受影响）
→ V5.5 全量 gate
```

### 3. 诊断错误或性能回退

描述精确症状、输入规模和可运行环境：

```text
使用 diagnosing-bugs 诊断 filtering/lfilter 在 L6 上
GPU e2e 变慢的问题。先建立快速、确定、可判红的复现命令，
再最小化案例并提出 3～5 个可证伪假设。
在确认根因前不要修改生产代码。
```

显存异常示例：

```text
使用 diagnosing-bugs 分析连续运行 30 次后 GPU 显存增长。
结合 gpu_mem_changes.log、cache 统计和单算子 benchmark 建立复现循环。
```

该技能的关键约束是：没有能捕获原始症状的复现循环，就不进入猜测和修复阶段。

### 4. 分析代码架构

建议在 V5.5 最终验收完成后使用，避免架构重构干扰当前性能基线：

```text
使用 improve-codebase-architecture 分析 CETC。
优先检查 src/zhongkexin/filtering.cu、spectral.cu、
radartools.cu 和对应测试 support 的模块深度、接口、seam 与 locality。
只生成候选方案和 HTML 报告，暂不修改代码。
```

该流程会把报告写到 `/tmp/architecture-review-<timestamp>.html`。选择候选方案后，再通过追问确定模块接口和测试边界。

## CETC 推荐工作流

```text
正常优化：tdd → code-review → 逐级验证
发生异常：diagnosing-bugs → tdd 回归测试 → code-review → 逐级验证
阶段关闭：code-review → 全量门禁
验收之后：improve-codebase-architecture → 新建独立重构工作包
```

## 使用原则

- 每轮只处理一个明确问题，不同时修改无关算子。
- 性能优化必须同时保留精度、耗时、显存/cache 和复现证据。
- 宿主机适合静态检查；ZQ500 构建和运行结论以项目指定容器为准。
- 不让技能读取或引用 `.zq500_sdk_full.delete_me`。
- 技能提供工作方法，不能替代仓库已有的 V5.5 阶段门禁。
