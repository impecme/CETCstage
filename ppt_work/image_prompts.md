# 比赛答辩 PPT 整页生成提示词（P03～P19）

对应内容规划：[deck_spec.md](./deck_spec.md)；技术事实与数据口径：[evidence.md](./evidence.md)。

本版已参照 `CICC0900702_北方华创_总决赛_答辩PPT.pptx` 与 `凌波驭算_10_25改.pptx`：采用蓝白技术答辩母版、固定顶部导航、当前栏目高亮、单页单结论和“技术结构 + 真实数据”的表达方式；不复用示例中的学校、企业、赛事 Logo 或具体项目内容。

P01 封面、P02 团队、P20 致谢由团队自行制作。本文件生成 P03～P19 的整页 PNG；P03 V04 已确认，后续页面以它为视觉基线。

## 本轮页序重排（数据补图前的唯一依据）

原“81 算子公共机制”页从正式主线移出，原图仅作问答备用。代码架构前置到技术路线之前；三项公共技术之后放三层算子性能页，再进入 Task1 与 Task2：

```text
P03  赛题重述
P04  代码架构
P05  技术路线
P06  访存资源复用：Wiener 代表
P07  并行结构重构：IIR 代表
P08  Shape-aware 分派与 Fusion：Periodogram 代表
P09  task27（27）：任务直接依赖算子性能        待填数据
P10  extended28（28）：赛题附录算子性能        待填数据
P11  core53（53）：原生基础算子性能            待填数据
P12  Task1 公开算子链
P13  Task1 端到端性能
P14  Task2 混合特化链
P15  Task2 端到端性能
P16  正确性与运行验证
P17  性能优缺点与改进方向
P18  核心亮点
P19  AI 工具使用说明
```

`task27` 是 `core53` 的优先子集，`extended28` 与 `core53` 共同构成 `all81`；三层展示优化深度，不能把 `27 + 28 + 53` 相加。P09～P11 在补入同协议真实数据前不生成正式性能图，也不得复制旧 81 算子总览冒充分层结论。

仓库将 `extended28` 定义为扩展集合；正式采用“赛题附录”标题前，团队须核对其与官方附录名单一致。

## 统一母版与数据规则

所有整页生图提示词共同追加：

```text
生成一张完整 16:9 横向技术答辩 PPT 成品页，不是局部素材。白色底，深蓝 #0B5CAD，亮蓝 #1677D2，浅蓝 #EAF3FB，GPU 青绿 #00A6A6，CPU 灰 #788796，优化动作橙 #F28C28，正文深灰 #243447。顶部固定导航：“团队介绍｜赛题解析｜技术路线｜核心技术｜技术指标｜创新点”，本页栏目使用亮蓝圆角块高亮。左上使用抽象蓝色几何标记和“ZQ500 信号处理算子库”，不使用真实 Logo。页面标题左对齐，标题下有一句短结论。所有流程箭头使用正交细蓝线；CPU 与 GPU 必须并列，不能画为串行。扁平、精确、人工 PowerPoint 风格，正文留出 4% 安全边距。避免：无标签装饰图标、照片、人物、芯片渲染、霓虹、渐变、厚重阴影、3D 柱状图、Logo、水印、乱码、小字堆砌。
```

- P04～P08、P12、P14、P18～P19 可以用 GPT 生图模型生成整页。
- P09～P11、P13、P15～P17 必须由真实 JSON 生成图表和页面，禁止让生图模型编造曲线、柱状图、速度数字或运行截图。
- P06～P08 与 P09～P11 使用历史或当前单位 benchmark 时，必须分开标记，不得相除、相乘或合并归因。
- 机制级数字必须显式标注归因口径：只有“仅开/关某机制”的同配置开关对照，才可以写“单机制开关对照”。当前 setup cache `1.70×` 符合这一口径；Wiener Tile/Halo `61.27×`、IIR `1267.88×`、Periodogram R2C+fusion `108.98×` 只能标“代表路径整体前后对比”，不得宣称为单一机制或全库最高收益。`RUN SNAPSHOT` 是成品算子 CPU/GPU 性能，也不得归因给单一机制。

