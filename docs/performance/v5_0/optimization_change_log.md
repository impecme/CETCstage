# V5.0 性能优化台账

## 文档定位

本文档用于记录 V5.0 性能优化阶段的关键问题、优化措施、报告字段变化、验证结果和暂缓项。

阶段划分、当前执行点和关闭门禁见 `docs/performance/v5_0/README.md` 与 `docs/performance/v5_0/plans/`。

V4 及以前的中科芯迁移不兼容、构建适配、命名收口和报告 schema 中性化记录仍保留在 `docs/migration/zhongkexin/change_log.md`。V5.0 起，性能优化阶段的台账独立维护在本文档中，避免迁移问题和优化问题混在一起。

## 记录规则

- 凡影响性能、显存、workspace、缓存、报告字段、benchmark 口径或验证流程的 V5.0 变化，必须进入本文档。
- 每条记录必须说明优化目标、实际措施、CPU/ZQ500 影响、验证命令和当前状态。
- correctness 未通过时，不记录性能收益结论。
- 显存占用提高必须对应明确目的，例如减少 allocation、提高 cache hit、减少搬运、扩大批处理或复用 workspace。
- 若某项只完成 L1/L2 probe，状态保持 `待验证`；只有完成本阶段规定的关闭验证后才能标记 `已关闭`。

## 状态枚举

- `待确认`：现象已发现，尚未定位。
- `待修改`：已确认需要改动，但尚未实施。
- `修改中`：正在实施改动。
- `待验证`：改动已完成，等待或正在进行容器验证。
- `已关闭`：验证通过，记录完整。
- `暂缓`：暂不处理，需写明原因和后续触发条件。

## 记录模板

| ID | 阶段 | 模块/文件 | 类型 | 现象 | 原因判断 | 计划修改 | 实际修改 | CPU/ZQ500 影响 | 验证命令 | 状态 | 后续处理 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| V5-XXXX | V5.0 | 示例 | 性能/显存/报告/验证 | 示例现象 | 示例原因 | 示例计划 | 示例修改 | 示例影响 | 示例命令 | 待确认 | 示例后续 |

## 当前记录

