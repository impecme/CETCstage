# 比赛答辩 PPT 整页生成提示词（P03～P19）

对应内容规划：[deck_spec.md](./deck_spec.md)；技术事实与数据口径：[evidence.md](./evidence.md)。

本版已参照 `CICC0900702_北方华创_总决赛_答辩PPT.pptx` 与 `凌波驭算_10_25改.pptx`：采用蓝白技术答辩母版、固定顶部导航、当前栏目高亮、单页单结论和“技术结构 + 真实证据”的表达方式；不复用示例中的学校、企业、赛事 Logo 或具体项目内容。

P01 封面、P02 团队、P20 致谢由团队自行制作。本文件生成 P03～P19 的整页 PNG；P03 V03 已确认，后续页面以它为视觉基线。

## 统一母版与数据规则

所有整页生图提示词共同追加：

```text
生成一张完整 16:9 横向技术答辩 PPT 成品页，不是局部素材。白色底，深蓝 #0B5CAD，亮蓝 #1677D2，浅蓝 #EAF3FB，GPU 青绿 #00A6A6，CPU 灰 #788796，优化动作橙 #F28C28，正文深灰 #243447。顶部固定导航：“团队介绍｜赛题解析｜技术路线｜核心技术｜技术指标｜创新点”，本页栏目使用亮蓝圆角块高亮。左上使用抽象蓝色几何标记和“ZQ500 信号处理算子库”，不使用真实 Logo。页面标题左对齐，标题下有一句短结论。所有流程箭头使用正交细蓝线；CPU 与 GPU 必须并列，不能画为串行。扁平、精确、人工 PowerPoint 风格，正文留出 4% 安全边距。避免：无标签装饰图标、照片、人物、芯片渲染、霓虹、渐变、厚重阴影、3D 柱状图、Logo、水印、乱码、小字堆砌。
```

- P05～P08、P10、P12～P13、P17～P19 可以用 GPT 生图模型生成整页。
- P09、P11、P14、P15、P16 必须由真实 JSON 生成图表和页面，禁止让生图模型编造曲线、柱状图、速度数字或运行截图。
- 性能数字统一标注 `RUN 2026-07-20 SNAPSHOT`；历史优化前后统一标注 `HISTORICAL A/B`。二者不能相除、相乘或合并归因。
- 报告快照与当前源树有 4 项 `SOURCE_FILES.sha256` 漂移；性能页不能写“当前实时结果”，应写“已发布运行快照”。

---

## P03｜赛题重述（已生成、技术链路版）

**文件**：`generated/P03_赛题重述_整页_v03_技术链路.png`

**已锁定语义**：`Host 端信号数据与参数 → 统一 C++17 接口（type / shape / axis 合约）→ 公共信号处理算子库（12 模块·81 算子）→ CPU reference 与 ZQ500 GPU 双后端 → 两后端均执行 Task1、Task2 并对照 → 数值正确性、性能结果、可追溯报告`。

继续沿用当前成品；不要恢复无标签图标墙、输入样例小图、芯片图标或结果图标，也不要把 CPU 只连 Task1、GPU 只连 Task2。

---

## P04｜“3 + 2 + 5”技术路线

**栏目**：技术路线。  
**页结论**：`3 类通用公共机制提供跨算子执行基础；代表算子负责展开算法级重构，2 条应用沿 5 类路径组合落地。`

```text
生成完整技术路线页。主标题：“3 + 2 + 5 技术路线”；标题下结论：“三类通用公共机制 + 两条应用算法构建 + 五类可组合优化路径”。页面主体采用参考页的“左公共库、右应用构建、底部结论带”结构；所有抽象机制必须配极简、可读的微流程图，不能只列术语。

左侧 42% 标题“底层公共算子库优化”，蓝色六边形“3 通用机制”。竖排三张浅蓝卡：① `Device-resident 数据链`，右侧微图为灰色 H 方块 → 橙色 H2D 箭头 → 青绿 Device 方块，旁标 `.get()`；短注“入口 H2D · 链内驻留 · 链尾 .get()”。② `存储与准备缓存复用`，右侧微图为 `buf / plan / data` 三个小块和回环复用箭头；短注“容量 / plan / content 复用”。③ `Shape-aware 分派与 Fusion`，右侧微图为 `shape` 方块分流到 `T / F / S` 三条短路径并汇向紧凑输出；短注“shape 选路径 · 融合减少读写”。左下单独给一条代表案例带：“Wiener Tile/Halo · IIR Scan · Periodogram R2C”；只填一个公共库真实数字“典型公开算子 Wiener：183.62×”。

右侧 53% 标题“应用级算法构建”，上方两个蓝色六边形“2 构建”“5 路径”。左半两张浅青任务卡：Task1 卡片画“脉冲小矩阵 → 距离-多普勒热图 → 检测准星”，短注“公开算子驻留组合 → 检测”，大号橙色 `34.20×`；Task2 卡片画“三帧小矩阵 → 四条 score 条带 → 轨迹折线”，短注“算子库 + private helper → score/轨迹”，大号橙色 `1071.70×`。两数字下方都必须小字标“已发布快照 · 统一复测后替换”，不能伪装成新统一 L6 数据。右半竖排五条橙色路径：`设备驻留/批处理`、`准备与内容缓存`、`融合/直接写回`、`并行 Scan/归约`、`score-only/紧凑输出`。底部深蓝带：“3 类通用机制 + 2 条应用构建 + 5 类组合路径”。页脚：“Task 速度为 2026-07-20 已发布快照；正式答辩用统一 L1–L6 新 L6 数字替换。”
```

