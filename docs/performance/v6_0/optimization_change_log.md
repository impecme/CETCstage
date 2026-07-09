# V6 性能优化台账

## 文档定位

本文档记录 V6 任务优先深度优化阶段的来源调研、候选方案、实际改动、验证结果和回退原因。V6 只记录第六版执行过程，不再追加到 V5 台账。

## 记录规则

- 凡影响 Task1/Task2 性能、任务相关算子、workspace/cache、FFT plan、kernel fusion、报告字段或验证命令的变化，必须进入本文档。
- 每条记录必须说明来源措施、赛题约束判断、计划修改、实际修改、验证命令和状态。
- correctness 未通过时，不记录性能收益结论。
- 候选优化失败或退化也必须记录为 `暂缓` 或 `已回退`。
- 容器日志、完整 probe 和图件统一放到 `/home/usr_04/CETC_garbage/`。

## 状态枚举

- `待确认`：现象或候选已发现，尚未定位。
- `待修改`：已确认需要改动，但尚未实施。
- `修改中`：正在实施。
- `待验证`：已修改，等待容器验证。
- `已关闭`：验证通过，记录完整。
- `已回退`：验证失败或性能退化，代码已恢复。
- `暂缓`：当前不做，需写明原因和触发条件。

## 记录模板

| ID | 阶段 | 模块/文件 | 类型 | 来源措施 | 赛题约束判断 | 计划修改 | 实际修改 | 验证命令 | 状态 | 后续处理 |
|---|---|---|---|---|---|---|---|---|---|---|
| V6-XXXX | V6.0 | 示例 | 性能/调研/回退 | 示例来源 | 示例判断 | 示例计划 | 示例修改 | 示例命令 | 待确认 | 示例后续 |

## 当前记录

