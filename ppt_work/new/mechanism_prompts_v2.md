# 机制页 V2 生图提示词

## 通用约束

Use case: `productivity-visual` / `scientific-educational`

Asset type: 16:9 Chinese technical-defense PPT full-slide PNG, 1672×941.

Input images: each page uses its matching file in
`/home/usr_04/CETC/ppt_work/final_images/` as the style and composition
reference, not as a source of new performance data.

Style: preserve the existing CETC defense-deck visual language: white
background, deep navy title and bottom conclusion strip, vivid blue section
headers, teal GPU/optimized path, orange metrics and path numbering, restrained
red only for the legacy/problem path, thin blue borders, rounded technical
cards, clean vector-like diagrams, high information density, no photographs.

Composition: keep the reference page's header/navigation, 16:9 margins,
three-column technical panels where present, right-side metric cards, and one
deep-navy conclusion band at the bottom. Text must be sharp, correctly spelled,
and placed inside its card; do not invent, round, or alter any numeric value.

Must avoid: redesigning into a flat generic flowchart, decorative 3D effects,
people, logos, watermark, footer, historical-version labels, fake profiler
charts, unsupported speedup claims, and any use of Hopper-only instructions.

Language rule: use Chinese wherever a term has a clear Chinese equivalent.
Keep only unavoidable technical identifiers such as `GPU`, `CPU`, `FFT`,
`Tile`, `Halo`, `H2D`, `D2H`, `E2E`, `CWT` and operator names.

Metrics rule for P06–P08: the right panel must contain exactly three metric
cards and no correctness, shape, case, gain-source, or fallback cards:
`端到端加速比`, `内核加速比`, and `提速比`. Rank the correctness-PASS,
comparable, positive-E2E operator records by CPU→GPU end-to-end speedup and
select the highest operators in descending order for the three pages. Show one
single value only; do not write a scale suffix, range, or `CPU/GPU` in the
right-side card titles. The left and center mechanism diagrams are independent
mechanism explanations and must not be redrawn to match the ranked right-side
operator label.

## P05 — 3 + 2 + 5 技术路线

Reference image: `final_images/P05_技术路线_三加二加五_v11_统一数据.png`.

Primary request: preserve the reference's left–middle–right strong visual
composition and regenerate the page around the current three mechanisms.

Exact text:

- Title: `3 + 2 + 5 技术路线`
- Subtitle: `三类公共算子机制 + 两条应用任务链 + 五类任务级路径`
- Left header: `3 类公共算子机制`
- Mechanism 1: `离线自动调优与形状分派`; detail `精确键 → 候选筛选 → 缓存 / 回退`
- Mechanism 2: `分层 Tile / 扫描 / FFT`; detail `布局、共享内存分块、分层归约与输出写回`
- Mechanism 3: `执行资源与数据流复用`; detail `设备缓冲、工作区、计划、事件与直接拷贝`
- Representative metric: `pulse_compression CPU/GPU E2E 59.17×`
- Middle header: `2 条应用任务链`
- Task 1: `任务一 · 雷达检测`; metric `L6 CPU/GPU E2E 32.53×`
- Task 2: `任务二 · 特征融合与跟踪`; metric `L6 CPU/GPU E2E 1053.33×`
- Right header: `5 类任务级路径`
- Paths: `设备驻留 / 批处理`; `准备与内容缓存`; `融合 / 直接写回`; `并行扫描 / 归约`; `仅评分 / 紧凑输出`
- Conclusion: `公共算子机制提供基础，任务链负责组合、驻留与紧凑输出。`

Diagram requirements: left cards show exact-key dispatch and Tile/Scan/cache
icons; middle cards show 雷达矩阵 → 距离-多普勒图 → 检测 and 帧序列 → 评分带
→ 轨迹; right side shows five numbered orange cards. Use Chinese labels in
the diagrams wherever possible.

## P06 — 算子机制①：离线自动调优与形状感知分派

Reference image: `final_images/P06_访存资源复用_Wiener代表_v07_真实数据.png` (仅借用历史机制③的版式，不借用其编号或内容；本页是当前机制①).