---

## P05｜Wiener：Shared Tile / Halo

**栏目**：核心技术。  
**页结论**：`共享内存分块把重叠窗口的重复全局读取转化为块内 Halo 数据复用。`

```text
生成完整三段式技术页，标题：“Wiener：Tile / Halo 将重复访存变为块内复用”。左侧“原始瓶颈”：同一张灰色 global memory 网格上，三个半透明红色邻域窗口重叠，重复读取箭头汇向相同格点，短注“相邻输出反复读取同一邻域”。中间“GPU 重构”：最大的主视觉为 16×16 输出 Tile；中心青绿输出块、完整一圈橙色 Halo、外层蓝色 shared-memory 边框；8×8 线程格通过少量合并箭头协作加载，随后一个共享块扇出到多个相邻输出。右侧“真实证据”：上方深蓝数据卡“HISTORICAL A/B 214.44 → 3.50 ms · 61.27×”；下方浅蓝数据卡“RUN 2026-07-20 SNAPSHOT 646.387 / 3.52033 ms · 183.615×”，旁标“mixed error 9.75527e-7”。最底一行红色细注：“适用：2D、奇数窗口、每维 ≤31；auto-noise 标量回传和 mean/variance 中间量仍存在。”不画芯片、人物或无意义方块。
```

---

## P06｜IIR：Affine Prefix Scan

**栏目**：核心技术。  
**页结论**：`把状态更新改写为可结合的 affine transform，低阶 IIR 才能由串行链变为并行前缀扫描。`

```text
生成完整技术页，标题：“IIR：Affine Prefix Scan 重构递归依赖”。左侧画 12 个灰红状态节点首尾相接的唯一长链，顶部公式“sₙ = Aₙsₙ₋₁ + vₙ”，红色标记“临界路径长”。中间画同样 12 个橙色 affine 小块，两两组合、再分层组合，最终形成四层青绿色 scan 树；树下三组 Tile 内节点并行应用初始状态，标“tile scan → transform scan → initial state → apply”。右侧数据与边界并列：深蓝卡“HISTORICAL A/B lfilter 455.17 → 0.359 ms · 1267.88×*”；浅蓝卡“RUN 2026-07-20 SNAPSHOT：event 1.457×，E2E 0.504×”；红色结论“并行结构已解决，短序列固定成本仍可反转 E2E”。页脚：“* 特定灾难性旧路径；fast path 只覆盖低阶、无 state、单连续长线。”
```

---

## P07｜Periodogram：R2C、Fusion、Cache

**栏目**：核心技术。  
**页结论**：`R2C、融合与缓存分别减少无效频点、全局写回和重复准备，不能混成一个 kernel 效果。`

```text
生成完整上下对齐的频谱流水对比页，标题：“Periodogram：三类削减拆解频谱冗余”。上方灰红旧路径严格为：输入波形→detrend→window→独立 C2C FFT→完整双边频谱→power 中间量→PSD；window、full spectrum、power 后各放一块大灰色缓冲和红色写回箭头。下方青绿新路径严格为：prepared/cache→fused detrend+window→独立 R2C FFT→宽度约一半的单边谱→fused power/crop/scale PSD；FFT 节点保持独立，不能画成 FFT 与 PSD 同一个 kernel。右侧竖排三张证据卡：`HISTORICAL A/B R2C+fusion 72.91→0.669 ms · 108.98×`；`HISTORICAL A/B setup cache 0.659052→0.387250 ms · 1.70×`；`RUN 2026-07-20 SNAPSHOT 1.41709/0.366592 ms · 3.866×`。底部红色细注：“CSD/spectrogram 部分 R2C 因数值问题回退 C2C。”
```

