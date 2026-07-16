# V6.0 任务优先深度性能优化规划

## 定位

第六版从 V5 的迁移验收中独立出来，只做性能深化。优化优先级按赛题价值排序：

1. Task1/Task2 端到端 GPU 性能。
2. 两个任务直接相关算子。
3. 赛题明确提到的算子库热点。
4. 原 cuSignal 有、但赛题未提到且不影响任务链路的算子，暂不继续优化。

V6 允许更激进的数据流重排、workspace 复用、kernel fusion、FFT plan/cache 复用和任务级公共 fused operator，但必须保持 V5.5 的接口、类型、精度、步骤报告和平台兼容要求。

执行顺序固定为 Task2 P0、Task1 P0、内部执行基础设施、任务相关 P1、赛题算子 P2。详细代码审计、实测热点和 Amdahl 预算见 `../performance_audit.md`。

智能体协作按 `../agent_collaboration.md` 执行：主智能体是唯一常驻写入者，阶段 Owner 默认只读，`gpu_04` 正式测量全局串行，patch 在昂贵全量回归前接受 Standards/Spec 双轴审查。协作规则不改变本计划的范围、顺序或关闭门禁。

## 小版本交付规则

- V6.0 总交付索引为 `docs/submission/READMEV6_0.md`。
- V6.1-V6.8 每个小版本必须维护对应的 `docs/submission/READMEV6_x.md`，格式参考 V5。
- 每次小版本状态、保留优化或关闭结论变化时，同步更新计划、台账和交付文件。
- 小版本关闭时，交付文件必须包含范围、保留/回退项、性能对照、correctness、证据路径和下一阶段。
- 未关闭阶段只记录已验证结果和待交付门禁，禁止把计划值写成完成值。
- 容器长日志、probe 和图件仍留在 `/home/usr_04/CETC_garbage/`，交付文件只引用结论和路径。

## 开源措施对照

| 来源 | 可借鉴措施 | V6 落地方式 |
|---|---|---|
| CUDA Best Practices | shared memory 复用 global 数据、合并非连续访问、减少重复访存 | 对 FIR、CWT、CFAR、局部统计、ambgfun 矩阵构造继续做 shared-memory tile 和 coalesced 输出 |
| CuPy memory pool | 用 device/pinned memory pool 降低 allocation 与同步开销 | 扩展现有 `DeviceStorageCache`，建立任务级 workspace plan，Task1/Task2 整条链路复用 buffer |
| CuPy signal `convolve/correlate` | direct/FFT/auto，长卷积用 FFT 或 overlap-add/overlap-save | Task2 filter/correlate 引入规模阈值；L5/L6 优先评估 FFT/overlap-save，短模板保留 direct shared tile |
| CuPy wavelets CWT | CWT 本质为每个 width 调一次 convolution | Task2 不再默认落完整 CWT 矩阵；新增公共 `cwt_score` 路径，把多尺度 convolution、abs/reduce/score 融合 |
| SciPy spectral | Welch/CSD/coherence 可视为 STFT/spectrogram 上的平均和交叉谱 | `spectrogram/welch/csd/coherence` 统一 segment pack、window cache、FFT plan、magnitude/reduce kernel |
| CUDA Graph | 固定形状多 kernel pipeline 可减少累计 launch overhead | 先做 ZQ500 runtime graph 支持探针；支持则捕获 Task1/Task2 L1-L6 固定 pipeline，不支持则手工 fused stage |
| GPU overlap-save convolution | 长信号短滤波器用 overlap-save 分块并减少 device memory transaction | Task2 filter/correlate 的 L5/L6 候选；要求与直接卷积误差一致后才能替换 |
| CuPy launch-parameter optimize | 对 shape/dtype 缓存更优 block/thread 配置 | 为高频 task kernels 增加按 scale-level 的静态 launch config 表，不在运行时反复试探 |

## 论文策略对照