Primary request: retain the reference's left object cards, central technical
process, right metric cards, and bottom conclusion band, but replace the old
Wiener story with the actual offline autotuning mechanism.

Exact text:

- Title: `算子机制①：离线自动调优与形状感知分派` (top-left aligned)
- Subtitle: `有限候选、精确匹配、离线筛选；运行时只查表，不在线试跑。`
- Left header: `输入、完整键与形状分派`
- Cards: `工作负载键` / `算子 / 形状 / 数据类型 / 布局 / 批量 / 语义参数`; `有限候选集` / `线程 / 分块 / 路径 / 计划`; `资源与正确性门` / `工作区 / 误差 / 输入刷新`
- Center header: `离线筛选 → 运行时选择`
- Flow labels: `离线调优`; `候选筛选`; `前三名 / 正式验证`; `优胜者 / 静态路径`; `正确性通过`; `E2E 主指标不降`; `调优缓存`; `运行时`; `分派依据：规模阈值 / 内存布局 / 算法参数 / 平台校验`; `完整调优键`; `键摘要：N×F / dtype / layout`; `完整键字段：family / operator / shape / dtype / layout / batch / semantic`; `形状感知分派`; `大工作量 + 连续布局 → Tile 路径`; `小工作量 → 通用路径`; `需要频域变换 → FFT / R2C`; `扫描或归约 → 并行扫描`; `形状与参数匹配 → 形状特化核`; `直接计算`; `分块共享内存`; `FFT / R2C`; `并行扫描`; `形状特化核`; `缓存未命中 / 设备不匹配 / 显存不足 → 静态或旧路径回退`
- Right header: `代表算子：lombscargle`
- Metric 1: `端到端加速比 194.03×`
- Metric 2: `内核加速比 195.65×`
- Metric 3: `提速比 2.78×`
- Conclusion: `自动调优决定算子路径；不改变公共 API，失败时回退安全路径。`

Diagram requirements: make the left panel a meaningful workload-to-key-to-route
visual, not a decorative icon list: replace the old wiener matrix/window example
with a Lomb–Scargle input sketch showing sample vectors `x / y`, a frequency grid
`f`, and the logical workload shape `N×F`. Do not repeat `N samples × F
frequencies` on all three input rows: label `x` and `y` as `N 个样本`, label `f`
as `F 个频点`, and show one separate note `逻辑工作量：N×F`. Make the key
table explicitly read `lombscargle | N×F | FP32 | contiguous`, and label it as a
key example rather than a complete serialized key. Immediately below or beside
that table, add a large, unmistakable left-side dispatch chain with arrows:
`输入 x / y / f → 完整调优键 → 形状感知分派 → 候选路径`. The `完整调优键`
box must visibly list chips `family / operator / shape / dtype / layout / batch /
semantic` (the two identity fields may be combined into one compact chip);
show `N×F / dtype / layout` as `键摘要`, not as the whole key. Put a separate
small gate `平台 / 设备校验` next to the dispatch diamond, because it validates
the target rather than being a shape field. The dispatch diamond must branch
visibly into `大工作量 + 连续布局 → Tile / 共享内存`, `小工作量 → 直接 / 通用`,
`需要频域变换 → FFT / R2C`, `扫描或归约 → 并行扫描`,
`形状与参数匹配 → 形状特化核`; make clear that these five are the
shape-aware dispatch alternatives and only one route family is selected for this
operator workload, not five serial stages. Do **not** put `静态旧路径` as a
branch of the shape-aware dispatch diamond. Show `静态旧路径` only in the
offline candidate/validation lane and as a separate red safety fallback reached
from `缓存未命中 / 设备不匹配 / 显存不足 / 正确性或 E2E 门失败`. In the center, show
the offline lane filtering candidates and the runtime lane doing
`键摘要 → 形状感知分派 → 选择路径 → 频率点并行计算`.
Add a compact, clearly readable dispatch block before the branch: the full key
fields `family / operator / shape / dtype / layout / batch / semantic` flow into
`形状感知分派`; four decision gates `规模阈值 / 内存布局 / 算法参数 /
平台校验` select one reusable library-level route family from
`直接计算 / 分块共享内存 / FFT·R2C / 并行扫描 / 形状特化核`. Make it clear
that these are candidate path families selected per operator shape, not five
steps executed serially and not a task-level pipeline. The static/legacy path
belongs to offline validation and safety fallback, not to this dispatch set.
The offline lane checks correctness and the CPU→GPU E2E gate, then writes one
cache entry. The runtime lane reads the exact key and dispatches the cached
route; a cache miss, device mismatch, workspace shortage, or OOM must have a
visible red fallback arrow to the static/legacy route. Do not leave any
`wiener`, local mean, window variance, or wiener output labels on this page. The
left key/dispatch is a generic library policy illustration; do not imply that
the current Lomb–Scargle report row has a populated tuning cache entry unless
the data explicitly says so.
Use key-value chips, input-shape diagram, branch arrows, and a small execution
flow that explain the computation; do not use arbitrary charts, unrelated
icons, online benchmarking, or arbitrary kernel generation. Keep the right
panel to the three metric cards above and do not add PASS or case-description
cards there.