---

## P08｜Task1：Device-Resident 雷达检测链

**栏目**：核心技术。  
**页结论**：`六个公开算子在 Device 内连续组合，只在入口上传、在验证边界回传。`

```text
生成完整 Task1 流程页，标题：“Task1：公开算子构建 Device-Resident 雷达检测链”。中央是一条青绿色 Device-resident 带，左侧单次 H2D 入口，右侧紧凑 D2H/validation 出口。主链六步用有语义图形和清晰标签横向排列：`pulse compression`（匹配滤波窄峰）→`pulse Doppler + shift`（距离-多普勒网格）→`power map`（功率热图）→`CA-CFAR`（阈值与检测 mask）→`final detection`（检测准星）；从模板输入单独分出 `ambgfun` 模糊函数曲面旁路，再与主链在最终证据处并列。主链上仅用五个橙色编号标记实际技术：① template/prepared cache；② scale fusion；③ transpose+shift fusion；④ row-prefix CFAR；⑤ two-stage peak + compact D2H。右下角小注：“6 public steps 均调用算子库 GPU 实现；逐步同步计时，不是 multi-stream pipeline。”所有箭头表达真实依赖：ambgfun 不连接 CFAR，peak 只接 power/detections 的真实汇合处；不得画 CPU shortcut。
```

---

## P09｜Task1：统一 L1–L6 性能与正确性（待复测）

**生成方式**：真实数据制图；本轮只保留填数位置，不使用生图模型。  
**新数据**：`data/reports/demo/task1_radar/unified_scales/L1…L6/metrics.json`。  
**页结论**：`原 final-input 纳入新 L6；冻结分块与 CFAR 参数，只改变输入规模。`

```text
用同一蓝白母版渲染完整 16:9 占位页面。左侧 48% 画空白 L1-L6 加速比坐标：L1～L6 六个等距横轴点、无曲线、L6 橙色；图中写“统一 L1–L6 复测后填入”。中间 23% 放三张窄卡，仅写“CPU（ms）”“GPU（ms）”“speedup”，不填数字。右侧 24% 放四条统一协议：`L6：原 final-input 配置`、`固定：窗口/CFAR 参数`、`固定：公开算子处理链`、`改变：任务输入规模`。下方左侧放两行正确性占位：`Expected / CPU / GPU：待填`、`CFAR error / PASS：待填`；下方右侧放填表字段“CPU total · GPU total · 已计算 speedup · 检测位置 · CFAR error”。页脚严格写：“不使用旧 final-input 或旧 L1-L6 数字；speedup = CPU total / GPU total。”
```

---

## P10｜Task2：Batched Score-Only Pipeline

**栏目**：核心技术。  
**页结论**：`任务只保留最终所需的 score，把完整中间张量压缩成批量四路 score 与轨迹。`

```text
生成完整 Task2 技术页，标题：“Task2：Batched Score-Only 压缩多域特征流程”。左半灰色 CPU reference：`输入 → 相关 → 谱图 → CWT → 融合/track`，强调完整中间量物化与回传。右半青绿色 ZQ500 GPU：`批输入 → 滤波/解调 → 相关 → 谱图 → CWT → 融合/track`，强调只保留任务所需 score 与状态轨迹。底部给出统一测评约束三块：`冻结：B=8 / score-only`、`改变：帧数、输入长度`、`P11：填入新 L1-L6 数据`。页脚：“mixed：公开算子库 + private helper 协同调用；helper 不是第三后端；不展示旧 final-input 性能数字。”
```

---

## P11｜Task2：统一 L1–L6 性能与正确性（待复测）

**生成方式**：真实数据制图；本轮只保留填数位置，不使用生图模型。  
**新数据**：`data/reports/demo/task2_features/unified_scales/L1…L6/metrics.json`。  
**页结论**：`原 final-input 纳入新 L6；冻结 B=8、score-only 与门限，只改变帧数和输入长度。`