### 正式 L1–L6 实测状态（2026-07-21，覆盖下文旧编号描述）

- Task1、Task2 的正式 L1–L6 页在重排后位于 P13、P15；正确性页位于 P16；优缺点/改进页位于 P17。它们由 `scripts/generate_unified_scale_pages.py` 或同协议数据渲染器从真实 JSON 输出，不再调用生图模型，也不得覆盖其中的曲线、数字和验证结论。
- 数据角标统一为 `FINAL L1-L6 · 2026-07-21 · ZQ500-Q QUAD-0`：每点 7 次运行，首轮 warm-up 排除，CPU/GPU total 取其余 6 次中位数；`speedup = CPU median total / GPU median total` 已直接计算。
- Task1 L6 为 `128×4096`：`364.798 / 11.023 ms = 33.09×`；Task2 L6 为 `128×3072`：`28363.050 / 27.044 ms = 1048.78×`。L6 即原 final-input；L1～L5 固定算法配置、只改变输入规模。
- P15 仍是 2026-07-20 的全库性能快照，不能与新任务曲线混算。任何后续重测必须再次运行统一脚本并由数据渲染器重出图。

---

## P03｜赛题重述（待更新、技术链路版）

**文件**：`generated/P03_赛题重述_整页_v04_交付链路.png`

**已锁定语义**：`Host 端信号数据与参数 → 统一 C++17 接口（type / shape / axis 合约）→ 公共信号处理算子库（12 模块·81 算子）→ CPU reference 与 ZQ500 GPU 双后端 → 两后端均执行 Task1、Task2 并对照`。

删除右下角蓝色交付横条与左下来源脚注；右侧技术链在 Task1、Task2 双任务框处收束。脚注如需保留，只写“来源：README · contracts · reports”。不要恢复无标签图标墙、输入样例小图、芯片图标或结果图标，也不要把 CPU 只连 Task1、GPU 只连 Task2。

---

## P04｜“3 + 2 + 5”技术路线

**栏目**：技术路线。  
**页结论**：`3 类通用公共机制提供跨算子执行基础；代表算子负责展开算法级重构，2 条应用沿 5 类路径组合落地。`

```text
生成完整技术路线页。主标题：“3 + 2 + 5 技术路线”；标题下结论：“三类通用公共机制 + 两条应用算法构建 + 五类可组合优化路径”。页面主体采用参考页的“左公共库、右应用构建、底部结论带”结构；所有抽象机制必须配极简、可读的微流程图，不能只列术语。

左侧 42% 标题“底层公共算子库优化”，蓝色六边形“3 通用机制”。竖排三张浅蓝卡：① `访存与资源复用`，微图为重叠邻域窗口汇入 shared Tile，以及 `capacity / prepared / content` 三个可复用对象回环；短注“减少重复读取、分配和准备”。② `并行结构重构`，微图为红色串行依赖链转换为青绿色分层 scan/reduction 树；短注“把依赖改写为可结合、可分块结构”。③ `Shape-aware 分派与算子内 Fusion`，微图为 `shape / dtype / order` 方块分流到 `direct / tiled / FFT / scan` 并汇向紧凑输出；短注“选对路径、减少中间读写和 launch”。左下单独给一条代表案例带：“Wiener Tile/Halo · IIR Affine Scan · Periodogram R2C”；只填一个公共库真实数字“典型公开算子 Wiener：183.62×”。严禁在左栏画 Device-resident、H2D/D2H 链路或任务流水，它们属于右栏的多算子应用构建。

右侧 53% 标题“应用级算法构建”，上方两个蓝色六边形“2 构建”“5 路径”。左半两张浅青任务卡：Task1 卡片画“脉冲小矩阵 → 距离-多普勒热图 → 检测准星”，短注“公开算子驻留组合 → 检测”，大号橙色 `33.09×`；Task2 卡片画“三帧小矩阵 → 四条 score 条带 → 轨迹折线”，短注“算子库 + private helper → score/轨迹”，大号橙色 `1048.78×`。两数字下方都必须小字标“L6 中位数 · 2026-07-21”，不得伪装为单 kernel 或历史前后对比数字。右半竖排五条橙色路径：`设备驻留/批处理`、`准备与内容缓存`、`融合/直接写回`、`并行 Scan/归约`、`score-only/紧凑输出`。底部深蓝带：“3 类通用机制 + 2 条应用构建 + 5 类组合路径”。页脚：“Task 速度为正式 L1–L6 的 L6 CPU/GPU total 中位数直接加速比。”
```

