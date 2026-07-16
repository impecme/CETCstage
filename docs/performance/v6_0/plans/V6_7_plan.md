# V6.7 赛题算子库轻度优化计划

## 状态与目标

- 状态：已关闭；V6-0134 增采样确认在原门限下通过，V6-0135 已完成剩余热点处置审计和阶段收束。
- 目标：对赛题明确提到但不在任务热点链路中的算子做低风险轻度优化。
- 排序依据：V6.1 all81 的 GPU E2E、kernel 外占比、任务复用价值和改动风险；不能仅按 CPU/GPU speedup 排名。
- 阶段交付：`docs/submission/READMEV6_7.md`；按候选同步记录基线、门禁、回退和仓库外证据。

## 工作包

| ID | 工作包 | 允许措施 | 关闭条件 |
| --- | --- | --- | --- |
| V6.7-01 | double 字面量清理 | GPU 端 float 常量、避免隐式 double | 单算子 full 通过，无精度退化 |
| V6.7-02 | copy 清理 | 消除多余 H2D/D2H 和 D2D | cache/copy 指标下降或解释保留 |
| V6.7-03 | runtime/cache 推广 | 复用 V6.6 event、FFT plan 和 workspace 基础设施 | allocation、plan create、event 或峰值下降 |
| V6.7-04 | 小数组 fast path | host scalar、预计算、fusion 或固定配置 | 小规模 E2E 固定开销下降，GPU 必跑约束不破坏 |
| V6.7-05 | build/math 审计 | 确认 Release flags；只做局部安全的 float 运算替换 | verbose compile 有证据，精度不退化 |
| V6.7-06 | 暂缓列表 | 非赛题、非任务、低收益项 | 不再重复深挖 |

## 执行规则

- 只做低风险、容易验证的改动。
- 不重写原 cuSignal 全库非任务算子。
- 禁止全局 fast-math；每个数学替换必须有算子精度和 Task smoke 证据。
- 单算子 E2E 收益低于 5%且绝对节省低于 0.05 ms 时默认暂缓，除非它在任务中高频调用。
- 任一改动必须通过单算子 full；跨模块 helper 需跑受影响模块 full。
- correctness、dtype、API、类型和报告 schema 为硬门禁，不允许降低。对高噪声辅助性能指标最多允许在 `repeat>=100` 且中位数稳定时把批次稳定要求由 `4/5` 调整为 `3/5`，但目标 E2E 有效线和中位数不退化门不变；V6.7 最终确认未使用该例外。

## 当前排序与候选

