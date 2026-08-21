# 技术路线与任务机制页 V3

本目录保存按现有答辩 PPT 风格、经提示词打磨后重新生成的技术路线页、算子机制页和任务机制页。
本轮新增 P05、P12、P14 当前口径版本，不覆盖 `ppt_work/final_images/` 中的旧页面，也不修改性能展示页。
提示词见 `mechanism_prompts_v3.md`；上一轮提示词仍保留在 `mechanism_prompts_v2.md`。

## 页面

| 页面 | 文件 | 内容 |
|---|---|---|
| P05 | `P05_技术路线_三加二加五_v12_机制更新.png` | 3 类公共算子机制、2 条任务链、5 类任务路径 |
| P06 | `P06_算子机制_离线自动调优_v01.png` | 离线候选筛选、完整调优键、形状感知分派、路径选择、缓存和安全回退 |
| P07 | `P07_算子机制_Tile布局归约_v01.png` | Tile、共享数据、分层归约和路径选择 |
| P08 | `P08_算子机制_非内核开销复用_v01.png` | 每轮资源独立、执行内资源复用、完整 H2D/D2H 和 E2E 开销计入 |
| P12 | `P12_任务一_五类路径机制_v06.png` | 任务一设备驻留、FFT 资源复用、CFAR 扫描和紧凑输出 |
| P14 | `P14_任务二_五类路径机制_v13.png` | 任务二批处理、仅评分、并行归约和紧凑跟踪输出；五类路径不再混放代表算子加速比 |
| P05 新版 | `P05_技术路线_三加二加五_v13_当前口径.png` | 3+2+5 总览；任务指标改为当前 autotune CPU→GPU E2E |
| P12 新版 | `P12_任务一_五类路径机制_v07_当前口径.png` | Task1 实际阶段链、ambgfun 质量分析旁路和本轮资源协议 |
| P14 新版 | `P14_任务二_五类路径机制_v14_当前口径.png` | Task2 批量评分、特征融合、并行归约和紧凑跟踪 |

## 数值口径

- Task1 当前 L6 CPU→GPU E2E：`7.49x`。
- Task2 当前 L6 CPU→GPU E2E：`481.37x`。
- 任务级 GPU 优化前后提速比：当前没有正式配对数据，不在任务机制页展示。
- P06 代表 `lombscargle`：端到端 `194.03x`，内核 `195.65x`，提速 `2.78x`。
- P07 代表 `wiener`：端到端 `102.12x`，内核 `199.70x`，提速 `32.92x`。
- P08 代表 `vectorstrength`：端到端 `85.36x`，内核 `106.76x`，提速 `1.73x`。

机制页右栏口径：P06–P08 每页只保留端到端加速比、内核加速比和提速比。右栏
代表算子来自当前仓库报告 `/home/usr_04/CETC/data/reports/autotune/units/benchmarks/operator_scales.csv`：
先过滤正确性 PASS、输入刷新通过、记录可比且 GPU 优化前后提速比大于 1.05x 的记录，
再按 CPU→GPU E2E 加速比从高到低选取；GPU 前后提速比按 frozen baseline
`/home/usr_04/CETC/data/baseline/gpu_baseline.csv` 的 GPU E2E 除以当前 GPU E2E 计算。
不写规模后缀，不展示范围、负收益或 N/A 结果，原始记录仍保留在性能报告中。左侧和中部保持机制解释，不因右栏排序重画。P14 右上角的
`Task2 L6 E2E 481.37x` 是当前任务 CPU→GPU 端到端加速比；五类路径旁只解释机制，
不再放代表算子数字，避免把算子指标误读为任务链路加速比。

端到端、内核和提速三个指标来自同一记录；右栏不再写 CPU/GPU 字样。

任务机制页口径：P05/P12/P14 只展示当前任务 CPU→GPU E2E 标尺；不把算子级 GPU
基线和任务级结果相加，也不把 GPU 优化前后提速比写成任务结论。P12 的主链与旁路
对齐 `data/reports/autotune/demo/task1_radar/stages/L6.csv`；P14 的 GPU 路径对齐
`data/reports/autotune/demo/task2_features/stages/L6.csv`。每轮独立输入、完整 H2D/D2H，
资源复用只限单次执行内部，跨 repeat 不复用。