---

## P05｜通用机制①：访存与资源复用——以 Wiener Tile/Halo 为代表

**栏目**：核心技术。  
**页结论**：`同一输入、同一准备资源和相邻输出的重复访问，应在单算子内转化为“加载/准备一次，多次复用”。`

```text
生成完整三段式技术页，标题：“通用机制①：访存与资源复用——Wiener Tile/Halo 代表”。左侧“单算子复用对象”：画 `capacity`、`prepared plan/table`、`邻域输入` 三张浅蓝卡，每张卡均为“命中 → 直接执行 / 未命中 → 创建后复用”的小回环；只表达单算子资源生命周期，禁止画 Task1、Task2 或跨算子 Device-resident 链。中间“Wiener 落地”：同一张灰色 global memory 网格上，三个半透明红色邻域窗口重叠，重构为青绿 `16×16 output tile` 与橙色 `(16+2r)×(16+2c) Halo`，蓝色 shared-memory 外框；线程协作加载后，一个 Tile 扇出供多个相邻输出复用。右侧只保留一张深蓝“性能结果”大卡：标题 `Wiener Tile/Halo`，时间 `214.44 → 3.50 ms`，大号数字 `61.27×`，底部极小口径标记 `历史版本 · 组合路径`。删除全部其余性能卡、归因卡、RUN SNAPSHOT 和红色说明框。底部红色细注：“适用边界：2D · 奇数窗口 · 每维≤31；有效 key 缓存 · 非 Unified Memory / zero-copy。”底部蓝色结论条：“单算子复用：一次加载/准备，多次输出复用。”不画芯片、人物、无意义方块或任务链。
```

---

## P06｜通用机制②：并行结构重构——以 IIR Affine Prefix Scan 为代表

**栏目**：核心技术。  
**页结论**：`递推重构：分块可结合，分层可并行。`

```text
生成完整技术页，标题：“通用机制②：并行结构重构——IIR Affine Scan 代表”。顶部先画通用关系“串行依赖 → 结构变换 → 分层并行”。左侧画 12 个灰红状态节点首尾相接的唯一长链，顶部公式“sₙ = Aₙsₙ₋₁ + vₙ”，红色标记“临界路径长”。中间画同样 12 个橙色 affine 小块，两两组合、再分层组合，最终形成四层青绿色 scan 树；树下三组 Tile 内节点并行应用初始状态，标“tile scan → transform scan → initial state → parallel apply”。右侧只保留一张深蓝“性能结果”大卡：标题 `lfilter`，时间 `455.17 → 0.359 ms`，大号数字 `1267.88×`，底部极小口径标记 `历史版本 · 组合路径`。删除 RUN SNAPSHOT、单项参数对照说明与红色文字区。底部深蓝结论条必须写“递推重构：分块可结合，分层可并行。”页脚：“适用边界：低阶 · 无 state · 单连续长线；单算子内依赖变换。”
```

---

## P07｜通用机制③：Shape-aware 分派与算子内 Fusion——以 Periodogram 为代表

**栏目**：核心技术。  
**页结论**：`按 shape、类型与约束选对单算子路径，再融合可合并前后处理，才能同时减少无效计算、读写与 launch。`