```text
用同一蓝白母版渲染完整 16:9 占位页面。左侧 48% 画空白 Task2 L1-L6 加速比坐标，L6 橙色、图中写“统一 L1–L6 复测后填入”；不能画旧趋势或虚构曲线。中间 23% 仅放“CPU（ms）”“GPU（ms）”“speedup”三张待填卡。右侧 24% 放四条协议：`L6：原 final-input 配置`、`固定：B=8 / score-only`、`固定：feature 与 track 门限`、`改变：帧数与输入长度`。下方左侧放`CPU/GPU 轨迹：待填`和`RMSE / feature error：待填`；右侧写填表字段“CPU total · GPU total · 已计算 speedup · track RMSE · feature-score error”。页脚：“不使用旧 final-input 或旧 L1-L6 数字；无独立传统 GPU 基线。”
```

---

## P12｜代码架构

**栏目**：核心技术。  
**页结论**：`公共 API 与共享语义统一 CPU/ZQ500 行为，Task2 helper 是明确的 GPU 任务特化支路。`

```text
生成完整五层正交软件架构页，标题：“代码架构：双后端公共语义与任务特化边界”。第一层四个入口：用户、Task1、Task2、unit/contract tests。第二层一条“include/cusignal 公共 API”接口带。第三层“src/common 共享语义”带，内部三个图标明确表示参数合法性、shape/axis、数学规则。第四层从中央 Y 形分为灰色 CPU reference（FFTW、C++ loops）和青绿色 ZQ500 GPU backend（kernels、FFT/BLAS/Solver）；CPU 与 GPU 不连接成串行。只从 GPU 右下引出细支路“Task2 specialized helper：batch / score / track”，明确它不是第三后端。第五层蓝色证据基座：contracts、81 unit、task reports、provenance。右下红色细注：“仅支持 ZHONGKEXIN；CUDA-like 名称是平台 ABI，不代表 NVIDIA 后端。”
```

---

## P13｜81 算子与公共执行机制

**栏目**：核心技术。  
**页结论**：`81 个算子共享数据驻留、资源复用、形状分派与门禁机制，而不是 81 套孤立实现。`

```text
生成完整机制页，标题：“81 个算子：共用执行基础，而非 81 套孤立优化”。上方为 12 个模块的窄计数带：waveforms 5、bsplines 3、windows 23、filter design 5、filtering 17、radartools 6、spectral 9、wavelets 5、correlate 3、demod 1、estimation 1、peak finding 3，总计“= 81”。下方四条清晰泳道，每条只画真实机制和短标签：① Host/Device variant：Host 输入一次 H2D → Device returns → 链尾显式 .get()；② shared_ptr DeviceStorage：浅层 alias → best-fit capacity reuse；③ prepared/content cache：plan/table/uploaded copy 命中后复用；④ shape-aware dispatch → correctness gate → E2E gate → fallback。最底红字边界：“不是 Unified Memory、zero-copy 或 online autotuner；Task helper 不计入 81。”不要用无含义图标墙。
```

---

## P14｜正确性与任务运行验证：新统一 L6 结果预留

**生成方式**：真实数据制图；本轮只保留填数位置，不使用生图模型。  
**页结论**：`81 算子覆盖保留；两条任务的最终正确性以新统一 L6 的同一 run 为准。`

```text
用同一蓝白母版渲染完整页面。左侧仅保留当前代码/契约覆盖三张大卡：`81/81 公开算子`、`2/2 端到端任务`、`14/14 正式计算步骤`。右上 Task1 新 L6 面板只放两行占位：`Expected / CPU / GPU：待填`、`CFAR error / PASS：待填`。右下 Task2 新 L6 面板只放：`CPU / GPU 轨迹：待填`、`RMSE / feature error：待填`。底部橙色细条：“仅当新 metrics.json 的实际值通过门限，才显示 PASS。”页脚：“不沿用旧 final-input 误差；新数据源：unified_scales/L6/metrics.json。”
```

---

## P15｜全库性能分布

**生成方式**：真实数据制图，不使用生图模型。  
**页结论**：`大规模 stencil、频谱与批处理收益高；极小标量和固定 setup 主导的 case 仍可能慢于 CPU。`

```text
用同一母版生成整页。顶部首先显示“81/81 公开算子有性能记录”。主图为来自 73 个算子的 78 个 `source=case_detail` 真实 GPU E2E speedup，按升序等距排布，纵轴 log，水平 1× 参考线；9 个慢于 CPU 的点用红色，69 个快于 CPU 的点按模块蓝绿着色。8 个只含 `summary_aggregate` 的算子不混入 case 散点，但在页脚和外部表说明。右侧三项大数字：69 快 / 9 慢、median 17.463×、geomean 10.113×。标注 Wiener 183.615× 与 lfilter event 1.457× / E2E 0.504×。页脚：“完整 81 算子直接计算的 CPU/GPU speedup 表：ppt_work/data_tables/operator_performance_81.csv。”
```