| 来源 | 可借鉴措施 | V6 落地方式 |
|---|---|---|
| GPU overlap-save 共享内存 FFT 论文 | 对长信号短滤波器，按块做 overlap-save，块内 FFT 尽量用 shared memory，降低全局内存和库 FFT 调度开销 | Task2 `filter/correlate/cwt` 建立 direct、dlFFT、shared-memory overlap-save 三路阈值探针；只在 L5/L6 与误差通过时替换 |
| fCWT 论文 | 将 CWT 分为 scale-independent 与 scale-dependent 操作，复用 FFT，并利用 downsampled wavelet 降低每尺度成本 | Task2 `cwt` 不再以完整矩阵为默认目标；优先实现 wavelet cache、频域复用和 score-only reduce 路径 |
| CUDA Graph 性能评估论文 | 重复工作流中 kernel launch 和 memory transfer 开销会压低 GPU 收益，Graph 可复用依赖图降低这些固定开销 | 对 Task1/Task2 L1-L6 固定形状建立 graph capture 探针；若 ZQ500 runtime 不支持，则把同一收益目标转为手工 fusion/workspace resident |
| GPU Gems scan / prefix-sum | work-efficient scan 可把局部统计、前缀和、压缩和直方图类顺序依赖改写为并行基础块 | Task1 `ca_cfar`、Task2 peak/top-k、局部均值/能量统计优先使用 prefix-sum 或 tiled scan，替换逐 CUT 重复访问 |
| GPU CA-CFAR 论文 | CA-CFAR 可用 naive、sliding window、summed-area table 三类方案，SAT 在大窗口更有潜力，但小窗口需实测 | `ca_cfar` 不固定采用积分图；按窗口半径和 map 尺寸选择 naive shared tile、sliding window 或 SAT |
| GPU 雷达实时处理论文 | FFT/preprocess 容易获得 GPU 收益，CPU postprocess 和 host/device 边界会成为瓶颈 | Task1 保持 CFAR、peak、measurement、报告中间值尽量 device resident，只回传最终少量标量 |
| GPU MVDR 论文/实现经验 | MVDR 中 covariance 与 inverse/solve 是核心瓶颈，显式 inverse 容易带来性能和一致性风险 | `mvdr` 用 `X^H X` covariance、diagonal loading 和 small Hermitian solve；优先 `solve` 替代显式 inverse |
| 并行 FFT 论文 | FFT 性能强依赖 batched transform、数据布局和通信/访存模型，批处理和布局选择可能比单 kernel 微调更重要 | `spectrogram/stft/welch/csd/coherence/pulse_doppler` 统一 segment layout 和 batched FFT plan/cache，避免分散构造 |

参考链接：

- CUDA shared memory/coalescing: https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html
- CuPy memory pool: https://docs.cupy.dev/en/stable/user_guide/memory.html
- CuPy signal direct/FFT/auto convolution: https://github.com/cupy/cupy/blob/main/cupyx/scipy/signal/_signaltools.py
- CuPy CWT convolution-per-width: https://github.com/cupy/cupy/blob/main/cupyx/scipy/signal/_wavelets.py
- SciPy STFT/Welch/CSD 语义: https://github.com/scipy/scipy/blob/main/scipy/signal/_spectral_py.py
- CUDA Graph launch-overhead 口径: https://docs.nvidia.com/dl-cuda-graph/cuda-graph-basics/cuda-graph.html
- GPU overlap-save convolution: https://github.com/KAdamek/GPU_Overlap-and-save_convolution
- GPU overlap-save shared-memory FFT paper: https://arxiv.org/abs/1910.01972
- fCWT paper: https://doi.org/10.1038/s43588-021-00183-z
- GPU prefix-sum/scan: https://developer.nvidia.com/gpugems/gpugems3/part-vi-gpu-computing/chapter-39-parallel-prefix-sum-scan-cuda
- CUDA Graph performance thesis: https://www.diva-portal.org/smash/get/diva2%3A1779194/FULLTEXT01.pdf
- GPU CA-CFAR paper: https://www.researchgate.net/publication/229034537_Implementation_of_the_CA-CFAR_algorithm_for_pulsed-Doppler_radar_on_a_GPU_architecture
- GPU radar signal processing thesis: https://www.utupub.fi/bitstream/handle/10024/178763/Kimi_Zaknoun_Real-Time_GPU-accelerated_Processing_of_Digital_Radar_Signal_Data.pdf
- GPU MVDR reference: https://espace.rmc.ca/jspui/bitstream/11264/1802/1/TH%20500-%20Thesis%20Capt%20Rideout.pdf
- Parallel FFT performance reference: https://www.netlib.org/utk/people/JackDongarra/PAPERS/Performance_Analysis-fft-ipdps22.pdf

参考论文：