```text
生成完整上下对齐的技术页，标题：“通用机制③：Shape-aware 分派与算子内 Fusion——Periodogram 代表”。页面顶部画一个明确的单算子“分派门”：`shape / dtype / order / window` 进入网关，四条路线分别标 `direct`、`tiled`、`FFT/R2C`、`scan`，只选择一条路径；禁止画任务链。下方选中 `FFT/R2C` 分支并展示 Periodogram：上方灰红旧路径严格为“输入波形→detrend→window→独立 C2C FFT→完整双边频谱→power 中间量→PSD”，window、full spectrum、power 后各放一块大灰色缓冲和红色写回箭头；下方青绿新路径严格为“prepared/cache→fused detrend+window→独立 R2C FFT→宽度约一半的单边谱→fused power/crop/scale PSD”。FFT 节点保持独立，不能画成 FFT 与 PSD 同一个 kernel。右侧只保留一张深蓝“性能结果”大卡：标题 `R2C + Fusion`，时间 `72.91 → 0.669 ms`，大号数字 `108.98×`，底部极小口径标记 `历史版本 · 组合路径`。删除其余性能卡、单项参数对照说明和红色归因框。底部红色细注：“适用边界：CSD/spectrogram 回退 C2C；shape / dtype / 正确性约束。”
```

---

## P08｜Task1：五类路径组合公开算子雷达检测链

**栏目**：核心技术。  
**页结论**：`六个公开算子在 Device 内连续组合，五类应用路径分别落在真实节点。`

```text
生成完整 Task1 应用技术页，标题：“Task1：按 5 条路径组合公开算子雷达检测链”。顶部结论：“六步公开算子驻留组合；五类路径映射真实节点。”中央左侧约 68% 画一条青绿色 Device-resident 主链：左侧单次 H2D 入口，右侧紧凑 D2H/validation 出口。主链严格为 `pulse compression`（匹配滤波窄峰）→`pulse Doppler + shift`（距离-多普勒网格）→`power map`（功率热图）→`CA-CFAR`（阈值与 detection mask）→`final detection`（检测准星）；模板旁路 `ambgfun` 模糊函数曲面独立并列，绝不连接 CFAR。中央主链外必须有一条连续 Device-resident 包围带。右侧约 28% 画标题“本任务实际采用的 5 条路径”的竖向路径面板，每张卡用细连接线明确指向主链落点：①“Device-resident：入口一次 H2D，链尾 materialize”连接整个包围带；②“prepared/cache：template FFT 复用”连接 pulse compression；③“fusion/direct write：scale + transpose/shift”连接 Doppler/shift 与 power map；④“parallel scan/reduction：row-prefix CFAR + two-stage peak”连接 CFAR 和 final detection；⑤“compact output：仅 detection list 回传”连接最终输出。不要把 ① 写成公共单算子机制，它是任务级多算子链路优化。底部一条窄版本对比带，标题必须写“历史优化前后对比（版本候选，非当前正式 L6；不同 run，不能累加）”，四张微卡依次写：`template cache · L6 stage -7.43% / total -2.14%`；`transpose+shift · L6 stage -11.57% / total -2.03%`；`row-prefix CFAR · L6 stage -28.68% / total -4.79%`；`two-stage peak · L6 stage -43.95% / total -4.12%`。Device-resident 旁用灰字“无独立关闭消融，仅结构事实”。右上蓝色小卡：“任务总效果见 P09 · FINAL L6 33.09×”，明确不能归因给任一路径。页脚：“6 public steps 均调用算子库 GPU 实现；逐步同步计时。”不得画 CPU shortcut、伪造单独路径总加速或把历史前后对比相加。
```

---

## P09｜Task1：正式 L1–L6 性能与正确性（已实测）