| ID | 阶段 | 模块/文件 | 类型 | 现象 | 原因判断 | 计划修改 | 实际修改 | CPU/ZQ500 影响 | 验证命令 | 状态 | 后续处理 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| V5-0001 | V5.1 | `include/cusignal/core/types.hpp`、`tests/unit/common/report.hpp`、`scripts/test/benchmark_all_ops_scales.py`、`scripts/test/README.md`、`docs/performance/v5_0/agent_collaboration.md` | 性能/报告 schema/可观测性 | Stage4 full 只能看到耗时、speedup、误差和设备名，缺少 device allocation、cache hit/miss、cache 驻留字节等指标，难以解释低 e2e speedup 或显存占用变化 | 下一阶段要优化显存利用和 workspace 复用，必须先补公共 device storage cache 的可观测性；第一轮不触碰核心算子算法，降低容器验证风险 | 将 `DeviceStorageCache` 上限参数化并新增线程本地统计；unit `latest_metrics.json` / Markdown 输出 `summary.device_storage_cache`；all-ops benchmark CSV 展开 `device_cache_*` 字段；V5 协作文档规定产物目录和验证阶梯 | 已完成公共 cache 统计与报告字段接入；默认缓存上限保持 8 blocks、512 MiB 总量、256 MiB 单块，新增环境变量 `CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS`、`CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB`、`CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB`；容器 L1 `filtering/wiener` L6 probe、filtering 17 算子 L2 和全模块 81 算子行 schema smoke 均已通过 | 不改变 CPU reference 或 ZQ500 算法数值路径；报告 schema 为向后兼容的字段扩展；统计范围明确为 `DeviceSignal`/`DeviceArray` 公共 storage cache，模块内本地 `DeviceBuffer` 纳入后续阶段按热点处理 | `python3 -m py_compile scripts/test/benchmark_all_ops_scales.py`; `git diff --check`; `stage5_metrics_probe` 1/1 PASS；`stage5_filtering_l2` 17/17 PASS；`stage5_schema_l2_all` 81/81 PASS，`cache_missing_rows=0`，`plot_status=passed` | 已关闭 | V5.1 可观测性阶段关闭；整卡显存采样见 V5-0002，模块内部 `DeviceBuffer` 和真实性能优化按 V5.3-V5.5 计划推进 |
| V5-0002 | V5.1 | `scripts/platform/sample_gpu_memory.py`、`scripts/platform/run_zhongkexin_stage4.sh`、`docs/performance/v5_0/agent_collaboration.md` | 显存/报告/验证 | 现有 `device_cache_*` 只统计公共 cache 内部行为，不能直接说明运行期间整卡显存峰值、平均显存和利用率变化；外部 `gpu_mem_changes.log` 也不随 Stage4 报告归档 | 性能优化阶段需要把“显存占用提升”变成可复验指标；必须自动采样 `dlsmi`，并把 time series 与 summary 放进 Stage4 报告目录 | 新增项目内 GPU memory sampler；Stage4 operator benchmark 运行期间后台采样，结束后写 CSV/JSON；Stage4 summary 增加 `gpu_memory_*` 字段；采样失败不影响 correctness/benchmark 结果 | 已新增 `scripts/platform/sample_gpu_memory.py`；Stage4 默认 `STAGE4_GPU_MEM_MONITOR=1`，采样间隔由 `STAGE4_GPU_MEM_INTERVAL` 控制；报告新增 `latest_gpu_memory_samples.csv`、`latest_gpu_memory_summary.json`、`gpu_memory_available`、`gpu_memory_used_mib_max`、`gpu_memory_used_mib_avg`、`gpu_memory_free_mib_min`、`gpu_memory_util_percent_max` 等字段；监控进程通过 EXIT trap 清理，benchmark 失败时也不会残留；容器 L1 `filtering/wiener` probe 已确认写出 time series 与 summary | 不改变 CPU reference 或 ZQ500 算子路径；只增加后台 `dlsmi` 采样进程和报告字段；如果 `dlsmi` 不可用或字段不兼容，summary 标记 unavailable，Stage4 不因此失败 | `python3 -m py_compile scripts/platform/sample_gpu_memory.py`; `bash -n scripts/platform/run_zhongkexin_stage4.sh`; 宿主机 `sample_gpu_memory.py --max-samples 1` 已确认可写 CSV/JSON；容器 `stage5_gpu_mem_probe.log` PASS，`benchmark_rows=1`，`benchmark_failed_rows=0`，`gpu_memory_available=true`，`gpu_memory_sample_count=76`，`gpu_memory_used_mib_max=615`，`gpu_memory_used_mib_avg=320.92105263157896`，`gpu_memory_free_mib_min=15769`，`gpu_memory_util_percent_max=100`，`filtering/wiener` `mixed_error=9.75527e-07` | 已关闭 | 后续所有性能优化可用 `latest_gpu_memory_samples.csv` 和 `latest_gpu_memory_summary.json` 对比显存峰值、平均显存和 GPU 利用率 |
| V5-0003 | V5.4（提前） | `src/zhongkexin/filtering.cu` | 性能/kernel/shared memory | `filtering/wiener` L6 1024×1024、5×5 自动噪声基线为 `gpu_e2e_median_ms=214.436`、`gpu_kernel_median_ms=212.496`，公共 cache 已有 8 hits 且无 eviction/free，主要耗时集中在通用 N 维局部统计 kernel | 通用 kernel 每个输出线程维护 N 维坐标数组，并为窗口内每个元素重复执行维度循环和 offset 计算；二维小窗口还会让相邻线程重复从 global memory 读取高度重叠的邻域 | 增加二维奇数小窗口专用 tiled kernel，以 16×16 block 将带 halo 的输入块加载到 shared memory；保持行优先累加顺序、零填充边界、自动噪声 reduction 和 ZQ500 D2H fallback 不变；N 维、偶数窗口和大窗口继续走原 kernel | 已新增 `wiener_local_stats_2d_tiled_kernel`；rank=2、两维窗口为奇数且不超过 31 时启用；1024×1024、5×5 perf case 使用 16×16 tile 和 20×20 shared input tile，显著减少重复 global load 与动态 N 维 offset 计算；容器稳定 benchmark 和 full 回归均确认快路径生效 | 不改 CPU reference、公开 API、噪声估计、apply 公式和输出布局；累加仍按窗口行优先顺序执行；现有 3×4、3×3 accuracy case 已验证非方形输入与边界，1024×1024、5×5 perf case 已验证目标快路径 | CPU 语义模拟与原通用语义完全一致；`cusignal_zx_gpu` 宿主机 `dlcc` 编译通过；容器 L6 warmup=5/repeat=30 PASS：`gpu_e2e_median_ms=3.49952`、`gpu_kernel_median_ms=3.37212`、`mixed_error=9.75527e-07`；相对旧 1/3 probe 基线，E2E 约 61.28×、kernel 约 63.02×，但因 warmup/repeat 不同仅作初步对比；峰值显存从 615 MiB 降至 487 MiB；容器 full PASS：accuracy_cases=1、perf_cases=1，CPU/GPU `max_abs=7.748604e-07`、`max_rel=9.755279e-07`、`rmse=2.980232e-08`，reference `max_abs=5.960464e-08`，`gpu_e2e_median_ms=3.578`、`gpu_kernel_median_ms=3.397` | 已关闭 | wiener 归入核心 53 提前完成项；下一步按 V5.2 完成工程规范、类型契约和平台兼容基础，再进入 V5.3 任务优化 |
| V5-0004 | V5.2 | `README.md`、`docs/performance/v5_0/`、`docs/submission/READMEV5_*.md` | 计划/工程规范/类型/平台兼容 | 原计划先优化任务和算子，未把目录职责、五种实数类型、complex64 唯一复数口径、算子封装和完整平台 API 兼容作为前置门禁 | 若后期再补类型和接口会导致任务及 81 算子重复改造，平台 API 也缺少完整审计责任 | 重排 V5.2-V5.5，先关闭工程与兼容基础，再依次处理任务 27、核心 53 和全库 81 | 已重写 V5 总计划、阶段计划、交付口径和协作分工；README 增加目录结构；正式实数类型固定为 FP32、FP16、INT32、INT16、INT8，复数只允许 complex64 | 本轮为计划和文档口径修改，不宣称五种类型或完整 API 探针已经实现；已有 Wiener 性能证据不变，仅阶段归属改为 V5.4 提前完成 | `git diff --check`、阶段引用和状态检查 | 已关闭 | 按 V5.2 继续生成 81 条逐算子契约和完整平台兼容矩阵 |
| V5-0005 | V5.2 | `docs/performance/v5_0/plans/`、V5 索引和协作文档 | 计划可执行性 | 阶段计划只有目标和关闭标准，缺少领取顺序、固定接口、命令、产物和失败回退，实际推进时仍需临时决策 | 宿主机修改与用户容器验证需要小批次、可复制、可回传的工作包，否则多智能体和多轮容器往返容易失控 | 为 V5.2-V5.5 增加编号工作包、允许范围、固定脚本/target 接口、基线与回归命令、回传产物和关闭条件 | 已把当前队列锁定为 V5.2-01；后续阶段统一使用 operator set、单热点验证阶梯和阶段报告目录；明确尚未创建的入口必须由前置工作包先实现 | 只修改计划执行口径，不改变现有算法和报告结果 | `git diff --check`、工作包/命令/产物字段检查 | 已关闭 | 下一轮实施 V5.2-01，不并行实施 V5.2-02 |
| V5-0006 | V5.2-01 | `scripts/test/operator_sets.json`、`operator_set_support.py`、`validate_operator_sets.py`、benchmark/Stage4 入口、81 行契约清单 | 集合/验证/报告接口 | 任务 27、核心 53、扩展 28 和全库 81 只存在于人工文档，后续命令需要复制长列表且无法自动发现遗漏、重复或阶段范围漂移 | 缺少机器可读唯一来源和严格集合关系检查；Stage4 也不能直接按阶段集合运行 | 固化 all81/task27/extended28 显式清单并由 all81-extended28 派生 core53；校验注册表、数量、集合关系和真实模块路径；benchmark 增加 `OPERATOR_SET` 交集过滤；生成 81 行契约骨架 | 已实现四集合 JSON、共享 loader、严格校验脚本、81 行清单和 benchmark/Stage4 接口；指定命名集合且未显式设置 `BENCH_MODULES` 时自动使用 all，避免历史 waveforms 默认误过滤 | 不改 CPU/GPU 算法和数值路径；仅改变显式使用 `OPERATOR_SET` 时的 benchmark 目标选择；默认 `OPERATOR_SET=all` 保持历史行为 | Python 3.8 py_compile、`bash -n`、注册表/路径/集合校验、benchmark 过滤测试、81 行生成、`git diff --check` 均通过 | 待验证 | 同步容器后运行 V5.2-01 smoke，回传四集合计数和 Stage4 帮助/语法结果 |

## 阶段关闭要求

V5.0 关闭前至少需要：

- 本文档中无 `待修改` 或无解释的 `待验证` 项。
- 关键优化项都有优化前后性能、显存或 cache 指标对比。
- correctness gate 通过。
- Stage5 full 通过，且报告和图件生成完整。
- `docs/submission/READMEV5_0.md` 总结核心优化措施、验证结果和遗留风险。
