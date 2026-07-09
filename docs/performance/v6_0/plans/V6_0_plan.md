# V6.0 任务优先深度性能优化规划

## 定位

第六版从 V5 的迁移验收中独立出来，只做性能深化。优化优先级按赛题价值排序：

1. Task1/Task2 端到端 GPU 性能。
2. 两个任务直接相关算子。
3. 赛题明确提到的算子库热点。
4. 原 cuSignal 有、但赛题未提到且不影响任务链路的算子，暂不继续优化。

V6 允许更激进的数据流重排、workspace 复用、kernel fusion、FFT plan/cache 复用和任务级公共 fused operator，但必须保持 V5.5 的接口、类型、精度、步骤报告和平台兼容要求。

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

## 强化目标

| 指标 | V6 目标 |
|---|---|
| Task1 L6 GPU total | 相比 V5.5 终测下降 35%-50%；若受 full ambgfun surface 输出规模限制，必须给出 bytes/FFT/launch 分解证据 |
| Task2 L6 GPU total | 相比 V5.5 终测下降 45%-65% |
| Task2 L5/L6 `spectrogram + cwt + correlate` | 三项合计至少下降 50%，作为 Task2 主目标 |
| Task1 L5/L6 `ambgfun + pulse_doppler + ca_cfar` | 三项合计至少下降 35%，作为 Task1 主目标 |
| 任务步骤 | 14/14 独立计时、14/14 独立精度、failure_count=0 |
| all81 correctness | 81/81 passed |
| dtype 覆盖 | `operator_dtype_missing_edges=0` |
| 报告目录 | `data/reports/` 仍只保留终测汇总；日志和中间 probe 放仓库外 |

目标不是硬放宽阈值，而是用分解报告证明确实减少了 kernel launch、global memory traffic、FFT plan 重建、host/device copy 或无用中间矩阵落地。

## P0：Task1 深度优化

| 工作项 | 优化措施 | 验证要求 |
|---|---|---|
| Task1 task graph / pipeline plan | 固定 L1-L6 输入规模，预分配 pulse、doppler、power、CFAR、ambgfun workspace；避免每步重复 malloc/free 和 host sync | 每步 timing 不丢；GPU total 与各 stage sum 可解释 |
| `pulse_compression` | template FFT 频谱预计算并 device resident；pulse FFT、乘模板、IFFT 和 magnitude 候选融合；复用 FFT plan/workspace | `pulse_compression` error 不回退；L5/L6 分解显示 plan/copy 开销下降 |
| `pulse_doppler` | Doppler FFT 后 `fftshift + power_map` 融合；按行/列 coalesced 写回；保留公共算子接口 | `pulse_doppler_fftshift` 和 `power_map` 仍独立报告，融合算子内部拆 event |
| `ca_cfar` / `detect_peak` | 积分图或行列前缀和 CFAR；阈值、mask、peak selection device resident；最终只回传少量标量 | CFAR 阈值误差和 peak 一致性通过 |
| `ambgfun` | 第二轮算法级改写：评估 full surface 是否必须全量落地；若必须落地，优化 batched FFT/extract/zero-fill；若任务只消费 peak/ROI，新增公共 `ambgfun_metrics`，full `ambgfun` 保持独立算子语义 | 不改变现有 `ambgfun` API；任务路径若改用 metrics，必须保留 representative surface 校验 |
| `mvdr` | covariance 构造、diagonal loading、small Hermitian solve 合并；避免显式 inverse；小矩阵放 shared/register | `mvdr` 独立测试通过；若任务链路不直接使用，仍作为 radartools 深化项保留 |

## P0：Task2 深度优化