**现有成品**：`generated/P09_Task1_L1-L6_实测_v08.png`。由真实数据渲染器生成，不提供生图提示词。
**数据源**：`data/reports/demo/task1_radar/scales/L1…L6/metrics.json`。
**页结论**：`原 final-input 纳入 L6；固定窗口、CFAR 与公开算子链，仅改变输入规模，端到端加速为 25.53×～33.09×。`

若后续代码变更需要重出图，运行统一测评和 `scripts/generate_unified_scale_pages.py`；禁止手改曲线或数字。

---

## P10｜Task2：五类路径构建 Batched Score-Only Pipeline

**栏目**：核心技术。  
**页结论**：`五类应用路径把全量中间张量压缩为批量四路 score、peak 与轨迹。`

```text
生成完整 Task2 应用技术页，标题：“Task2：按 5 条路径构建 Batched Score-Only 流程”。顶部结论：“全量张量裁剪为批量 score、peak 与轨迹。”上方灰色 CPU reference 仅作对照：`逐帧 → full correlate / full spectrogram / full CWT → host postprocess`，画出大二维/三维中间张量。下方青绿色 GPU 主链约占页面 67%：`一次 H2D → B=8 Device batch → filter/demod score、correlate score、spectrogram band-score、CWT max-score → weighted/smooth private helper → independent row peak → Kalman state/track → compact materialize`。用形状差异明确表示“全量张量 → 四路一维 score → 每帧一个 peak/track”。右侧约 29% 画标题“本任务实际采用的 5 条路径”的竖向路径面板，每张卡使用细连接线精确指向 GPU 主链：①“Device-resident / batch：一次 H2D，B=8，不逐帧 .get()”连接入口与 Device batch；②“prepared / AOT：correlate、spectrogram 固定 shape 预编译/预准备”连接两条 score 分支；③“direct write / task fusion：各分支直接写 task score；peak 仍独立 kernel”连接 score 分支到 weighted/smooth；④“parallel reduction：band-score、CWT max-score、row peak”连接谱图、小波和 peak，严禁写 prefix scan；⑤“score-only / compact output：仅四路 score、peak、Kalman state/track”连接最终输出。清楚标 `mixed = public operator library + private helper`，helper 不是第三后端。底部一条窄版本对比带，标题必须写“历史优化前后对比（版本候选，非当前正式 L6；不同 run，不能累加）”，仅两张性能微卡：`AOT correlate · L6 hotspot -61.66% / total -9.77%`；`AOT spectrogram · L6 hotspot -43.37% / total -7.78%`。其余路径统一灰色小注“结构已采用，待独立归因”；禁止用 Task2 `1048.78×` 倒推任何一路径收益。右上蓝色小卡：“任务总效果见 P11 · FINAL L6 1048.78×”。底部测评约束三块：`冻结：B=8 / score-only`、`改变：帧数`、`P11：统一 L1-L6 实测`。页脚：“radix-2 pad 最大 4096；weighted+smooth 与 peak 独立 kernel；Kalman 跨帧串行。”
```

---

## P11｜Task2：正式 L1–L6 性能与正确性（已实测）

**现有成品**：`generated/P11_Task2_L1-L6_实测_v08.png`。由真实数据渲染器生成，不提供生图提示词。
**数据源**：`data/reports/demo/task2_features/scales/L1…L6/metrics.json`。
**页结论**：`原 final-input 纳入 L6；冻结 B=8、score-only 与门限，仅改变帧数，端到端加速为 415.96×～1048.78×。`

若后续代码变更需要重出图，运行统一测评和 `scripts/generate_unified_scale_pages.py`；禁止手改曲线或数字。

---

## P12｜代码架构

**栏目**：核心技术。  
**页结论**：`公开 API、共享语义与 CPU/GPU 双后端构成三层核心架构。`

