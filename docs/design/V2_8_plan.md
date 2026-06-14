# V2.8 Report 全量统一到 `waveforms/sawtooth`

## 摘要

- 这次统一的不只是 `latest_cases.csv`，而是整套 report 产物：算子级 `latest_summary.md`、`latest_metrics.json`、`latest_cases.csv`，以及模块级同名 3 个文件。
- 以 `waveforms/sawtooth` 的算子级 report 作为唯一 canonical 模板，以 `waveforms` 的模块级 report 作为模块聚合模板。
- 范围只包含 的 `windows`、`filter_design`、`filtering`；`waveforms` 作为基线，不做 schema 回退，但也迁到同一套共享 writer，确保后续不再漂移。
- `filter_design`、`filtering` 还要补齐当前缺失的模块级 `latest_cases.csv` 和算子级 `history/.../cases.csv`。

## 关键改动

- 抽出共享 report writer。
- 在 `tests/unit/common` 增加一套 header-only 的 canonical report 组件，负责统一生成 markdown / json / csv 以及模块聚合。
- 四个模块的 test support 都先把本地 `CaseReport` / `OperatorSummary` 映射到公共 report model，再调用同一套 writer。
- `waveforms` 也切到这套 writer，但生成结果必须与当前 `sawtooth` / 模块级 `waveforms` schema 保持一致，不能借机改 canonical 形状。

- 单算子 `latest_metrics.json` 全部统一到 `waveforms/sawtooth` schema。
- 顶层字段固定为：`module`、`operator`、`generated_at`、`git_commit`、`gpu_name`、`compile_config`、`summary`、`cases`。
- `summary` 固定为扁平字段：
  - `pass`
  - `accuracy_cases`
  - `perf_cases`
  - `max_abs_error`
  - `max_rel_error`
  - `rmse`
  - `gpu_e2e_speedup`
  - `gpu_kernel_speedup`
  - 可选 `reference_error`
  - 可选 `cpu_perf` / `gpu_e2e_perf` / `gpu_kernel_perf`
- case 级固定使用 `case_id`，不再出现 `id`。
- 每个 case 始终输出 `cpu_gpu_error`；有 reference 时追加 `cpu_reference_error`、`gpu_reference_error`。
- 每个 case 的 `artifacts` 始终显式输出数组；无 artifact 时写 `[]`。
- artifact 固定使用绝对路径，并补齐 `sha256`。
- 允许的额外 case 字段只保留：
  - `note`
  - `cpu_reference_error`
  - `gpu_reference_error`
  - 多输出相关 artifact role，例如 `cpu_indices`、`gpu_indices`、`cpu_state`、`gpu_state`、`cpu_time`、`gpu_time`
- `windows`、`filter_design`、`filtering` 当前缺失的 `git_commit`、`gpu_name`、`compile_config` 必须补齐。
- `filter_design`、`filtering` 当前 summary 中的嵌套 `cpu_gpu_error` 改成 sawtooth 的扁平 summary 字段，不再保留模块自定义 summary 形状。

- 单算子 `latest_summary.md` 全部统一到 `waveforms/sawtooth` 结构。
- 标题固定为 `# <module>/<operator> Summary`。
- 固定段落顺序：基础信息、`## Errors`、`## Performance`、`## Cases`。
- `## Errors` 至少包含 `gpu_vs_cpu max_abs/max_rel/rmse`；存在 reference 时补 `reference max_abs/max_rel`。
- `## Performance` 的字段顺序和 sawtooth 对齐：`cpu` 三项、`gpu_e2e` 三项和 speedup、`gpu_kernel` median 和 speedup。
- `## Cases` 的每行统一为 `- <case_id>: pass|fail, max_abs=<...>`。
- 失败原因仍留在 JSON 的 `note`；markdown 不再使用各模块自定义的压缩展示方式。

- 单算子 `latest_cases.csv` 精确统一到 sawtooth schema。
- 列头固定为：
  `case_id,backend,metric_kind,samples,warmup,repeat,mean_ms,median_ms,p95_ms,min_ms,max_ms,std_ms,max_abs_error,max_rel_error,rmse,l2_error,exact_match`
- 每个 case 展开成多行：
  - 始终输出 `gpu_vs_cpu,error`
  - 有 reference 时再输出 `cpu_vs_ref,error` 与 `gpu_vs_ref,error`
  - 有 perf 时输出 `cpu,perf`、`gpu_e2e,perf`、`gpu_kernel,perf`
- error 行只填误差列，perf 行只填 timing 列。
- 不再保留 `category`、`pass`、`note` 这些压缩列。
- `windows`、`filter_design`、`filtering` 当前一行一 case 的压缩 CSV 全部移除。