## P07 — 算子机制②：分层 Tile、布局与归约重构

Reference image: `final_images/P07_并行归约重构_LombScargle代表_v08_真实数据.png`.

Primary request: preserve the reference's legacy-vs-optimized contrast, central
parallel technical diagram, right metric stack, and bottom conclusion band.

Exact text:

- Title: `算子机制②：分层 Tile、布局与归约重构` (top-left aligned)
- Subtitle: `把重复全局访存和串行归约改写为按形状感知的块内协作路径。`
- Left header: `旧路径：点×通道重复访存`; labels `输入样本 x`; `相位 tap h`; `每个输出重复读取`; `串行 phase 累加`
- Center header: `新路径：点×相位 Tile + 分层归约`; labels `输入样本 Tile`; `相位 tap Tile`; `共享 8×8 twiddle`; `一次加载 → 多通道输出`
- Route chips: `通用路径`; `8 通道点路径`; `按通道数 / 点数选择`
- Right header: `代表算子：wiener`
- Metric 1: `端到端加速比 102.12×`
- Metric 2: `内核加速比 199.70×`
- Metric 3: `提速比 32.92×`
- Conclusion: `Tile、布局与归约共同决定路径；不满足条件的形状保留旧路径。`

Diagram requirements: replace the generic matrix/Halo picture with the actual
channelizer dataflow. On the left, show the legacy `点 × 通道` outputs each
re-reading the same input samples and polyphase taps, with repeated red global
memory arrows and a serial phase accumulation. Keep the left diagram visually
clean: place the `问题来源` explanation in its own unobstructed strip between
the output matrix and the input x/h boxes; do not let arrows, labels, or matrix
cell outlines pass through that strip. Replace the current ambiguous outer-gutter
arrow/circular-icon notation with one explicit compact dataflow inset below or
beside the issue strip: `同一输入样本 x_i` and `同一相位 tap h_t` each flow into
three clearly labeled representative outputs `y_{0,0}`, `y_{1,1}`, and
`y_{P-1,C-1}`. Use two colored source nodes, three output nodes, and short
straight arrows; add the caption `同一 x_i / h_t 被多个输出重复读取`. Beside
this inset, show a separate small sequential strip `phase: t=0 → 1 → … → T-1`
with the label `串行累加，难以并行化`. Do not use unexplained loop icons or
long arrows from the input strips through the problem-source text. The output
matrix must remain readable. In the center, show one
`点 × 相位` input Tile, a shared `相位 tap Tile`, a shared `8×8 twiddle` table,
and multiple teal channel outputs produced from the same loaded data; label the
reduction as `按 phase 归约` and show `一次加载 → 多通道输出`. Add only meaningful
route chips: `通用路径`; `8 通道点路径`; `按通道数 / 点数选择`. The diagram must
explain why loads and twiddle preparation are reused; do not use an unrelated
FFT, Halo, or decorative chart. Keep exactly the three metric cards in the
right panel and do not imply every shape uses the specialized route.

