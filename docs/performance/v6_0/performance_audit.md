# V6 全项目性能审计

## 结论

V6 当前不缺少候选算法，缺少的是同源码基线、统一执行上下文和按 Amdahl 定律排序的关闭标准。最高收益路线应固定为：

1. 先关闭 Task2 `demod_mixed_error`，建立当前源码的 L1-L6 冷/暖基线。
2. Task2 先改 `cwt` 和 `spectrogram` 的算法复杂度，再改 `correlate/filter`，之后探测多 stream 并发。
3. Task1 先消除 FFT plan 抖动和模板重复 FFT，再优化 Doppler/CFAR；任务内 `ambgfun` 不是首要热点。
4. 抽取内部计时、FFT plan/cache 和 workspace 执行上下文，消除全库重复事件创建、同步和模块私有 allocation。
5. 最后处理公共 `ambgfun/mvdr` 和赛题算子库轻度优化，不让非任务热点抢占 P0 资源。

不建议全局启用 fast-math。当前主要损耗来自算法复杂度、串行调度、plan 重建和同步，放宽数学语义不能解决主瓶颈，反而会扩大 Task2 demod 和频谱精度风险。

## 审计证据

- V5.5 最终交付摘要归档：`/home/usr_04/CETC_garbage/manual_20260707235136/CETC_removed_20260627/reports/CETC-reports-pre-clean-20260627/zhongkexin/v5_5_final/summary.json`。
- V6 旧部署 L1-L6 日志：`/home/usr_04/CETC_garbage/cetc_v6_0202_kalman_alias_20260710_025605/`。
- V6-0021 初版验证：`/home/usr_04/CETC_garbage/cetc_v6_0208_pull_20260711/`；demod full 与 Task2 L1-L6 通过，all81 为 `80/81`。
- V6-0208R 当前源码门禁：`/home/usr_04/CETC_garbage/cetc_v6_0208r_pull_20260711/`；Task2 L1-L6、all81 `81/81`、dtype 缺口 0、14 步审计全部通过。
- V6-0026 CWT shared-halo：`/home/usr_04/CETC_garbage/cetc_v6_0210_pull_20260711/`；L6 CWT 下降 55.1%，Task2 total 下降 24.2%，全门禁通过。
- 当前源码：`src/zhongkexin/`、`include/cusignal/`、`demo/task1_radar/`、`demo/task2_features/`。
- V5.5 已知门禁为 all81 通过、dtype 缺口 0；V6-0208R 已完成等价算子全量回归，Task1 当前源码任务 L1-L6 仍待 V6.1 基线补齐。

旧部署日志不包含 V6-0008 至 V6-0011，因此只作为热点和 correctness 阻塞证据，不作为当前源码收益证据。

## 当前门禁

| 项目 | 当前结论 | 处理 |
|---|---|---|
| Task2 correctness | V6-0208R L1-L6 repeat=3 全部通过，L6 `demod_mixed_error=2.45506e-4` | 已关闭；后续每个性能候选继续保留 L3 -> L5/L6 -> L1-L6 门禁 |
| Task1 correctness | 旧部署 L1-L6 通过 | 当前源码仍需 repeat=3 回归 |
| all81 / dtype | V6-0208R 已通过 `81/81`，dtype 缺口 0，14 步 timing/accuracy 缺口 0 | 每个候选阶段回归，V6.8 最终重跑 |
| 基线可比性 | Task2 已有 V6-0208R 当前源码 L1-L6 repeat=3；V5.5 L3 不能作为 L6 分母 | V6-0026 起只与 V6-0208R 同配置比较；Task1 另补当前源码基线 |
| 报告捕获 | 旧命令只捕获 stdout，遗漏 stderr 和真实退出码 | 后续统一 `2>&1`、`PIPESTATUS[0]`、状态清单 |
| 源码部署 | 已发生容器源码落后宿主的情况 | 每个日志包记录 commit、dirty diff、目标文件 SHA256 和编译命令 |

## 实测热点

### Task2 L6

V6-0208R 优化前基线为 `76.0695 ms`；V6-0026 当前源码 L6 repeat=5 为 `57.6454 ms`：

