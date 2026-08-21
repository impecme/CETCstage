# 技术路线与任务机制页 V3 生图提示词

本组只重生成 P05、P12、P14；P06–P08 算子机制页和性能展示页不改。

## 通用约束

Use case: `productivity-visual` / `scientific-educational`

Asset type: 16:9 Chinese technical-defense PPT full-slide PNG, 1672×941.

Input images: each page's current PNG in `/home/usr_04/CETC/ppt_work/new/` is
the edit target; the matching image in `final_images/` is only a style and
composition reference. Preserve the established CETC defense-deck style:
white background, deep navy title and bottom conclusion band, blue section
headers, teal GPU path, orange numbered path cards, red only for warnings or
CPU/legacy contrast, thin blue borders, rounded technical cards, clean
vector-like diagrams, high information density.

All Chinese labels must be rendered verbatim, sharp and readable. Keep only
necessary technical identifiers such as `GPU`, `CPU`, `FFT`, `H2D`, `D2H`,
`E2E`, `CA-CFAR`, `CWT`, `Kalman`, `B=8`, `ambgfun` and operator names.
Do not invent numbers, operator speedups, before/after task speedups, or
cross-repeat cache claims. Task badges use the current `autotune` task
summary: Task1 L6 CPU→GPU E2E `7.49×`; Task2 L6 CPU→GPU E2E `481.37×`.
These are CPU→GPU E2E speedups, not GPU-optimized-before/after ratios.

Avoid photographs, people, logos, watermarks, fake profiler charts, unrelated
icons, Hopper-only instructions, arbitrary decorative graphics, spaghetti
arrows, tiny unreadable text, English-only labels, and any implication that
all five task paths execute as five serial stages.

## P05 — 3 + 2 + 5 技术路线

Reference image: `final_images/P05_技术路线_三加二加五_v11_统一数据.png`.

Primary request: edit the current P05 page while preserving its strong
left–middle–right composition, three blue section headers, two task cards and
five orange route cards. Correct the mechanism wording and task metrics to the
current data protocol. Remove the stale individual-operator performance strip;
this overview page must not present `pulse_compression 59.17×` or any other
operator metric.

Exact text:

- Title: `3 + 2 + 5 技术路线`
- Subtitle: `三类公共算子机制 + 两条应用任务链 + 五类任务级路径`
- Left header: `3 类公共算子机制`
- Mechanism 1: `形状感知分派`; detail `完整键 → 离线筛选 → 运行时查表 → 安全回退`
- Mechanism 2: `分层 Tile 与并行归约`; detail `布局 / 共享内存 / FFT·R2C / 扫描`
- Mechanism 3: `E2E 开销与执行内资源`; detail `每轮新输入与 H2D；本轮内部复用；D2H 完整计时`
- Left footer: `公共算子：all81 × L1–L6；正确性与输入刷新均纳入门禁`
- Middle header: `2 条应用任务链`
- Task 1: `任务一 · 雷达检测`; badge `当前 L6 CPU→GPU E2E 7.49×`
- Task 2: `任务二 · 特征评分与跟踪`; badge `当前 L6 CPU→GPU E2E 481.37×`
- Task 1 diagram: `输入构造 → 脉冲压缩 → 脉冲多普勒 → 功率图 → CA-CFAR → 检测列表`
- Task 2 diagram: `设备批量 → 多路评分 → 并行归约 → 峰值 / Kalman → 紧凑状态`
- Right header: `5 类任务级路径`
- Path 1: `设备驻留 / 一次上传，链尾回传`
- Path 2: `本轮准备 / 模板、窗口、计划统一准备`
- Path 3: `算子内直写 / 打包、补零、输出复用`
- Path 4: `并行扫描 / CFAR 前缀、峰值归约`
- Path 5: `仅评分 / 评分、峰值、状态紧凑输出`
- Conclusion: `公共算子机制提供基础，任务链负责组合、驻留与紧凑输出。`

Diagram requirements: draw mechanism 1 with a key and branching dispatch,
mechanism 2 with a tiled block and reduction tree, and mechanism 3 with a
fresh-input/H2D boundary plus a small within-one-execution resource reuse
symbol. Explicitly show `跨 repeat 不复用` as a small protocol note, not as a
large metric card. The two task cards must be visually distinct: Task1 is a
radar matrix → range–Doppler map → CFAR/detection flow; Task2 is frame batch →
score strips → peak/state trajectory. Use one short arrow per stage and keep
the five path cards as a legend, not a second serial pipeline. Do not show
GPU-optimization-before/after numbers because no paired task-level baseline
exists in the official `autotune` + `baseline` sources.

## P12 — 任务一：设备驻留与五类路径组合雷达检测链

Reference image: `final_images/P12_任务一_五类路径公开算子链_v05_中文重构.png`.

Primary request: edit the current P12 page in the same style. Make the main
chain represent the actual Task1 stages recorded in
`data/reports/autotune/demo/task1_radar/stages/L6.csv`: input construction,
pulse compression, pulse Doppler, power map, CA-CFAR, final detection and
final output. Keep `ambgfun` as a visibly separate quality-analysis side path.
Use the current CPU→GPU task metric only; do not show an invented task
GPU-before/after ratio or a stale operator metric.