## P08 — 算子机制③：非内核执行开销与执行内资源复用

Reference image: `final_images/P08_形状感知分派_ChannelizePoly代表_v08_真实数据.png`.

Primary request: preserve the reference's large execution comparison, right
metric stack, and bottom conclusion band; use the real correlate direct/FFT
dataflow to explain why kernel speedup and E2E speedup can differ.

Exact text:

- Title: `算子机制③：非内核执行开销与执行内资源复用` (top-left aligned)
- Subtitle: `每轮独立分配与释放；单次执行内部复用中间资源，完整计入 E2E。`
- Left header: `每轮独立资源与执行内复用`
- Resource cards: `输入信号` / `每轮新建 + 完整 H2D`; `模板信号` / `每轮新建 + 完整 H2D`; `packed FFT buffer` / `本轮 forward / inverse 共用`; `forward / inverse plan` / `本轮新建并使用`; `workspace` / `本轮阶段复用，轮末释放`
- Center header: `E2E 时间轴：每轮独立资源，执行内复用`
- Lanes: `每轮独立路径`; `新建输入 → 新分配 buffer → H2D → 新建 plan / workspace → 内核阶段（本轮内复用）→ D2H → 释放`; `执行内复用`; `同一 repeat 内复用 buffer / workspace，跨 repeat 全部释放并重建`
- Protocol note: `每个 warmup/repeat：新建输入、分配容量、创建 plan/event；完整 H2D/compute/D2H 后释放；只允许本轮内部复用。`
- E2E gate: `E2E 主指标优先`; `内核单独变快 ≠ 算子最终有效`
- Right header: `代表算子：vectorstrength`
- Metric 1: `端到端加速比 85.36×`
- Metric 2: `内核加速比 106.76×`
- Metric 3: `提速比 1.73×`
- Conclusion: `非内核优化只有在 CPU→GPU E2E 加速比变大时才保留。`

Diagram requirements: make the left panel show the real correlate inputs and
resources: an input signal, a template signal, a packed FFT buffer, forward /
inverse plan handles, and workspace. Re-layout the left panel into two visually
distinct groups: an upper group titled `每轮独立创建` containing only `输入信号`
and `模板信号`, and a lower group titled `本轮内部复用` containing
`packed FFT buffer`, `forward / inverse plan`, and `workspace`. Remove the old
standalone bottom note `不保留跨轮资源；不做预分配`; do not replace it with
another long policy card. Make the left panel geometry clean and closed: use one
continuous outer panel frame, one complete rounded red frame around the upper
group including its red header, and one complete rounded teal frame around the
lower group including its teal header. Keep uniform inner margins and closed
card borders; do not let the outer frame stop at a card, do not leave broken
vertical lines or dangling corners, and do not overlap group frames with card
borders. Under the strict benchmark protocol, every
warmup/repeat must independently create the logical inputs, allocate device
buffers/workspace, create plan and event handles, perform full H2D/compute/D2H,
and release them before the next iteration. Do not show or imply any resource
cache across repeats. Only within one repeat may a packed FFT buffer or
workspace be reused by multiple stages after the prior stage has finished. In
the center, compare two
meaningful lanes. The grey conventional lane must show `选择 direct/FFT → 每轮
pack / padding → 分配 fft buffer → 建 forward plan ×2 → FFT 频域乘法 → inverse
FFT → crop / 写回`; the teal reuse lane must show `每轮 fresh 输入 H2D → 形状
感知选择 → 复用 fft buffer / forward plan / inverse plan → pack → FFT ×2 → 频域
乘法 → inverse FFT → crop / D2H`. Use arrows to distinguish refreshed data from
cached preparation resources and show the plan key `(FFT size, batch, layout)`
matching the workspace. Use dashed blue arrows only inside the same repeat to
show buffer/workspace reuse, and use solid refresh/allocation arrows at the
start of every repeat. Show an explicit `释放` boundary before the next repeat.
Do not draw arbitrary memory gauges or 15 GiB as a
preallocated block; do not use a decorative chart. Keep exactly the three
metric cards in the right panel; do not add a separate benefit or protocol card
there.