| 步骤 | 耗时 ms | 占比 | 结论 |
|---|---:|---:|---|
| `spectrogram` | 25.4713 | 44.2% | 第一热点；82 个频点的 large kernel 处理约 8766 万项，每项对实部和虚部各做一次 shared `atomicAdd` |
| `cwt` | 15.2658 | 26.5% | shared-halo 已下降 55.1%；暂不以更复杂算法抢占 spectrogram 主线 |
| `correlate` | 9.7932 | 17.0% | 公共 `method="fft"` 仍走 direct；任务阈值在 L5 才切换 tiled direct |
| `filter` | 6.2060 | 10.8% | 257 taps 时重复读取输入；后续 shared halo/overlap-save |
| 其余四步 | 0.9091 | 1.6% | demod/fusion/measurement/kalman 不应先做深度优化 |

V6-0026 已把 CWT 占比从 44.7% 降到 26.5%，当前 spectrogram/CWT/correlate 三项仍占 87.7%。V6-0028 的无原子逐频点 direct DFT 在 L5/L6 分别退化 126.36%/106.63%，已回退；V6-0031 转测公共 batched C2C FFT。ZQ500 既有 R2C 路径有数值偏差记录，不能未经 Task 精度验证直接启用。

### Task1 L6

旧部署 repeat=5，总计 `7.463 ms`：

| 步骤 | 耗时 ms | 占比 | 结论 |
|---|---:|---:|---|
| `pulse_compression` | 3.466 | 46.4% | 单槽 plan 在 batch=1 与 batch=num_pulses 间重建；模板每次重新 pack/norm/FFT |
| `pulse_doppler` | 1.631 | 21.8% | 与 pulse compression 共用单槽 plan；转置、FFT、shift/power 有融合空间 |
| `ca_cfar` | 1.008 | 13.5% | 需按窗口和 shape 实测 direct/sliding/SAT，不预设算法 |
| `ambgfun` | 0.926 | 12.4% | 任务内不是第一热点；公共 all81 的 full surface 才是大热点 |
| `power + detection` | 0.431 | 5.8% | 只做低风险融合和 device-resident 收口 |

前三项占 81.8%。若只改前三项，Task1 总耗时下降 35% 和 50% 分别要求其合计下降约 43% 和 61%。

## 代码级发现

| 优先级 | 发现 | 影响 | 指导意见 |
|---|---|---|---|
| P0 | `radartools.cu` 的 `PulseWorkspace` 只有一个 `GenericPlan`，连续用于 `(nfft,1)`、`(nfft,num_pulses)` 和 `(doppler_nfft,samples)` | 每次任务可反复 destroy/create plan | 建立按 transform type、nfft、batch、layout、stream 键控的有界 plan cache；模板频谱和 norm 同键缓存 |
| P0 | Task2 的 demod/correlate/spectrogram/cwt 在 filter 后互相独立，但当前逐步 `cudaDeviceSynchronize` 串行执行 | 无法重叠计算，stage 固定开销累加 | 先做 `concurrentKernels` 和 stream/cufft probe；支持时用每分支 stream event 保留分步计时，并另记 pipeline wall time |
| P0 | Task2 spectrogram 对每个 segment/bin/sample 直接累加，CWT 对每个 sample/width/kernel 直接卷积 | L6 算法量主导 | spectrogram 改全帧 batched R2C + band reduce；CWT 先 shared halo，再比较 FFT/fCWT score-only |
| P0 | 公共 `correlate` 只用 `method` 限制 direct 的维度，实际 `direct/fft/auto` 都启动 ND direct kernel | 接口名与算法行为不一致，长相关无法获得 FFT 收益 | 建立共享 convolution engine 和 shape 阈值表；公共 API 语义不变 |
| P0 | 多个 GPU 模块各自定义 `ScopedZxGpuEvents`，每次公共调用创建两个 event 并同步 stop | 小算子 E2E 被 event create/destroy/sync 主导，阻断多 stream | 建立内部 `ExecutionContext/Timer`；复用 event，允许任务层禁用嵌套同步 |
| P1 | `DeviceBuffer`、`GenericPlan`、workspace 在多个大 `.cu` 文件重复实现，部分绕开 `DeviceStorageCache` | allocation/cache 策略分裂，难以统计高水位 | 只抽取内部模块，不改变 V5.5 公共类型；先服务 Task，再推广到 P1 |
| P1 | `pulse_compression` 为归一化调用 beamformer handle 初始化，连带创建 cuBLAS/cuSOLVER；模板 H2D/FFT 重复 | 冷启动和固定开销偏高 | 拆出 pulse 专用 norm 路径；缓存 device template、norm 和频谱，不初始化无关 solver |
| P1 | Task2 的 widths、taps、template 和 B-spline 权重上传发生在 stage 计时外，验证代表帧又重复调用公共算子 | 当前 `GPU total` 不是完整冷启动 E2E，stage sum 也未覆盖验证成本 | 保留旧 schema，同时新增 setup、pipeline wall、validation、cold/warm 和显存高水位字段 |
| P1 | V5.5 all81 中 `mvdr` E2E 11.148 ms、kernel 0.841 ms | 92.5% 在 kernel 外 | 先拆 handle/alloc/copy/sync，再决定是否改 small-matrix kernel；归入公共 P1，不抢 Task1 P0 |
| P2 | CMake 指定 Release，但项目显式 GPU flags 未展示优化级别 | 无法证明 dlcc 实际收到 `-O3/-DNDEBUG` | V6.1 保存 verbose compile 和 cache；确认后再评估局部编译选项 |