- 模块级 report 统一到 `waveforms` 模块模板。
- 模块级 `latest_summary.md` 固定为：
  - `# <module> Summary`
  - `generated_at`
  - `## Operators`
  - 每个 operator 一行：`PASS/FAIL, max_abs, max_rel`
- 模块级 `latest_metrics.json` 固定为：
  - 顶层 `module`、`generated_at`、`operators`
  - 每个 operator 记录统一使用 `operator` 字段，不再混用 `name`
  - 每个 operator 至少包含 `pass`、`max_abs_error`、`max_rel_error`、`gpu_e2e_speedup`、`gpu_kernel_speedup`
  - 可选附带 `cpu_perf` / `gpu_e2e_perf` / `gpu_kernel_perf`
- 模块级 `latest_cases.csv` 统一为模块内各算子 canonical `latest_cases.csv` 的拼接，列头和内容完全复用 sawtooth schema。
- `filter_design`、`filtering` 当前缺失的模块级 `latest_cases.csv` 本轮补齐。

- 历史快照统一。
- 算子级 `history/<timestamp>/summary.md|metrics.json|cases.csv` 都使用与 `latest_*` 完全相同的 canonical schema。
- `windows` 保持现有 history 布局不变，只统一内容。
- `filter_design`、`filtering` 补齐算子级 `history/`，并写入 `summary.md`、`metrics.json`、`cases.csv`。
- 模块级不新增 `history/`，继续与 `waveforms` 当前模式一致。

- 多输出与失败场景按 canonical 规则保留扩展语义。
- `waveforms/gausspulse` 保留多 artifact 输出。
- `filter_design/cmplx_sort` 保留 `indices` 相关 artifact 和误差，但主 report schema 仍按 canonical。
- `filtering` 中带 `state` / `time` 的算子保留对应 artifact role。
- 失败算子的 `note` 只保留在 JSON，CSV 不再承载失败说明。

## 公共接口与数据约定

- 不修改生产库 API、数值逻辑和测试判定逻辑。
- 这轮只统一 report 产物 schema，不再改 `data/reference/unit` 或 `data/generated/unit` 的测试数据 schema。
- 当前用户提到的 `latest_case.json` / `latest_case.md`，仓库里实际对应的是 `latest_metrics.json` / `latest_summary.md`；本轮统一以这两个真实文件名为准。
- canonical report 口径固定为：
  - 算子级基线：`waveforms/sawtooth`
  - 模块级基线：`waveforms`
- `waveforms` 其他算子不要求“长得像 sawtooth 的数据文件”，但 report writer 必须走同一套 canonical schema 生成链路，避免后续再次分叉。

## 测试与验收

- 重建 `waveforms`、`windows`、`filter_design`、`filtering` 的 unit test support 和算子目标，确保共享 writer 编译通过。
- 重跑：
  - `./scripts/test/run_all_tests.sh --module waveforms --emit-report`
  - `./scripts/test/run_all_tests.sh --module windows --emit-report`
  - `./scripts/test/run_all_tests.sh --module filter_design --emit-report`
  - `./scripts/test/run_all_tests.sh --module filtering --emit-report`
- 不要求顺带修复现有数值失败；只要求 PASS/FAIL 两种情况下 report schema 都一致。

- 验收点：
  - `windows`、`filter_design`、`filtering` 的算子级 `latest_metrics.json` 顶层字段与 `waveforms/sawtooth` 一致。
  - 非 `waveforms` case 记录中不再出现 case 级 `id`，统一为 `case_id`。
  - 非 `waveforms` 的 case `artifacts` 一律存在，且每项都带绝对路径和 `sha256`。
  - `windows`、`filter_design`、`filtering` 的算子级 `latest_summary.md` 段落和字段顺序与 `waveforms/sawtooth` 一致。
  - 非 `waveforms` 的 `latest_cases.csv` 列头与 sawtooth 完全一致，不再出现 `category`、`pass`、`note`。
  - 模块级 `latest_summary.md` / `latest_metrics.json` / `latest_cases.csv` 都统一到 `waveforms` 模板。
  - `filter_design`、`filtering` 生成算子级 `history/.../summary.md|metrics.json|cases.csv`。
  - 多输出和失败场景仍保留必要扩展语义：
    - `waveforms/gausspulse`
    - `filter_design/cmplx_sort`
    - `filtering/resample`
    - `filtering` 带 `state` / `time` 的算子

## 假设与默认决策

- `bsplines` 明确不在本轮范围内。
- `waveforms/sawtooth` 是唯一算子级 canonical 基线；若其他模块当前字段与它冲突，一律向它收敛。
- `waveforms` 模块本身也接入共享 writer，但输出以“不改变当前 canonical schema”为准，而不是借机重新设计。
- `latest_cases.csv` 不承载失败说明；失败原因统一留在 `latest_metrics.json`，必要时在 `latest_summary.md` 体现基础状态。