Exact text:

- Title: `任务一：设备驻留与五类路径组合雷达检测链`
- Subtitle: `每轮独立输入与 H2D；设备侧连续完成检测主链，跨 repeat 不复用资源。`
- Badge: `当前 L6 CPU→GPU E2E 7.49×`
- Main header: `GPU 设备驻留：任务实际执行链`
- Entry: `主机输入`; `一次上传`
- Node 1: `脉冲压缩`; detail `模板 FFT / 匹配滤波`
- Node 2: `脉冲多普勒`; detail `批量 FFT / 转置·移位`
- Node 3: `功率图`; detail `|RD|² / 归一化`
- Node 4: `CA-CFAR`; detail `行前缀 / 阈值`
- Node 5: `峰值与紧凑输出`; detail `detect_peak / 检测列表`
- Exit: `链尾回传`; `检测与验证结果`
- Side branch: `旁路 ambgfun`; `并行矩阵 / FFT 批处理`; `质量分析，不进入检测回传`
- Right header: `五类路径映射`
- Path 1: `设备驻留`; detail `一次上传，链尾回传`
- Path 2: `本轮准备`; detail `模板、窗口、计划统一准备`
- Path 3: `算子内直写`; detail `打包、补零、输出复用`
- Path 4: `并行扫描`; detail `CFAR 前缀、峰值归约`
- Path 5: `紧凑输出`; detail `检测列表与验证结果`
- Protocol note: `输入 / buffer / plan / event：每轮独立创建；只允许本轮内部复用`
- Conclusion: `设备驻留、执行内资源、算子直写、CFAR 扫描与紧凑输出共同支撑任务一。`

Diagram requirements: use a large teal rounded frame for the main GPU chain,
with five evenly sized nodes and straight arrows. Put input construction in
the entry area rather than silently hiding it. Put `ambgfun` below the main
frame inside a dashed teal side branch with an arrow labelled `旁路质量分析`;
its output must not connect to `检测列表`. Connect the five orange path cards
to short alignment markers or a single bracket so their lines do not cross the
main chain. Keep the badge at top right. Avoid writing `CPU/GPU` in any path
card and avoid any individual operator speedup on this mechanism page.

## P14 — 任务二：设备批量评分与紧凑跟踪

Reference image: `final_images/P14_任务二_五类路径评分流程_v12_初版保留主内容.png`.

Primary request: edit the current P14 page while preserving the grey CPU
reference lane, teal GPU lane, orange path panel and bottom conclusion band.
Align the GPU lane with the actual Task2 stages in
`data/reports/autotune/demo/task2_features/stages/L6.csv`: filter, demod,
correlate, spectrogram, CWT, feature fusion, measurement conversion and
Kalman. Clearly contrast full intermediate-tensor materialization with
score-only processing. Do not show task GPU-before/after numbers.

Exact text:

- Title: `任务二：设备批量评分与紧凑跟踪`
- Subtitle: `从逐帧全量中间张量转向设备批量评分、并行归约和紧凑状态输出。`
- Badge: `当前 L6 CPU→GPU E2E 481.37×`
- CPU header: `CPU 参考路径：逐帧完整中间结果`
- CPU chain: `帧序列 → 完整相关 → 完整时频图 → 完整 CWT → 主机后处理 → Kalman 跟踪`
- CPU note: `完整张量 / 批量=1 / 主机后处理`
- GPU header: `GPU 路径：设备批量 B=8 + 仅评分`
- GPU chain: `一次 H2D → 设备批量 B=8 → 滤波 / 解调评分 → 相关评分 → 时频带评分 → CWT 最大评分 → 特征融合 / 并行归约 → 峰值 + Kalman 紧凑输出`
- Right header: `五类路径说明`
- Path 1: `设备驻留 / 批处理`; detail `一次上传，设备侧连续评分`
- Path 2: `本轮准备`; detail `窗口、模板、计划统一准备`
- Path 3: `只写评分`; detail `不物化完整中间张量`
- Path 4: `并行归约`; detail `加权、平滑、峰值归约`
- Path 5: `紧凑输出`; detail `评分、峰值、状态、轨迹回传`
- Protocol note: `每轮 fresh 输入与完整 H2D / D2H；跨 repeat 不复用资源`
- Conclusion: `批量评分减少全量张量物化，输出聚焦评分、峰值、状态与轨迹。`

Diagram requirements: keep the CPU lane grey and the GPU lane teal. The CPU
lane must visibly create full 2D/3D tensor blocks; the GPU lane must visibly
create several compact score strips and only then a peak/state/track output.
Use `B=8` as a batch annotation, not as a claim that eight independent task
chains execute serially. Use straight arrows, aligned boxes and a clear
vertical separation between lanes. The five orange cards explain mechanisms
only; do not place operator speedups beside them. The only performance number
on this page is the top-right current Task2 CPU→GPU E2E badge.