| ID | 阶段 | 模块/文件 | 类型 | 来源措施 | 赛题约束判断 | 计划修改 | 实际修改 | 验证命令 | 状态 | 后续处理 |
|---|---|---|---|---|---|---|---|---|---|---|
| V6-0001 | V6.0-00 | `docs/performance/v6_0/plans/V6_0_plan.md` | 调研/规划 | CUDA shared memory/coalescing、CuPy memory pool、CuPy signal direct/FFT/auto convolution、CuPy CWT per-width convolution、SciPy STFT/Welch/CSD 语义、CUDA Graph launch overhead、GPU overlap-save convolution | 可采用项必须保持 CPU/GPU 精度、五类实数和 complex64 兼容、ZQ500 CUDA 11.7 API 兼容；CUDA Graph 和 overlap-save 需先做平台探针，不能直接假设可用 | 将 V6 从方向性规划升级为任务优先深度优化计划；明确 Task1/Task2 强目标、P0/P1/P2 分层、可采用措施和阶段工作包 | 已更新 V6 plan，新增本台账；后续每个候选必须登记来源、约束判断和容器验证 | 文档修改：`git diff --check`；后续容器基线按 V6.0-01 执行 | 已关闭 | 进入 V6.0-01 基线和 V6.0-02 平台探针 |
| V6-0002 | V6.0-00 | `docs/performance/v6_0/plans/V6_0_plan.md` | 论文调研/规划 | GPU overlap-save shared-memory FFT、fCWT、CUDA Graph 性能评估、GPU prefix-sum/scan、GPU CA-CFAR、GPU 雷达实时处理、GPU MVDR、并行 FFT 性能分析 | 论文策略只能作为候选；必须通过 ZQ500 容器 correctness、dtype、task smoke 和 timing 验证；不允许牺牲任务步骤计时/精度字段 | 增加论文策略对照，把候选转成 V6.0-02 平台探针和 V6.0-03/V6.0-06 深化方向 | 已在 V6 plan 中新增论文策略、参考链接和落地约束；重点加强 CWT、filter/correlate、CFAR、MVDR、FFT layout/plan/cache | 文档修改：`git diff --check` | 已关闭 | 后续每个论文候选需要单独新增记录，例如 `V6-010x` probe、`V6-020x` 实现、`V6-090x` 回退 |
| V6-0003 | V6.0-00 | `docs/performance/v6_0/plans/V6_0_plan.md` | 论文引用/文档 | overlap-save、fCWT、CWT fast algorithms、prefix-sum、CA-CFAR、GPU radar processing、MVDR、parallel FFT、CUDA Graph 论文或论文类资料 | 参考论文只作为策略来源，不作为实现完成证明；后续必须逐项验证 | 将论文从普通链接中单独列出，便于后续报告引用和方案追溯 | 已新增“参考论文”列表，保留题名、作者/年份可得信息和 URL/DOI | 文档修改：`git diff --check` | 已关闭 | 后续实现记录引用对应论文编号或标题 |
| V6-0100 | V6.1-01 | `/home/usr_04/CETC_garbage/` | 日志/基线 | V6.1 容器基线命令 | 中间日志必须在仓库外；不能把 probe 或 benchmark 长表写入 `data/reports/` 作为长期文件 | 定位 `cetc_v6_0_01_02` 或 `cetc_v6_1_baseline` 回传包，抽取 Task L1-L6、all81、重点算子和平台探针结论 | 已扫描 `/home/usr_04/CETC_garbage/` 和 `/tmp`，未定位本轮 V6 包或 `task_l1_l6_repeat5.log`、`focus_operator_benchmark`、`cuda_graph_probe` 产物 | 本地扫描：`find /home/usr_04/CETC_garbage ...`、`find /tmp ...` | 待确认 | 需要补充回传包具体路径；拿到后更新 V6.1 关闭证据和热点排序 |
| V6-0101 | V6.1-00 | `docs/performance/v6_0/plans/` | 规划 | 参照 V5.1-V5.5 小版本计划格式 | V6 内容只写入 `docs/performance/v6_0/`；计划不得要求中间日志进入仓库 | 将 V6.0 工作包拆成 V6.1-V6.8：基线探针、Task2 两批、Task1 两批、P1/P2、全量收束 | 已新增 `V6_1_plan.md` 至 `V6_8_plan.md`，更新 V6 README 索引 | 文档修改：`git diff --check` | 待验证 | 待日志路径确认后，把 V6.1 状态从待分析改为已关闭或待修改 |
| V6-0102 | V6.1-02 | `/home/usr_04/CETC_garbage/v6_container_logs_20260709_211736` | 日志/热点 | 用户确认日志需要从容器取回；宿主无 docker 组权限但 `sudo docker cp` 可用 | 只读复制容器 `/tmp` 到宿主临时目录，再筛选到仓库外垃圾目录；不复制到 `data/reports` | 从活跃容器中定位 V6 Task2/STFT/CFAR 探针，形成可分析证据包 | 已从 `gpu_22(7b876b01f923):/tmp` 取回 7月8日/9日探针目录并打包为 `/home/usr_04/CETC_garbage/v6_container_logs_20260709_211736.tar.gz`；Task2 新 STFT 路径约 `27.57 ms` 且 verification `26/26`，旧 Task2 约 `35.46 ms`；剩余热点为 `kalman≈8.60 ms`、`noise_signal≈5.60 ms`、`linspace≈3.17 ms` | 本地：`sudo docker cp ...:/tmp ...`，`git diff --check` | 已关闭 | 这批日志不是完整 all81/L1-L6 终测包；只能作为下一步热点依据，不能关闭 V6.1 全量基线 |
| V6-0200 | V6.2-03 | `demo/task2_features/task2_features_zx_gpu.cu` | 性能 | V6.2 `spectrogram` score-only；CUDA Best Practices 减少重复 host/device copy 和重复预计算 | 不改变公共 `spectrogram` API，不改变 Task2 step schema；只缓存 direct band score 的 cos/sin 表和 scale，窗口值不同会失效重建 | 缓存 Task2 direct spectrogram band score 的三角表，减少 repeat 和同配置运行中的 host trig 构造、H2D 上传和 device allocation | 已新增 direct spectrogram table cache：键包含 `nperseg/nfft/band/fs/window`；命中时复用 `direct_cos_table/direct_sin_table` 和 scale | 本地：`git diff --check`；待容器：`scripts/test/run_task_demos.sh --build-dir build-zx --build --scale-sweep --scales 1,2,3,4,5,6 --repeat 3 --require-visualization-deps`，再跑 `spectral/spectrogram` 与 Task2 L6 repeat=5 | 待验证 | 容器验证通过后比较 `latest_spectrogram_breakdown.csv` 中 `direct_band_score` 和 Task2 L6 GPU total；失败则回退缓存改动 |
| V6-0201 | V6.2-04 | `demo/task2_features/task2_features_zx_gpu.cu` | 性能 | V6.2 `cwt_score`；fCWT 思路中的 wavelet/kernel table 复用 | 不改变公共 `wavelets/cwt` API，不改变 Task2 `cwt` step schema；只缓存 Task2 `batched_cwt_max_score` 的 morlet2 kernel table | 缓存固定 widths/sample_count 的 CWT kernel table，减少 repeat 和同规模运行中的 host kernel table 构造、H2D 上传和 device allocation | 已新增 CWT kernel table cache：键包含 `widths` 和 `sample_count`；命中时复用 `cwt_kernel_sizes/starts/offsets/real/imag` | 本地：`git diff --check`；待容器：`scripts/test/run_task_demos.sh --build-dir build-zx --build --scale-sweep --scales 1,2,3,4,5,6 --repeat 3 --require-visualization-deps`，再跑 Task2 L6 repeat=5 | 待验证 | 容器验证通过后比较 Task2 `cwt` step 和 L6 GPU total；失败则回退缓存改动 |
| V6-0202 | V6.2-05 | `demo/task2_features/task2_features_demo.cpp`、`demo/task2_features/task2_features_zx_gpu.cu` | 性能 | 取回容器日志 `/home/usr_04/CETC_garbage/v6_container_logs_20260709_211736`：Task2 STFT 新路径已降至约 `0.63 ms`，剩余热点为 `kalman≈8.60 ms`、`noise_signal≈5.60 ms`、`linspace≈3.17 ms` | 不改变 V5.5 报告 schema；Task2 `measurement_conversion` 步骤仍保留，`measurement_values` 仍可输出；不改变 `kalman_track_from_peaks_zx_gpu` 输入输出类型 | 去掉 Task2 GPU resident 链路中 `peak_track -> measurement_values` 的一次 device copy/launch；Kalman 输出不再 zero-fill，因为 kernel 写满输出 | `measurement_values` 直接复用 `peak_track` 的 device signal；`measurement_conversion` 计时为 `0.0 ms`；`kalman_track_from_peaks_zx_gpu` 输出用未初始化 device allocation | 本地：`git diff --check`；待容器：Task2 L1-L6 repeat、Task2 L6 repeat、`estimation/kalman_filter` 单测/benchmark | 待验证 | 若 validation 通过但收益小，下一步转向 `noise_signal` 和 `linspace`；若 measurement 误差或 schema 失败，则恢复 copy kernel |