```text
生成完整三层软件架构页，标题：“代码架构：公开 API、共享语义与双后端”。副标题：“三层核心架构统一语义；右侧保留 README 原始目录树。”左侧 56% 只保留三层：第一层“公开 API”，深蓝接口带 `include/cusignal`，内置“聚合头 · 核心类型 · 模块声明 · ZQ500 兼容层”；第二层“共享语义”，浅蓝带 `src/common`，内置“参数 · shape / axis · 数值规则”；第三层“CPU/GPU 双后端”，从 `src/common` 分叉到灰色 `src/cpu CPU reference · C++ loops / FFTW` 与青绿色 `src/zhongkexin ZQ500 backend · kernels / FFT / BLAS / Solver`，二者并列而非串行。GPU 右侧可保留窄支路 `Task2 private helper · batch / score / track`。右侧 38% 只画蓝色虚线边框，标题 `README 原始目录树截图区`，内部完全留白，供后续粘贴 README.md 的原始目录树截图；不得由模型重写目录树。底部仅保留蓝条 `公开 API · 共享语义 · CPU/GPU 双后端`，左下红色边界卡 `ZHONGKEXIN 构建 · CUDA-like ABI ≠ NVIDIA 后端`。删除“工程入口”“工程产物”“构建→测试→任务→报告”等两层内容；不用口语化长句。
```

---

## P13｜81 算子与公共执行机制

**栏目**：核心技术。  
**页结论**：`81 个算子共享数据驻留、资源复用、形状分派与门禁机制，而不是 81 套孤立实现。`

```text
生成完整机制页，标题：“81 个算子：共用执行基础，而非 81 套孤立优化”。上方为 12 个模块的窄计数带：waveforms 5、bsplines 3、windows 23、filter design 5、filtering 17、radartools 6、spectral 9、wavelets 5、correlate 3、demod 1、estimation 1、peak finding 3，总计“= 81”。下方四条清晰泳道，每条只画真实机制和短标签：① Host/Device variant：Host 输入一次 H2D → Device returns → 链尾显式 .get()；② shared_ptr DeviceStorage：浅层 alias → best-fit capacity reuse；③ prepared/content cache：plan/table/uploaded copy 命中后复用；④ shape-aware dispatch → correctness gate → E2E gate → fallback。最底红字边界：“不是 Unified Memory、zero-copy 或 online autotuner；Task helper 不计入 81。”不要用无含义图标墙。
```

---

## P14｜正确性与任务运行验证：正式 L6 已实测

**现有成品**：`generated/P14_L6正确性_实测_v08.png`。真实数据渲染，不提供生图提示词。
**页结论**：`12 个统一规模点均通过；L6 正确性、性能与统计口径来自同一份结构化运行报告。`

后续重测只能由同一数据渲染器替换。不得把旧 `final/metrics.json` 的误差贴到本页。

---

## P15｜全库性能分布

**生成方式**：真实数据制图，不使用生图模型。  
**页结论**：`大规模 stencil、频谱与批处理收益高；极小标量和固定 setup 主导的 case 仍可能慢于 CPU。`

```text
用同一母版生成整页。顶部首先显示“81/81 公开算子有性能记录”。主图为来自 73 个算子的 78 个 `source=case_detail` 真实 GPU E2E speedup，按升序等距排布，纵轴 log，水平 1× 参考线；9 个慢于 CPU 的点用红色，69 个快于 CPU 的点按模块蓝绿着色。8 个只含 `summary_aggregate` 的算子不混入 case 散点，但在页脚和外部表说明。右侧三项大数字：69 快 / 9 慢、median 17.463×、geomean 10.113×。标注 Wiener 183.615× 与 lfilter event 1.457× / E2E 0.504×。页脚：“完整 81 算子直接计算的 CPU/GPU speedup 表：ppt_work/data_tables/operator_performance_81.csv。”
```

---

## P16｜正式 L1–L6 规模效应与热点（已实测）

**现有成品**：`generated/P16_L1-L6规模与热点_实测_v08.png`。真实数据渲染，不提供生图提示词。
**页结论**：`Task1 受固定开销影响而波动；Task2 随 batch 规模释放并行度，L6 Top3 已给出下一轮优化优先级。`