---

## P16｜统一 L1–L6 规模效应与热点（待复测）

**生成方式**：真实数据制图；本轮只保留填数位置，不使用生图模型。  
**页结论**：`新曲线只改变输入规模；新 L6 Top3 GPU 耗时步骤决定下一轮优化优先级。`

```text
用同一母版生成整页。上半并列两张空白折线图：Task1 和 Task2 的统一 L1-L6 加速比；只画坐标、L1～L6 横轴、L6 橙色标记和“统一复测后填入”，绝不填旧任务曲线。下半各放三条灰蓝色占位条：`Top1：名称 / GPU ms / 占比（待填）`至 Top3，Task1、Task2 分列。每块底部短注：“热点 = GPU 时间占比最高步骤”。页脚：“L6 = 原 final-input；L1-L5 固定算法参数，仅输入规模递增；GPU event 为 stream work，不是单 kernel profiler 时间。”
```

---

## P17｜性能优势、边界与改进方向

**栏目**：技术指标。  
**页结论**：`先用统一协议建立可比基线，再对分块、阈值和热点做独立 A/B。`

```text
生成完整三列技术页，标题：“性能优势、边界与改进方向”。左列青绿“已实现的结构优势”：`Tile/Halo：邻域复用`、`Affine Scan：递归转并行`、`R2C+Fusion：减少写回`、`Device-resident：减少回传`。中列灰色“统一复测先解决的问题”：`L6 对齐 final-input`、`L1-L5 仅变输入规模`、`speedup 自动计算`、`误差与性能同一 run`。右列橙色“后续参数优化方向”：`Block/Halo：独立 A/B`、`CFAR 参数：独立 A/B`、`batch/shape：独立 A/B`、`按新 L6 Top3 优先`。底部深蓝结论条写：“不把规模变化与参数调优混在同一曲线；先可比测量，再逐项优化。”不填未复测任务性能数字。
```

---

## P18｜核心亮点

**栏目**：创新点。  
**页结论**：`将不适合 GPU 的访存、递归和中间量结构，重写为可复用的 ZQ500 执行结构。`

```text
生成完整三卡亮点页。三张卡都按“问题 → 方法 → 价值”自上而下阅读：① 邻域访存重构：`相邻窗口重复读 → Tile/Halo 复用 → 服务 Wiener 类算子`；② 递归与频谱重构：`IIR 递归、双边频谱 → Affine Scan / R2C → 重写为并行结构`；③ 任务级语义裁剪：`完整中间量物化 → Device-resident / score-only → 只保留 score/轨迹`。底部蓝色注：“统一 L1-L6 复测完成后，再将同协议端到端收益填入亮点效果证据。”页脚：“只列已实现方法，不用旧独立 final-input 数字。”
```

---

## P19｜AI 工具使用说明

**栏目**：创新点。  
**页结论**：`AI 辅助技术表达与材料整理；性能、正确性和源码结论由真实文件与人工复核确认。`

```text
生成简洁的 AI 使用说明页，标题：“AI 工具使用说明”。中央三层边界，避免机器人、人物或装饰图：第一层青绿“AI 辅助：答辩结构梳理、代码/报告审计、图像提示词、PPT 版面汇编”；第二层深蓝“人工核验：README/源码、metrics.json、性能表、契约与正确性报告”；第三层橙色“禁止替代：不生成性能数字、不伪造运行截图、不替代测试与正确性判断”。底部结论：“新统一 L1-L6 数据必须由真实运行生成并人工复核。”如团队使用过其他 AI 工具，只按真实记录补充，不虚构。
```

---

## 输出命名

整页生成文件保存到 `ppt_work/generated/`：

```text
P03_赛题重述_整页_v03_技术链路.png
P04_技术路线_生图重构_v06.png
…
P10_Task2_Score_Only_生图重构_v06.png
P17_统一测评与改进方向_生图重构_v06.png
P18_核心亮点_生图重构_v06.png
P19_AI工具使用说明_整页_v02.png
```

P15 保存可追溯的 `PNG + SVG + 数据导出 CSV/JSON 摘要`。P09、P11、P14、P16 在统一复测前只保留占位图与 `unified_l1_l6_retest_template.csv`；生成新曲线前逐页检查中文、箭头方向、CPU/GPU 映射、数字、证据角标与安全边距。