## 优化后的版本路线

| 版本 | 主目标 | 量化关闭条件 |
|---|---|---|
| V6.1 | correctness、同源码基线、编译/runtime/stream/FFT 探针 | Task2 L3/L5/L6 先通过；Task1/2 L1-L6 repeat=3；冷/暖、SHA、退出码和高水位完整 |
| V6.2 | Task2 `cwt -> spectrogram -> correlate` | 建议阶段目标：CWT >=60%、spectrogram >=60%、correlate >=40%；Task2 总计至少下降 30% |
| V6.3 | Task2 execution plan、并行分支、filter 和轻量融合 | 在 V6.2 基础上 Task2 总计累计下降 45%-65%；measurement/kalman 只做零风险固定成本清理 |
| V6.4 | Task1 multi-key FFT plan、模板缓存、Doppler/CFAR | pulse compression >=50%、pulse Doppler >=35%、CFAR >=35%；Task1 总计至少下降 20% |
| V6.5 | Task1 收口与公共 `ambgfun/mvdr` 约束审计 | Task1 累计下降 35%-50%；公共热点单列，不用其结果替代任务收益 |
| V6.6 | 内部执行基础设施和任务相关 P1 算子 | event/plan/allocation/copy 计数下降；受影响模块 full 与两个任务 smoke 通过 |
| V6.7 | 赛题算子库低风险优化 | 每项有独立 E2E 收益且不增加 dtype 缺口 |
| V6.8 | 当前源码全量终测 | all81 81/81、dtype 缺口 0、14 步完整、L1-L6 repeat=5、报告目录干净 |

阶段百分比是挑战目标，不是 correctness 放宽条件。最终收益只与 V6.1 同源码基线或同一容器内的 A/B 基线比较，不再直接用 V5.5 L3 任务报告推算 L6。

## 测量与止损

- 每个候选固定同 shape、seed、编译参数和源码 SHA；先 cold=1，再 warmup>=2、repeat>=5，报告 median/p95，不用单次最小值。
- 同一日志包记录 stage wall、kernel event、launch 数、H2D/D2H/D2D bytes、allocation、plan create/hit/miss 和 GPU/RSS 高水位。
- correctness 不通过时只记录耗时原始值，不记录“收益”。
- 单 stage 收益低于 5%且任务总计低于 2%，连续三轮稳定复现后停止该候选；复杂度明显增加而总收益低于 3%时回退。
- 新算法必须先覆盖 L3 correctness，再跑 L5/L6；小规模 L1-L2 退化超过 10%时增加 auto threshold，不强行统一路径。
- CUDA Graph 仅在稳定 stream、workspace 和 plan 之后做一次支持探针；不作为 V6 关键路径。