## P12 — 任务一：五类路径组合雷达检测链

Reference image: `final_images/P12_任务一_五类路径公开算子链_v05_中文重构.png`.

Primary request: preserve the reference's teal device-resident main chain,
orange five-path mapping, lower ambgfun side branch, and bottom conclusion.

Exact text:

- Title: `任务一：五类路径组合雷达检测链`
- Subtitle: `公共算子在设备侧连续执行；任务边界只回传检测与验证所需结果。`
- Badge: `Task1 L6 E2E 32.53×`
- Main header: `GPU 设备驻留：公开算子组合链`
- Nodes: `1 脉冲压缩` / `模板 FFT` / `匹配滤波`; `2 脉冲多普勒` / `批量 FFT` / `转置 / 移位`; `3 功率图` / `|RD|²` / `归一化`; `4 CA-CFAR` / `行前缀` / `阈值`; `5 峰值 / 紧凑` / `两阶段` / `检测列表`
- Entry: `主机输入 一次上传`; exit: `紧凑 回传`
- Side branch: `旁路 ambgfun`; `并行矩阵 / FFT 批处理`; `质量分析，不进入检测回传`; `代表算子 CPU/GPU E2E 59.17×`
- Right header: `五类路径映射`
- Paths: `设备驻留` / `一次上传，链尾回传`; `预处理缓存` / `模板、窗口、FFT 计划`; `融合直写` / `打包 / 补零 / 输出复用`; `并行扫描` / `CFAR 前缀、峰值归约`; `紧凑输出` / `检测列表与验证结果`
- Conclusion: `设备驻留、缓存、算子内复用、CFAR 扫描与紧凑输出共同支撑任务一。`

Diagram requirements: keep the six-node semantic chain and make the ambgfun
branch visibly a parallel quality-analysis side path, not a detection output
stage. Keep the L6 CPU/GPU E2E badge visible.

## P14 — 任务二：五类路径构建批量评分与跟踪

Reference image: `final_images/P14_任务二_五类路径评分流程_v12_初版保留主内容.png`.

Primary request: preserve the reference's grey CPU reference lane, teal GPU
batch-score lane, orange five-path panel, and bottom conclusion band.

Exact text:

- Title: `任务二：五类路径构建批量评分与跟踪`
- Subtitle: `从逐帧全量中间张量转向设备驻留、批量评分和紧凑状态输出。`
- Badge: `Task2 L6 E2E 1053.33×`
- CPU header: `CPU 参考路径：逐帧完整中间结果`; nodes `帧`; `完整相关`; `完整时频图`; `完整 CWT`; `主机跟踪`; note `完整张量 / 批量=1 / 主机后处理`
- GPU header: `GPU 路径：设备批量=8 + 仅评分`; chain `一次 H2D`; `设备批量 B=8`; `滤波 / 解调评分`; `相关评分`; `时频带评分`; `CWT 最大评分`; `并行归约：加权 / 平滑`; `峰值 + Kalman 紧凑输出`
- Right header: `五类路径说明`
- Paths (no per-operator speedup numbers in this panel): `设备驻留 / 批处理` / `一次上传，设备侧连续评分`; `预处理与计划复用` / `模板、窗口、FFT 计划复用`; `直接写入评分` / `只写评分，不物化完整张量`; `并行归约` / `加权、平滑与峰值归约`; `仅评分 / 紧凑输出` / `峰值、状态与轨迹回传`
- Conclusion: `批量评分减少全量张量物化，输出聚焦评分、峰值、状态与轨迹。`

Diagram requirements: strongly separate the grey CPU full-materialization lane
from the teal GPU score-only lane. The B=8 device batch and the five orange
path cards must remain legible. Do not place per-operator speedup numbers next
to the five paths; the only task-level speedup is the top-right badge
`Task2 L6 E2E 1053.33×`.