数据入口：

- `ppt_work/data_tables/task_scaling.csv`
- `ppt_work/data_tables/operator_case_speedups.csv`
- `/home/usr_04/CETC/data/reports/autotune/units/benchmarks/operator_scales.csv`
- `/home/usr_04/CETC/data/baseline/gpu_baseline.csv`
- `/home/usr_04/operator_gpu_optimization_research.md`

代表算子选择按同一 workload 的正确性 PASS、输入刷新通过、记录完整、GPU 前后提速比大于 1.05x，
再按当前报告中的 CPU→GPU E2E 加速比降序执行；页面只显示单值，不显示规模后缀。

P06 的形状感知分派依据明确列为：`规模阈值 / 内存布局 / 算法参数 / 平台校验`；
候选路径族列为：`直接计算 / 分块共享内存 / FFT·R2C / 并行扫描 / 形状特化核`。
这些是按单算子工作负载选择的候选路径，不是串行执行步骤，也不是任务级链路。

P06 左侧的 `N×F / dtype / layout` 只表示键摘要：`N×F` 是逻辑工作量形状，
`dtype` 是数据类型，`layout` 是内存布局。实际 `TuningKey` 还包含
`family / operator / shape / dtype / layout / batch / semantic`；设备/平台校验是独立的
兼容性门，不是形状字段。页面因此把“完整调优键 → 形状感知分派 → 候选路径”
画成左侧显式流程。

P08 的“复用”限定为单次 warmup/repeat 内部：同一 repeat 的 forward/inverse、频域
乘法等阶段可以复用本轮已经新建的 buffer/workspace；跨 repeat 必须释放并重新分配
输入、device buffer、workspace、plan 和 event。严格测试中每个 warmup/repeat 都重新
生成逻辑输入、完整 H2D、执行、完整 D2H/materialize，并计入分配/计划/事件开销。
因此，旧的“跨轮资源复用”表述和基于该口径采集的性能数据不能直接作为本口径结果。

输入示意中 `x/y` 只标注 `N 个样本`，`f` 只标注 `F 个频点`，单独用
`逻辑工作量：N×F` 表达计算规模，避免三行重复写同一乘积。分派路径明确包含
`形状与参数匹配 → 形状特化核`，它与 Tile、通用、FFT/R2C、并行扫描是互斥候选路径，
不是额外串行步骤。`静态旧路径` 不属于形状感知分派集合，只出现在离线候选验证
和缓存未命中、设备不匹配、资源不足或门禁失败后的安全回退路径。

自动调优参数统计（按当前 all81 候选注册表去重）：所有公共算子共使用 **13 个
候选参数维度**，按算子取其子集：`threads`、`elements_per_thread`、
`rows_per_block`、`vector_width`、`stages`、`tile_rows`、`tile_cols`、
`scan_elements`、`buffer_count`、`batch_tile`、`memory_tier`、
`plan_variant`、`route`。当前报告把其中 12 个数值配置字段展开为
`tuning_threads` 至 `tuning_plan_variant`，`route` 编码在
`tuning_candidate`/候选名称中；这不是 81×13 个独立参数。完整候选 profile
共有 1386 个候选组合，two_day profile 共有 881 个候选组合；候选组合数不等于
参数维度数。`workspace_bytes`、`workspace_peak_bytes` 是测量结果，不是调优参数。

注意：当前报告中 Lomb–Scargle 代表行的 `tuning_key` 为空，因此 P06 左侧的
完整键和分派图是通用机制示意，不宣称该行已有实际缓存命中。

生成记录：

- 六个旧版 PNG 已使用内置图像生成能力按 `mechanism_prompts_v2.md` 逐页生成并保留。
- 本轮 P05/P12/P14 使用内置图像生成能力按 `mechanism_prompts_v3.md` 逐页编辑生成：
  `P05_技术路线_三加二加五_v13_当前口径.png`、
  `P12_任务一_五类路径机制_v07_当前口径.png`、
  `P14_任务二_五类路径机制_v14_当前口径.png`。
- `ppt_work/final_images/` 和性能展示页未改动。
- `ppt_work/scripts/generate_mechanism_pages_v2.py` 是此前的版式草稿脚本，不是本次最终 PNG 的生成来源。