1. Karel Adamek, Sofia Dimoudi, Mike Giles, Wesley Armour. GPU Fast Convolution via the Overlap-and-Save Method in Shared Memory. arXiv:1910.01972, 2019. https://arxiv.org/abs/1910.01972
2. Lukas P. A. Arts, Egon L. van den Broek. The fast continuous wavelet transformation (fCWT) for real-time, high-quality, noise-resistant time-frequency analysis. Nature Computational Science, 2(1):47-58, 2022. https://doi.org/10.1038/s43588-021-00183-z
3. Yun Wang, Ping He. Comparisons between fast algorithms for the continuous wavelet transform and applications in cosmology: the 1D case. arXiv:2302.03909, 2023. https://arxiv.org/abs/2302.03909
4. Mark Harris, Shubhabrata Sengupta, John D. Owens. Parallel Prefix Sum (Scan) with CUDA. GPU Gems 3, Chapter 39, 2007. https://developer.nvidia.com/gpugems/gpugems3/part-vi-gpu-computing/chapter-39-parallel-prefix-sum-scan-cuda
5. Implementation of the CA-CFAR algorithm for pulsed-Doppler radar on a GPU architecture. https://www.researchgate.net/publication/229034537_Implementation_of_the_CA-CFAR_algorithm_for_pulsed-Doppler_radar_on_a_GPU_architecture
6. Kimi Zaknoun. Real-Time, GPU-accelerated Processing of Digital Radar Signal Data. Master thesis, University of Turku, 2024. https://www.utupub.fi/bitstream/handle/10024/178763/Kimi_Zaknoun_Real-Time_GPU-accelerated_Processing_of_Digital_Radar_Signal_Data.pdf
7. GPU Parallelization of the MVDR Beamforming. https://espace.rmc.ca/jspui/bitstream/11264/1802/1/TH%20500-%20Thesis%20Capt%20Rideout.pdf
8. Performance Analysis of Parallel FFT on Large Multi-GPU Systems. IPDPS, 2022. https://www.netlib.org/utk/people/JackDongarra/PAPERS/Performance_Analysis-fft-ipdps22.pdf
9. Evaluating the performance of CUDA Graphs in common GPGPU algorithms. https://www.diva-portal.org/smash/get/diva2%3A1779194/FULLTEXT01.pdf

## 实测约束与性能预算

- 当前可用 L6 日志来自旧部署，只能确定热点，不能证明 V6-0008 至 V6-0011 的收益。
- Task2 L6 旧部署为 `77.302 ms`：`cwt=34.408 ms`、`spectrogram=26.363 ms`、`correlate=9.749 ms`，前三项占 91.2%。总耗时下降 45%-65% 要求前三项合计约下降 49%-71%。
- Task1 L6 旧部署为 `7.463 ms`：`pulse_compression=3.466 ms`、`pulse_doppler=1.631 ms`、`ca_cfar=1.008 ms`，前三项占 81.8%。总耗时下降 35%-50% 要求前三项合计约下降 43%-61%。
- V5.5 最终任务报告只覆盖 scale 3，不能作为 V6 L6 百分比基线。V6.1 必须重建当前源码、同配置的绝对基线。

## 强化目标

| 指标 | V6 目标 |
|---|---|
| Task1 L6 GPU total | 相比 V6.1 同源码基线下降 35%-50%；建议 stage 目标为 pulse compression >=50%、pulse Doppler >=35%、CFAR >=35% |
| Task2 L6 GPU total | 相比 V6.1 同源码基线下降 45%-65% |
| Task2 L5/L6 `cwt + spectrogram + correlate` | 三项合计下降 50%-70%；建议 stage 目标为 CWT >=60%、spectrogram >=60%、correlate >=40% |
| Task1 L5/L6 `pulse_compression + pulse_doppler + ca_cfar` | 三项合计至少下降 43%；`ambgfun` 任务路径和公共 full surface 分开统计 |
| 任务步骤 | 14/14 独立计时、14/14 独立精度、failure_count=0 |
| all81 correctness | 81/81 passed |
| dtype 覆盖 | `operator_dtype_missing_edges=0` |
| 报告目录 | `data/reports/` 仍只保留终测汇总；日志和中间 probe 放仓库外 |

目标不是硬放宽阈值，而是用分解报告证明确实减少了 kernel launch、global memory traffic、FFT plan 重建、host/device copy 或无用中间矩阵落地。

百分比是挑战目标，不是 correctness 门禁。未达到目标时必须保留同规模绝对耗时和瓶颈分解，不能换用不同 scale、repeat 或旧版本分母。

## P0：内部执行基础设施