| 工作项 | 优化措施 | 验证要求 |
|---|---|---|
| Task2 task graph / pipeline plan | `filter -> demod -> correlate -> spectrogram -> cwt -> fusion -> measurement -> kalman` 使用统一 workspace；中间结果默认 device resident | 8 个计算步骤仍独立计时/精度 |
| `filter` | L5/L6 评估 FIR direct shared tile vs dlFFT/overlap-save/shared-memory overlap-save；tap FFT/window cache；filter 输出实部投影和 demod 输入融合 | filtered error 通过；filter L6 明显下降 |
| `demod` | 相位差、unwrap、score 合并；多 frame 一次 kernel；减少小 kernel 和临时数组 | demod error 通过；低 scale 不因 fusion 退化 |
| `correlate` | 长模板采用 FFT/overlap-save 候选；短模板走 direct tile；相关输出 magnitude、argmax、normalize 融合为公共 `correlate_score` | correlate score 与原报告一致 |
| `spectrogram` | segment pack + window multiply + R2C plan/cache；band score 直接 reduce，完整谱图只用于代表帧/报告 | spectrogram step error 通过；L5/L6 spectrogram 至少下降 40% |
| `cwt` | 多尺度 wavelet table cache；引入 fCWT 式 scale-independent/scale-dependent 分离、downsampled wavelet 和 FFT 复用；convolution + abs + scale reduction + normalize 融合；默认不落完整 `widths x samples` 矩阵 | cwt step error 通过；L5/L6 cwt 至少下降 50% |
| `feature_fusion_peak` | smoothing、weighted sum、argrelmax 和 top-k candidate 合并为公共 fused operator | feature score 与 peak 输出一致 |
| `measurement_conversion` / `kalman` | measurement prepare、Kalman update、track RMSE 统计合并；小矩阵状态放寄存器/共享内存 | measurement 和 Kalman 两步仍有独立误差 |

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
| V6.0-01 | 建立 Task1/Task2 L1-L6 repeat=5 基线，输出 stage breakdown、copy/alloc/cache/FFT plan 统计 | 两任务 14 步全部 pass；热点排序和 V5.5 对比明确 |
| V6.0-02 | 开源/论文措施适配探针：CUDA Graph、workspace plan、FFT overlap-save、shared-memory overlap-save、direct/FFT auto threshold、prefix-sum/SAT CFAR、fCWT downsampled wavelet | 每项给出 supported/unsupported/limited 结论和最小 probe |
| V6.0-03 | Task2 第一批：`spectrogram + cwt + correlate` 融合和 score-only 公共算子；优先验证 fCWT/overlap-save 两类论文策略 | Task2 L6 GPU total 下降至少 30%，8 步精度通过 |
| V6.0-04 | Task2 第二批：filter/demod/fusion/kalman 小步骤合并 | Task2 L6 GPU total 累计下降 45%-65% |
| V6.0-05 | Task1 第一批：pulse/doppler/power/CFAR device-resident 链路 | Task1 L6 GPU total 下降至少 20% |
| V6.0-06 | Task1 第二批：`ambgfun` 算法级评估与可行改写 | 若 full surface 必须保留，给出瓶颈分解；若 metrics 可替代，新增公共 metrics 算子并保留代表面校验 |
| V6.0-07 | P1/P2 算子库批次优化 | 单算子 full、模块 full、任务 smoke 均通过 |
| V6.0-08 | 全量回归与报告收束 | all81 81/81、dtype 缺口 0、任务 L1-L6 通过、`data/reports` 仍精简 |

## 验证阶梯

1. 静态构建：改动模块对应 target 必须通过。
2. 单算子 CTest：改动算子对应独立测试必须通过。
3. 单任务 L3：先验证功能、schema、精度。
4. 任务 L1-L6 repeat=3：验证所有规模稳定。
5. 任务 L1-L6 repeat=5：进入阶段收口才使用。
6. all81 benchmark：阶段收口必须 81/81 passed。
7. full 回归：最终交付前跑全库 full、接口审计、类型契约和 dtype 覆盖。

## 台账规则

- V6 所有发现、候选、回退和保留优化写入 `docs/performance/v6_0/optimization_change_log.md`。
- 每条记录必须写清来源措施、是否满足赛题约束、实际改动、任务影响、单算子影响和验证命令。
- 候选失败也要记录，避免重复尝试。
- 中间报告和日志放 `/home/usr_04/CETC_garbage/`，正式报告只保留终测汇总。