- V6-0098 all81 中 P2 kernel 热点：`windows/kaiser=9.96352 ms`、`taylor=7.59305 ms`、`general_cosine=5.63924 ms`、`waveforms/gausspulse=5.35564 ms`。
- 先做 `taylor`：固定系数路径的 perf 用例每点重复 4 次 `cosf`，可在不改公式和 API 的前提下，用一次 `cosf(angle)` 与 `cos(n x)=2cos(x)cos((n-1)x)-cos((n-2)x)` 生成最多 8 阶谐波。
- `kaiser` 不替换 Bessel I0 近似式；V6-0104 仅消除 float32 累加已停滞后的无效级数迭代。
- V6-0099 要求 Taylor 单算子 E2E 至少下降 5%，kernel 不退化；随后通过 windows full、双任务 L1 smoke、all81、dtype、步骤和 manifest。
- V6-0099 五批 Taylor E2E/kernel 中位数=`4.21346/4.12130 ms`，相对 V6-0098 下降 `45.27%/45.72%`；windows `23/23`、双任务 L1、all81 `81/81`、dtype/步骤缺口 0 和 manifest 全部通过，正式保留。
- V6-0100 将同一递推限制在 `general_cosine` 的 1 至 5 个固定系数路径；基线 E2E/kernel=`5.70083/5.61463 ms`，仍按五批算子门禁和完整回归验收。
- V6-0100 五批 general cosine E2E/kernel 中位数=`2.90603/2.81139 ms`，下降 `49.02%/49.93%`，误差上限不变；windows `23/23`、all81 `81/81` 和全部审计通过，正式保留。
- V6-0101 只在 gausspulse GPU kernel 中复用同一样本的 envelope；bundle 基线 E2E/kernel=`5.40349/5.35596 ms`，real-only 基线=`2.64759/2.60354 ms`，要求 bundle 至少下降 5%且 real-only 不退化。
- V6-0101 五批 bundle E2E 中位数=`4.46783 ms`，下降 `17.32%`；但测试侧复制 kernel 未同步产品改动，报告 kernel=`5.35673 ms` 不代表候选，出现 E2E 小于 kernel 的确定性口径矛盾。全量阶梯按门禁跳过，候选暂不回退。
- V6-0102 将 envelope 复用下沉到内部 host/device component helper，产品 kernel 和测试 kernel 共用；继续使用 V6-0100 原始 E2E/kernel 分母，只有有效 kernel 与 E2E 均通过才保留。
- V6-0102 有效五批结果：bundle E2E/kernel=`4.33832/4.28933 ms`，下降 `19.71%/19.91%`；real-only=`2.80569/2.76140 ms`，退化 `5.97%/6.06%`。数值全部通过，但 real-only 超过 3% 门禁，完整阶梯按止损跳过。
- V6-0103 将 `retquad/retenv` 编译为四个 kernel 实例，模板 helper 用 `if constexpr` 去掉无关 `sinf`、指针判断和通用寄存器路径；仍按 V6-0100 原始分母同时验收 bundle 收益与 real-only 无退化。
- V6-0103 五批 real-only E2E/kernel=`2.58396/2.52858 ms`，下降 `2.40%/2.88%`；bundle=`4.48914/4.44098 ms`，下降 `16.92%/17.08%`。waveforms、双任务 L1、all81、dtype、步骤和 manifest 全部通过，正式保留。
- V6-0104 的 `bessel_i0` 在 `next_sum == sum` 时停机；五批 Kaiser E2E/kernel=`6.65311/6.57719 ms`，相对 V6-0103 下降 `34.00%/33.85%`。windows、双任务 L1、all81、dtype、步骤和 manifest 全部通过，正式保留。
- V6-0105 将 linear chirp 的 `(f1-f0)/t1` 从每个 GPU 样本移动到宿主一次计算；real 基线 E2E/kernel=`2.73803/2.69989 ms`，complex E2E=`4.13651 ms`。旧 complex kernel 使用两个平面 float 输出，与产品 `float2` 布局不一致，不跨口径比较；候选改为一致布局后仅报告新 kernel。
- V6-0105 五批 real E2E/kernel=`2.61261/2.57477 ms`，下降 `4.58%/4.63%`；complex E2E=`3.71627 ms`，下降 `10.16%`；E2E 合计下降 `7.94%`。waveforms、双任务 L1、all81、dtype、步骤和 manifest 全部通过，正式保留。
- V6-0106 以 V6-0105 all81 morlet2 E2E/kernel=`30.5184/30.2880 ms` 为分母，仅将同一 phase 的独立 `cosf/sinf` 改为 CUDA `sincosf`；若后端未降低双三角函数成本或误差增加则立即回退。
- V6-0106 五批 E2E/kernel=`30.4297/30.3561 ms`，仅下降 `0.29%`/退化 `0.22%`，误差不变但无一批达到双项 5% 门禁，已恢复保留版。
- V6-0107 利用 Ricker 关于中心的偶对称性，在 `points <= 2^24` 时每线程计算一次并写原点和镜像点；更大 points 保留原 kernel。基线 E2E/kernel=`29.5576/29.4336 ms`，summary/perf max abs 均为 `2.98023e-8`。
- V6-0107 五批 E2E/kernel=`15.3383/15.2579 ms`，下降 `48.11%/48.16%`，误差不增；wavelets、双任务 L1、all81、dtype、步骤和 manifest 全部通过，正式保留。
- V6-0108 将同一 `points <= 2^24` 保护推广到 morlet2：中心镜像点实部相同、虚部互为相反数；非有限参数和更大 points 保留原 kernel。基线采用 V6-0107 all81 E2E/kernel=`30.4007/30.1426 ms`。
- V6-0108 五批 morlet2 E2E/kernel=`16.7873/16.6851 ms`，下降 `44.78%/44.65%`，误差不增；wavelets、双任务 L1、all81、dtype、步骤和 manifest 全部通过，正式保留。
- V6-0109 处理 Morlet E2E/kernel=`5.56884/5.48628 ms`：直接共轭复制因 linspace float32 坐标不严格对称而否决，改用右点坐标残差的一阶修正；修正量超限时逐点精确回退。五批要求 E2E/kernel 均下降至少 `20%` 且误差不高于 V6-0108。
- V6-0109 五批 E2E/kernel=`4.04347/3.97874 ms`，下降 `27.39%/27.48%`；但 max abs 从 `9.77589e-7` 增至 `9.92467e-7`，严格门禁失败，完整阶梯按止损跳过。
- V6-0110 保留三角复用方向，但镜像 Gaussian 恢复原 `expf`，只用小角旋转修正 phase 残差；相对 V6-0108 要求 E2E/kernel 至少下降 `5%` 且 max abs 不增，否则恢复 V6-0108。
- V6-0110 五批 E2E/kernel=`4.61647/4.56155 ms`，下降 `17.10%/16.86%`；max abs=`1.01152e-6`，仍高于 `9.77589e-7`，已恢复 V6-0108 SHA=`301bfb4e...`。Morlet 镜像近似方向停止。
- V6-0111 处理 general Gaussian E2E/kernel=`1.89522/1.83722 ms`：对专用 power mode 在 `effective_size-1 <= 2^24` 时每线程计算一侧并同值写镜像位置；通用幂和更大尺寸走原路径。五批要求 E2E/kernel 均下降至少 `20%`、至少四批达标且 max abs 不高于 `1.19209e-7`。
- V6-0111 五批 E2E/kernel=`1.15901/1.09192 ms`，下降 `38.85%/40.57%`，误差不增；windows、双任务 L1、all81、dtype、步骤和 manifest 全部通过，正式保留。
- V6-0112 处理 Parzen E2E/kernel=`1.47060/1.41345 ms`。宿主探针确认 Parzen 在奇偶、sym/periodic 和 `2^24` perf 尺寸全部镜像位级一致；Hamming perf 尺寸有 `3635054` 对不一致，暂不使用直接镜像复制。Parzen 五批要求 E2E/kernel 均下降至少 `5%`、至少四批达标且 max abs 不高于 `5.96046e-8`。
- V6-0112 五批 E2E/kernel=`0.850685/0.766052 ms`，下降 `42.15%/45.80%`，误差不增；windows、双任务 L1、all81、dtype、步骤和 manifest 全部通过，正式保留。
- V6-0113 处理 Hamming E2E/kernel=`2.39096/2.31683 ms`。每对先按原公式计算左点；仅当右点角度与左点角度精确互为相反数时复制左值，否则按原公式计算右点。perf 尺寸可复用 `53.05%` 镜像对，理论 `cosf` 调用减少 `26.53%`，宿主候选相对原实现位级差异 0。
- V6-0113 五批 Hamming E2E/kernel=`1.39457/1.33826 ms`，下降 `41.67%/42.24%`，误差不增；windows、双任务 L1、all81、dtype、步骤和 manifest 全部通过，正式保留。
- V6-0114 处理 sawtooth/square 每点无条件调用 `fmodf(t,2π)`：对 `|t| < 2π` 直接使用 `t`，边界与其余输入仍调用原函数。宿主探针对边界和 1000 万随机 float 位级一致；预计覆盖两算子 perf 输入的 `12.5%/10%`。四个 scalar/vector case 各自五批要求 E2E/kernel 中位数至少下降 `5%`、至少四批达标且误差不增。
- V6-0114 四个 case 数值均通过但性能全部稳定退化：sawtooth scalar/vector E2E 中位数上升 `6.94%/6.79%`，kernel 上升 `7.25%/7.32%`；square E2E 上升 `10.47%/10.40%`，kernel 上升 `10.80%/10.79%`。分支与 warp 分歧成本高于少量 `fmodf` 直通收益，已恢复 header SHA=`57506c4c...`。
- V6-0115 处理 Triang E2E/kernel=`1.09041/1.02065 ms`。原公式只依赖整数镜像距离；宿主探针检查 `45,086,714` 对，覆盖奇偶、sym/periodic、连续小尺寸和 `2^24`，全部位级一致。大尺寸每线程计算一次并向镜像位置写同值，小于 512 点保留原 kernel；五批要求双指标下降至少 `5%`且误差不增。
- V6-0115 五批 Triang E2E/kernel 中位数=`0.777635/0.723708 ms`，下降 `28.68%/29.09%`，五批全部达标且 max abs 保持 `1.19209e-7`。dlsmi 进程/全卡显存峰值=`80/373 MiB`，GPU P95/active median=`95%/77%`；windows `23/23`、双任务 L1、all81 `81/81`、dtype/14 步缺口 0 和 manifest 全部通过，正式保留。
- V6-0116 处理 QMF E2E/kernel=`1.66222/1.60264 ms`，perf case 为 16777216 点且 max abs=0。偶数且不少于 512 点时，每线程以一个 `float2` 连续载入一对反序输入，交换后写一对输出并保持原交替符号；奇数和小尺寸保留原 kernel。宿主探针检查 `11,535,361` 对和任意 float 位模式，映射位级一致；五批要求双指标下降至少 `5%`、至少四批达标且误差保持 0。
- V6-0116 五批数值均严格通过，但 E2E/kernel 中位数=`1.68053/1.62071 ms`，相对基线上升 `1.10%/1.13%`，五批收益数为 0；完整阶梯按止损跳过，manifest 不变，宿主和容器已恢复 V6-0115 wavelets SHA=`301bfb4e...`。
- V6-0117 处理 Lomb-Scargle E2E/kernel=`12.5364/12.2951 ms`，perf 规模为 `8192 samples × 16384 frequencies`。仅在双维均不少于 1024 时每 block 处理两个频率，使两组独立 sin/cos、FMA 和归约共用一次 `x/y` 载入并减半 block 数；小规模走原 kernel。宿主探针对 514 个频率保持位级一致；五批要求双指标下降至少 `5%`、至少四批达标且原误差上限不增。
- V6-0117 五批精度完全不变，E2E/kernel 中位数=`12.1251/11.8777 ms`，下降 `3.28%/3.39%`，绝对节省 `0.4113/0.4174 ms`；专用 5%门禁未通过，完整阶梯按止损跳过。该收益远高于阶段 `0.05 ms` 有效线，不回退方向，作为 V6-0118 中间基线继续优化。
- V6-0118 保留双频输入复用，只将 pair kernel 的 256 线程树归约从八级整 block barrier 改为前两级 block barrier、后六级 warp 同步；加法配对和顺序不变。相对 V6-0115 原始分母仍要求五批 E2E/kernel 下降至少 `5%`且误差不增，通过后运行完整阶梯。
- V6-0118 五批 E2E/kernel 中位数=`11.5651/11.3009 ms`，相对原始分母下降 `7.75%/8.09%`，五批全过且误差完全不变。dlsmi 进程/全卡峰值=`48/341 MiB`，GPU P95/active median=`99%/99%`；spectral `9/9`、双任务 L1、all81 `81/81`、dtype/14 步缺口 0 和 manifest 全部通过，正式保留 V6-0117/0118 组合。
- V6-0119 处理 vectorstrength E2E/kernel=`9.19509/9.09648 ms`，perf 为 1048576 events、64 periods、每 period 1024 个 partial blocks。只将 partial kernel 的 stride 32 至 1 从整 block barrier 改为首 warp 同步，Kahan 累加、加法配对/顺序和 finalize 不变；五批要求双指标下降至少 `5%`且原误差上限不增。
- V6-0119 五批 E2E/kernel 中位数=`6.91468/6.85419 ms`，下降 `24.80%/24.65%`，五批全部达标且 summary/perf max abs 保持 `4.76837e-6`。dlsmi 进程/全卡峰值=`48/341 MiB`，GPU P95/active median=`99%/99%`；spectral `9/9`、双任务 L1、all81 `81/81`、dtype/14 步缺口 0 和 manifest 全部通过，正式保留。
- V6-0120 在 vector-period 路径且 `blocks_per_period >= 256` 时，每个 block 处理相邻两个完整 period，复用一次 event 载入，并让两组独立 Kahan 累加与四路 partial 归约共用同步；奇数尾 period、scalar 和小规模路径保留原 kernel。各 period 的 sample 顺序、角度/多项式、Kahan、加法树、partial 布局和 finalize 不变。
- V6-0120 以 V6-0119 E2E/kernel=`6.91468/6.85419 ms` 为分母；强门禁为双指标至少下降 `5%`且至少四批达标。为保留稳定有效收益，另允许双指标至少下降 `2%`、绝对各省至少 `0.1 ms`且至少四批均改善；两档都必须误差不增并完成完整回归。
- V6-0120 五批 E2E/kernel 中位数=`6.30728/6.22170 ms`，下降 `8.78%/9.23%`，五批均达到强门禁且 max abs/RMSE 保持 `4.76837e-6/1.45348e-6`。dlsmi 进程/全卡峰值=`48/341 MiB`，GPU P95/active median=`99%/99%`；spectral `9/9`、双任务 L1、all81 `81/81`、dtype/14 步缺口 0 和 manifest 全部通过，正式保留。
- V6-0121 处理 channelize_poly E2E/kernel=`26.5569/26.4035 ms`，perf 为 1048576 complex samples、97 taps、8 channels。原 kernel 的每个 `(point,channel)` 线程均重复计算同一 point 的 8 路 polyphase accum；专用 kernel 改为每线程一个 point，每个 phase 的 accum 只算一次，再按原 phase 顺序更新 8 个 channel，并由 block 前 64 线程按原公式生成 shared twiddle 表。
- V6-0121 仅在 `n_chans == 8 && n_pts >= 256` 时启用，其他 shape 保留原 kernel；tap/sample/rn_madd、每 channel DFT 加法顺序、padding 和输出布局不变。强门禁为双指标至少下降 `20%`，稳定有效门禁为双指标至少下降 `5%`且绝对各省至少 `1 ms`；两档都要求至少四批达标、max abs/RMSE 不增并完成完整回归。
- V6-0121 在实际产品 generic/point kernel 间做逐实部/虚部 bitwise A/B：覆盖 126 例、`1,471,492` 个 complex 输出，包括 `255/256/257`、5 档 taps、`x_size % 8=0..7`、非 8 通道回退和主规模。阈值 sweep 要求 `256/257/512/1024/4096/16384/131072` 每档至少 4/5 批 E2E/kernel 同时改善 `0.5%`，否则不批准 `256` 阈值。
- 五批主规模还锁定 max abs/RMSE/mixed/max relative 不高于 `1.26441e-6/3.3783e-7/5.85883e-5/0.00105172`；Owner、Standards、Spec 静态审查均无阻断。
- V6-0121 设备 A/B 126 例全部位级通过，七档阈值 sweep 均为 5/5 批双项收益，正式 crossover=`256`。主规模五批 E2E/kernel 中位数=`2.35314/2.19482 ms`，相对 `26.5569/26.4035 ms` 下降 `91.14%/91.69%`，四项误差不增；dlsmi、filtering `17/17`、双任务 L1、all81、dtype、14 步和 manifest 全部通过，正式保留。
- V6-0122 以 all81 `firfilter2` E2E/kernel=`6.22077/6.11656 ms` 为基线，先验证将 `reverse -> backward FIR -> reverse -> crop` 等价改写为沿正向输出索引读取 `min(padded_index+tap,N-1)` 并直接写最终结果；公共 API、padding、tap 顺序、shape/dtype/schema 不变，候选必须先通过位级索引 probe。
- V6-0122 候选只在 31 taps、单连续行且 `axis_size>=65536` 时自动启用；其他 taps、小规模、多行和跨步轴保留原链路。测试钩子可强制 generic/direct 并读取实际选路，覆盖 `65535/65536/65537`、负 axis、`padlen=0` 和多轴布局。
- 宿主公式 probe 已检查 792 例、`246252` 个 float 输出，位级差异 0；Correctness Reviewer PASS。容器专项 probe 将 generic/direct 位级 A/B、auto 实际路由和 5 档阈值收益分开记录；正式保留仍以正常 auto 路径五批相对固定基线双指标至少下降 `5%`、绝对各省至少 `0.25 ms`且至少四批达标为准。
- V6-0122 设备 A/B 13 例、`1,319,181` 个 float 输出全部位级相等，实际 crossover=`65536`；`65536/65537/262144/1048576` 各档均为 5/5 批双项收益。正常 auto 路径五批 E2E/kernel 中位数=`5.66339/5.56020 ms`，相对固定基线下降 `8.96%/9.10%`，绝对节省 `0.55738/0.55636 ms`，四项误差完全不变。dlsmi、filtering `17/17`、双任务 L1、all81、dtype、14 步和 manifest 全部通过，正式保留。
- V6-0123 以 all81 `filtering/resample` E2E/kernel=`6.93087/6.85412 ms` 为基线；先验证把 output 全量清零、低频复制和高频复制合并为每个输出 bin 恰好写一次的频谱重排 kernel。Nyquist 的下采样相加和上采样折半/镜像必须保持原操作顺序和位级结果，FFT、window、axis、domain、shape/dtype/API/schema 不变。
- V6-0123 自动路径仅覆盖正式 perf 配置：单连续行、time/Hann、`1048576 -> 1572864`；其他配置保留旧调度。强制 generic/fused 设备 A/B 仍覆盖极小尺寸、奇偶上下/等长、跨步/负 axis、time/freq、workspace 大小交替和双向主规模；主自动尺寸五批至少 4/5 批 E2E/kernel 同时下降 `0.5%`，正式 auto 五批再按 `5%`或绝对 `0.05 ms`门禁验收。
- V6-0123 设备 A/B 20 例、`2,626,285` 个 float 输出全部位级相等，auto 仅主规模实际选路为 fused；强制 sweep 主规模 4/5 批达到双项 `0.5%`。正常 auto 五批 E2E/kernel 中位数=`6.82613/6.74654 ms`，相对固定基线下降 `1.51%/1.57%`，绝对节省 `0.10474/0.10758 ms`，五批四项误差完全不变。dlsmi、filtering `17/17`、双任务 L1、all81、dtype、14 步和 manifest 全部通过，正式保留。
- V6-0124 以上述 V6-0123 五批中位数为固定分母；仅在已有 fused pack 路径中把 `apply_window_fftshift` 下沉为按源 bin 载入后的同序乘法，随后执行相同的低/高频映射和 Nyquist 操作。先用宿主位级 probe 覆盖无窗、直接窗、fftshift 窗以及奇偶上/下/等长，再做设备 pack/windowed-pack A/B；FFT、window 生成/cache、公共 API 和非自动配置不变。
- V6-0124 的 21/21 源指纹、3954 例宿主位级 probe 和 Release 构建通过，但设备 A/B 进程 SIGSEGV，后续性能、sanitizer、dlsmi、完整回归和审计均未运行；本轮不登记收益，正式基线继续使用 V6-0123。
- V6-0125 仅增加默认关闭的设备 A/B trace 和单 case 隔离：逐路径强制落盘 `before_call/after_resample/after_device_sync/after_get`，完整 trace 后重跑最后 case；若单 case 通过，再禁用 device storage cache 运行全量对照。定位完成前不进入其他算子。
- V6-0125 完整 trace 中 case 1-26 的四路径均结束；官方 case 25 `1048576 -> 1572864` observed=`0/1/2/2` 并独立通过。case 27 `1048576 -> 1572863` 在首个 generic `before_call` 后 `rc=139`，独立新进程仍复现，已排除 windowed-pack、显式 device window 生命周期和跨 case 累计状态。
- V6-0126 把 auto scope 抽为生产单一 predicate，并新增不创建 device array、不调用 `resample` 的 10 例 host-only 字面真值表；动态 A/B 删除仅用于路由边界、会触发大非平滑 FFT 的四例，保留 31 个平台可执行的奇偶升降采样、窗口、布局、axis/domain、异常和官方 exact 覆盖。
- V6-0126 正式验证前由独立子进程逐一观察四个 `N±1/M±1` 路由边界，并要求 smooth `1048576/1572864` 完整通过、已知 nonsmooth `1572863` 在 `cufftPlan1d` 内稳定 `rc=139`。正式脚本必须复核归档内 source/script SHA、原始 RC 和 marker，并硬断言 dtype missing=0、calculation steps=14、timing/accuracy gap=0；任一不满足即停止，不能通过删测试或只看审计进程 RC 掩盖回归。
- V6-0126 容器运行仅完成 source SHA；standalone probe 的单条 `dlcc -x cuda` 命令把后续 `.so` 继续按 CUDA 源解析，build=`1`，六 case 均为未运行 `99`，正式脚本按门禁跳过。该结果只证明验证工具错误，不形成产品、FFT 或性能结论。
- V6-0127 只把 probe 构建拆成 `.cu -> .o` 编译与 `.o + curt/dlfft/dleol -> executable` 链接，分别记录 RC；产品/测试、六 case、归因规则、固定 V6-0123 分母和完整回归均不变。
- V6-0127 compile/link/build 均为 0，smooth `1048576/1572864` 完整通过，`1572863` 在 plan 内稳定 `139`；`1048575` 的 plan 成功后，exec 因 16 MiB local-memory 资源超限返回 `255`。旧 coverage 只接受 `0/20/30/40/139`，因此 aggregate=`1`，正式链路按门禁未运行。
- V6-0128 不接受任意非零 RC；每个边界必须有 `before_plan`，并把 `0/20/30/40/139/255` 与各自 complete、错误阶段或 Driver 0701 marker 配对。真实归档回放中旧门=`1`、新门=`0`，删除 marker、删除 0701、伪造 timeout/未运行或无非零清理 marker 的 `40` 均重新判 `1`；正式脚本绑定四个逐 case 结果和 aggregate。
- V6-0128 的 Filtering Owner、Standards、Spec、Evidence Guard 均通过；六个冻结文件同步和回读证据为 `/home/usr_04/CETC_garbage/cetc_v6_0128_deploy_readback_U3YUo17T/`。
- V6-0128 前置与正式链路全部通过。resample 五批 E2E/kernel 中位数=`6.65073/6.57236 ms`，相对 V6-0123 再下降 `2.57%/2.58%`，绝对节省 `0.17540/0.17418 ms`，五批精度完全不变；31 case 设备 A/B、filtering `17/17`、双任务 L1、all81 `81/81`、dtype/14 步和 manifest 全部通过，正式保留 V6-0124 窗乘融合。
- V6-0129 的 host probe、构建和 17 case 设备位级 A/B 均通过；五批 STFT E2E/kernel 中位数=`19.9574/19.8011 ms`，相对 `20.0438/19.8608 ms` 仅下降 `0.43%/0.30%`，只有 2/5 批达到双项绝对收益门。性能门禁失败，后续回归按止损跳过，STFT 候选已恢复。
- V6-0130 评估把两路实数 CSD 打包为一次 C2C。独立 host probe 的最大差异为 `9.87377646e-8`、RMSE=`6.73709391e-9`，显著高于当前 CSD perf max abs=`9.31323e-10`，未改产品。
- V6-0131 保留两路独立实数序列、去均值树、窗乘、FFT 和交叉谱公式，仅把两个 segment prepare 写入一个连续 workspace，并把两次同规格 C2C exec 合并为一次 `batch=2*nseg`。
- V6-0131 自动选路严格限定到官方 CSD perf：一维 `[1048576]`、`axis=-1`、named Hann、`800 Hz`、`256/128/256`、constant detrend、one-sided、density、mean；其余配置保持 generic，测试钩子可在 constant detrend 下强制 paired 路径。
- V6-0131 产品、测试、host probe 和正式脚本已同步 `gpu_04` 并回读逐字节一致；部署证据：`/home/usr_04/CETC_garbage/cetc_v6_0131_final_readback_kmhIjc/`。
- V6-0131 source、host probe、构建、12 case 设备位级 A/B、sanitizer 和五批数值均通过；五批 E2E/kernel 中位数=`18.8101/18.7213 ms`，相对固定分母仅下降 `0.2545%/0.3736%`，双项达标批次=`1/5`。完整回归按止损跳过，候选已恢复。
- V6-0132 处理 periodogram E2E/kernel=`0.623577/0.192984 ms` 的 `0.430593 ms` kernel 外固定开销；命名窗口、scale 和频率轴在同配置重复调用中复用，host/device explicit window 保持原路径。
- V6-0132 不改 FFT、detrend、窗乘、PSD 或输出；9 case 设备 A/B 必须逐位相等。五批 paired 对照要求 E2E 中位数和至少 4/5 批下降 `5%`或绝对 `0.05 ms`，kernel 中位数和至少 4/5 批不得退化超过 `3%`或 `0.01 ms`；通过后执行 dlsmi、双任务 L1、spectral、all81、dtype、14 步和 manifest。
- V6-0132 五批同源码 bypass/candidate E2E 中位数=`0.659052/0.387250 ms`，下降 `41.24%`；kernel=`0.192644/0.192576 ms`，误差不变，5/5 批通过。dlsmi、双任务 L1、spectral `9/9`、all81 `81/81`、dtype/14 步和 manifest 全部通过，正式保留。
- V6-0133 处理 Welch E2E/kernel=`0.928063/0.609520 ms` 的 `0.318543 ms` kernel 外固定开销；复用命名窗口、scale 和频率轴，显式窗口保持不缓存。
- V6-0133 将 spectral cache key 中的 float 参数从六位小数文本改为 float32 位模式；设备 A/B 增加相邻 `fs` 跨调用 miss/hit 检查。12 case 必须逐位相等；五批 E2E 按 `5%`或绝对 `0.05 ms`、kernel 稳定门验收，通过后运行完整阶梯。
- V6-0133 五批 bypass/candidate E2E 中位数=`0.951467/0.792062 ms`，下降 `16.75%`、绝对节省 `0.159405 ms`；kernel=`0.629814/0.613350 ms`。12 case 设备 A/B、dlsmi、双任务 L1、spectral `9/9`、all81 `81/81`、dtype/14 步和 manifest 全部通过，正式保留。
- V6-0134 处理 ISTFT E2E/kernel=`0.663961/0.216292 ms` 的 `0.447669 ms` kernel 外固定开销；仅缓存命名/参数窗口 device storage、按旧顺序计算的窗口和，以及按 `(输出长度, fs)` 生成的时间轴。
- V6-0134 不改谱扩展、逆 FFT、overlap-add、workspace 清零、输出布局或数值公式；host/device explicit window 和强制 bypass 完整走旧路径。12 case 设备位级 A/B 后做五批 paired 对照，E2E 按 `5%`或绝对 `0.05 ms`、kernel 稳定门验收。
- V6-0134 首轮 source、host probe、Release 构建、12 case 设备位级 A/B 和 sanitizer 门均通过；五批 bypass/candidate E2E 中位数=`0.642347/0.506345 ms`，下降 `21.17%`，五批全部达到 E2E 门。kernel 中位数=`0.216106/0.215390 ms`，变化 `-0.33%`，但第 1、4 批候选受抖动影响，稳定批次仅 `3/5`，故正式性能门失败，dlsmi 和完整回归未运行。
- 不事后放宽门限，不改产品代码；确认脚本保持五批、同一固定分母和原 `4/5` kernel 稳定门，只把每路采样从 `warmup 3/repeat 30` 增加到 `warmup 10/repeat 100`。通过后才继续 dlsmi、双任务 L1、spectral `9/9`、all81 `81/81`、dtype、14 步和 manifest。
- V6-0134 增采样确认五批 bypass/candidate E2E 中位数=`0.682767/0.473596 ms`，下降 `30.64%`、绝对节省 `0.209171 ms`，五批全部达标；kernel=`0.214966/0.206278 ms`，下降 `4.04%`，稳定批次=`4/5`，原门禁通过。
- 确认轮 12 case 设备 A/B 检查 `26432` 个 float 输出并逐位相等；spectral `9/9`、Task1/Task2 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 和 21 项源码指纹全部通过，最终 `overall=0`。dlsmi 进程/全卡峰值=`48/341 MiB`，GPU P95/active median=`78%/74%`。
- V6-0135 对最终 all81 重新审计：剩余高耗时项以 FFT/算法主体、任务已深化链路或低于轻度优化有效线为主；`unit_impulse` 等小算子主要是单次 launch/setup 固定开销。继续修改需要跨入深度算法重写或改变生命周期语义，不再属于 V6.7 低风险范围。

## 关闭结论

- 正式保留 21 个优化方向，失败候选均已回退或明确暂缓；V6-0124 经 V6-0125 至 V6-0128 完成归因和重验后正式保留。
- 最终硬门禁：all81 `81/81`、dtype 缺口 0、14 个计算步骤 timing/accuracy 缺口 0、Task1/Task2 L1、spectral `9/9`、manifest 和源码指纹全部通过。
- V6.7 不再新增产品代码；剩余 FFT 主体、任务热点和需改变缓存生命周期的方向转入后续专项，不以降低精度、兼容性或有效性能线换取关闭。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0134_confirm_pull_eYnWMNuO/`；归档/console SHA256=`de092e941d9d956c5047f5b069b6a59a869bd4863c76f5a00d5260081babea49/acbd653a7d8be8d9c121a237b8b8f60fd6f362bcc7fab8ddad1195267313db`。
- 下一阶段：V6.8 全量回归、同源码性能终测和最终报告收束。