| 工作项 | 优化措施 | 验证要求 |
|---|---|---|
| execution context | 统一任务级 stream、event、workspace 和计时策略；任务层计时时允许关闭公共算子嵌套同步 | 14 步字段保留；另有 pipeline wall time；stage sum 与 wall 差异可解释 |
| FFT plan/cache | 按 transform type、nfft、batch、layout、stream 建立有界多键 cache；记录 create/hit/miss | Task1 不再在 batch=1、num_pulses、samples 间反复重建 plan |
| allocation/cache | 将任务热点中的模块私有 `DeviceBuffer` 接入统一 workspace；记录 allocation、bytes 和高水位 | 不增加长期显存；cold/warm 分开报告 |
| 并行分支 | 探测 ZQ500 concurrent kernels、非默认 stream 和 `cufftSetStream`；Task2 filter 后四分支按依赖并行 | 每分支用 stream event 独立计时；不支持时明确转为串行/fusion |
| 内部 timing | 复用 event，避免每个公共算子调用创建/销毁两个 event | 单算子 kernel timing 不丢；小算子 E2E 固定开销下降 |

## P0：Task1 深度优化（V6.4，Task2 后执行）

| 工作项 | 优化措施 | 验证要求 |
|---|---|---|
| Task1 task graph / pipeline plan | 固定 L1-L6 输入规模，预分配 pulse、doppler、power、CFAR、ambgfun workspace；避免每步重复 malloc/free 和 host sync | 每步 timing 不丢；GPU total 与各 stage sum 可解释 |
| `pulse_compression` | 分离 template/pulse/Doppler plan；template FFT、norm 和 window key 缓存并 device resident；pulse FFT、乘模板、IFFT 候选融合 | `pulse_compression` error 不回退；L5/L6 分解显示 plan create 和模板准备下降 |
| `pulse_doppler` | Doppler FFT 后 `fftshift + power_map` 融合；按行/列 coalesced 写回；保留公共算子接口 | `pulse_doppler_fftshift` 和 `power_map` 仍独立报告，融合算子内部拆 event |
| `ca_cfar` / `detect_peak` | 积分图或行列前缀和 CFAR；阈值、mask、peak selection device resident；最终只回传少量标量 | CFAR 阈值误差和 peak 一致性通过 |
| `ambgfun` | 任务内耗时与公共 full surface 分开；先复用已上传模板，再评估 batched FFT/extract/zero-fill 和 metrics 路径 | 不改变现有 `ambgfun` API；任务路径若改用 metrics，必须保留 representative surface 校验 |
| `mvdr` | 归入公共 P1；先拆 handle/alloc/copy/sync，再评估 covariance 和 small Hermitian solve | `mvdr` 独立测试通过；不得抢占 Task1 P0 资源 |

## P0：Task2 深度优化（V6.2-V6.3，先执行）

| 工作项 | 优化措施 | 验证要求 |
|---|---|---|
| Task2 task graph / pipeline plan | filter 后 `demod/correlate/spectrogram/cwt` 按依赖并行；统一 stream/event/workspace，中间结果 device resident | 8 个计算步骤仍独立计时/精度；另记 pipeline wall time |
| `filter` | L5/L6 评估 FIR direct shared tile vs dlFFT/overlap-save/shared-memory overlap-save；tap FFT/window cache；filter 输出实部投影和 demod 输入融合 | filtered error 通过；filter L6 明显下降 |
| `demod` | 相位差、unwrap、score 合并；多 frame 一次 kernel；减少小 kernel 和临时数组 | demod error 通过；低 scale 不因 fusion 退化 |
| `correlate` | 长模板采用 FFT/overlap-save 候选；短模板走 direct tile；相关输出 magnitude、argmax、normalize 融合为公共 `correlate_score` | correlate score 与原报告一致 |
| `spectrogram` | 全 frame segment pack + window multiply + batched R2C plan/cache；band score reduce，并从同一结果抽代表帧 | spectrogram step error 通过；L5/L6 spectrogram 目标至少下降 60% |
| `cwt` | wavelet table cache；先做 shared halo tile，再比较 FFT/fCWT、downsampled wavelet 和 score-only reduce；默认不落完整矩阵 | cwt step error 通过；L5/L6 cwt 目标至少下降 60% |
| `feature_fusion_peak` | smoothing、weighted sum、argrelmax 和 top-k candidate 合并为公共 fused operator | feature score 与 peak 输出一致 |
| `measurement_conversion` / `kalman` | 仅做 alias、冗余清零、allocation 和小矩阵固定开销清理 | 两步仍有独立误差；因 L6 占比低，不作为深度优化主线 |

## P1：任务相关算子深度优化