后续重测只能由同一数据渲染器替换。GPU event 只能表述为 stream work，不得写成单 kernel profiler 时间。

---

## P17｜性能优势、边界与改进方向

**栏目**：技术指标。  
**页结论**：`先用统一协议建立可比基线，再对分块、阈值和热点做单项参数对照。`

```text
生成完整三列技术页，标题：“性能优势、边界与改进方向”。左列青绿“已实现的结构优势”：`Tile/Halo：邻域复用`、`Affine Scan：递归转并行`、`R2C+Fusion：减少写回`、`Device-resident：减少回传`。中列蓝色“补齐统一复测”：`L6：统一规模配置`、`L1-L5 仅变输入规模`、`speedup 自动计算`、`误差与性能同一 run`。右列橙色“单项参数对照”：`Block/Halo：单项参数对照`、`CFAR 参数：单项参数对照`、`batch/shape：按 Top3 优先`。底部深蓝结论条写：“统一测评 · 单项参数对照 · 参数优化。”不填未复测任务性能数字；页面不出现 `final-input`。
```

---

## P18｜核心亮点

**栏目**：创新点。  
**页结论**：`将不适合 GPU 的访存、递归和中间量结构，重写为可复用的 ZQ500 执行结构。`

```text
生成完整三卡亮点页。三张卡都按“问题 → 方法 → 价值”自上而下阅读：① 邻域访存重构：`相邻窗口重复读 → Tile/Halo 复用 → 服务 Wiener 类算子`；② 递归与频谱重构：`IIR 递归、双边频谱 → Affine Scan / R2C → 重写为并行结构`；③ 任务级语义裁剪：`完整中间量物化 → Device-resident / score-only → 只保留 score/轨迹`。底部蓝色注：“统一 L1-L6 复测完成后，再将同协议端到端收益填入亮点效果数据。”页脚：“只列已实现方法，不用旧独立 final-input 数字。”
```

---

## P19｜AI 工具使用说明

**栏目**：创新点。  
**页结论**：`AI 辅助代码与文档工作；核心亮点与优化技术由团队提出，全部结论人工复核。`

```text
生成简洁的 AI 使用说明页，标题：“AI 工具使用说明”。左侧青绿“AI 辅助表达”：答辩结构梳理、代码/报告审计、图像提示词、PPT 版面汇编；在左下增加“AI 辅助使用比例”两行比例条，文字必须为“代码辅助：90%”“文档 / PPT 辅助：60%”，比例仅表示辅助使用范围，不表达性能。中央深蓝“数据与人工核验”：README/源码、metrics.json、性能表、契约与正确性报告逐项核对。右侧橙色“AI 不可替代的边界”：不生成性能数字、不伪造测试曲线/截图、不替代代码运行与正确性判断。中央下方用深蓝强调框写：“核心亮点与优化技术：团队提出 · 非 AI 生成”。底部结论：“AI 辅助表达 · 全过程人工复核”。避免机器人、人物和无标签装饰图；不得出现“证据”、A/B、L1-L6 或其他无关性能数字。
```

---

## 输出命名

整页生成文件保存到 `ppt_work/generated/`：

```text
P03_赛题重述_整页_v04_交付链路.png
P04_技术路线_单算子三机制_v09.png
…
P10_Task2_五路径ScoreOnly_v08_术语收束.png
P12_代码架构_三层加目录树预留_v03.png
P13_81算子与公共机制_v02_门禁术语.png
P17_统一测评与改进方向_v09_统一规模配置.png
P18_核心亮点_生图重构_v06.png
P19_AI工具使用说明_v08_比例与人工原创.png
```

P15 保存可追溯的 `PNG + SVG + 数据导出 CSV/JSON 摘要`。P09、P11、P14、P16 已替换为统一实测 `v07` 数据页；后续重测前逐页检查中文、箭头方向、CPU/GPU 映射、数字、数据角标与安全边距。