| 模块 | 算子 | V6 深化重点 |
|---|---|---|
| `radartools` | `ambgfun`, `pulse_compression`, `pulse_doppler`, `ca_cfar`, `mvdr` | FFT/workspace reuse、device-resident metrics、small matrix shared solve、前缀和/SAT/naive 三路 CFAR |
| `spectral` | `spectrogram`, `stft`, `periodogram`, `welch`, `csd`, `coherence`, `lombscargle` | 统一 STFT core、R2C、segment/window cache、reduce fusion、fast trig 二次校验 |
| `filtering` | `firfilter`, `upfirdn`, `resample_poly`, `decimate`, `hilbert`, `lfilter`, `filtfilt` | overlap-save FIR、polyphase shared tile、FFT Hilbert、SOS prefix scan 扩形 |
| `wavelets` | `cwt`, `morlet`, `morlet2`, `ricker` | wavelet table cache、fCWT 式尺度分离、CWT score fusion、常量预计算延续 |
| `correlate` | `correlate`, `correlate2d` | direct/FFT auto threshold、task score fusion |
| `estimation` | `kalman_filter` | batched small-state GPU path、measurement fusion |

## P2：赛题算子库轻度优化

只处理低风险、明确收益项：

- 消除 GPU 端 double 字面量和隐式 double 运算。
- 消除多余 host/device copy。
- 复用公共 workspace/cache。
- 对窗口、波形、滤波设计、谱估计和小矩阵路径补 fast path。
- 小数组路径能 fusion 就 fusion；不能 fusion 且 GPU 必跑时，需要给出 launch overhead 解释。

## 工作包

| 工作包 | 内容 | 关闭条件 |
|---|---|---|
| V6.1（原 V6.0-01/02） | 当前源码 correctness、Task1/Task2 L1-L6 冷/暖基线、编译/runtime/stream/FFT 探针 | Task2 L3/L5/L6 先通过；两任务 repeat=3；源码 SHA、退出码和热点分解完整 |
| V6.2 | Task2 第一批：按 `cwt -> spectrogram -> correlate` 做算法级替换 | Task2 L6 至少下降 30%，8 步精度通过 |
| V6.3 | Task2 第二批：execution plan、多 stream、filter 和低风险融合 | Task2 L6 累计下降 45%-65% |
| V6.4 | Task1 第一批：multi-key FFT plan、模板缓存、Doppler/power/CFAR | Task1 L6 至少下降 20% |
| V6.5 | Task1 收口；公共 `ambgfun/mvdr` 约束和开销分解 | Task1 累计下降 35%-50%；公共算子单列结果 |
| V6.6 | 内部执行基础设施推广和任务相关 P1 算子 | event/plan/allocation/copy 统计下降，模块 full 与任务 smoke 通过 |
| V6.7 | 赛题算子库 P2 低风险轻度优化 | 单算子 full 和受影响模块 full 通过；有独立 E2E 收益 |
| V6.8 | 当前源码全量回归与报告收束 | all81 81/81、dtype 缺口 0、任务 L1-L6 通过、`data/reports` 仍精简 |

## 测量协议与止损

- 每个候选固定源码 SHA、dirty diff、编译 flags、shape、seed 和输入；同一容器内做 A/B。
- cold=1 单列，warmup>=2、repeat>=5，报告 median/p95；阶段开发先 repeat=3，收口才 repeat=5。
- 记录 stage wall、kernel event、launch 数、copy bytes、allocation、plan create/hit/miss、GPU/RSS 高水位。
- correctness 未通过时不登记收益。单 stage 收益低于 5%且任务总计低于 2%，连续三轮后停止；复杂度明显增加而总收益低于 3%时回退。
- L1/L2 退化超过 10%时增加 shape threshold；不为统一实现牺牲小规模。
- CUDA Graph 在稳定 stream/workspace/plan 后只做一次支持探针，不作为关键路径。

## 验证阶梯

1. 静态构建：改动模块对应 target 必须通过。
2. 单算子 CTest：改动算子对应独立测试必须通过。
3. 单任务 L3：先验证功能、schema、精度。
4. 任务 L1-L6 repeat=3：验证所有规模稳定，并分开 cold/warm/setup/pipeline wall。
5. 任务 L1-L6 repeat=5：进入阶段收口才使用。
6. all81 benchmark：阶段收口必须 81/81 passed。
7. full 回归：最终交付前跑全库 full、接口审计、类型契约和 dtype 覆盖。

## 台账规则

- V6 所有发现、候选、回退和保留优化写入 `docs/performance/v6_0/optimization_change_log.md`。
- 每条记录必须写清来源措施、是否满足赛题约束、实际改动、任务影响、单算子影响和验证命令。
- 候选失败也要记录，避免重复尝试。
- 中间报告和日志放 `/home/usr_04/CETC_garbage/`，正式报告只保留终测汇总。
- 日志必须捕获 stdout/stderr、真实退出码、源码 fingerprint 和编译信息；源码不一致的日志只能作为历史证据。
