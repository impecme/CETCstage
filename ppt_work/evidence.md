# 比赛答辩 PPT 技术内容证据审计（当前仓库版）

> 审计对象：`/home/usr_04/CETC` 当前工作树
> 审计日期：2026-07-20
> 用途：为比赛答辩 PPT 提供可追溯的技术事实、数据口径、风险边界和素材索引。
> 本轮动作：重新阅读当前 README、最终说明文档、公共头文件、CPU/ZQ500 源码、两个任务、测试契约、根脚本和 `data/reports/`；仅更新 `ppt_work/`，未修改项目源码。
> 运行边界：本机未重新执行 ZQ500 构建或 GPU 测试；本文的运行数字来自仓库内已发布报告，派生统计均明确标注。

## 0. 审计结论与证据边界

### 0.1 最重要的五个结论

1. 当前仓库已经从“按版本堆放脚本和报告”收束为稳定交付结构：公共 API、共享语义、CPU reference、ZQ500 GPU 后端、两个任务、契约测试、根级构建/验证脚本和单一当前报告目录。
2. 最适合本次技术答辩的故事不是逐个介绍 81 个算子，而是：**公共算子库的通用优化机制 → 三类代表性算子难题 → 两条应用任务的组合优化 → 当前性能、边界和回退决策**。
3. 已发布运行 `current-20260720-task-optimized-l6` 证明了 81/81 算子、2/2 任务、14/14 计算步骤和 12/12 个 L1-L6 任务运行通过；81 个算子均有性能入口，共 86 条结构化 performance case，其中 78 条为独立 `case_detail`、8 条为 `summary_aggregate`。
4. 报告包 `FILES.sha256` 338/338 校验通过；当前复核时 `SOURCE_FILES.sha256` 为 691/695 匹配，差异包含两个 task demo、`docs/BUILD_AND_RUN.md` 与一份探索脚本。因此报告数字必须标为“2026-07-20 已发布运行快照”，不可冒充为未冻结当前工作树的实时性能。14/14 个正式任务步骤已有 GPU event 计时；provenance 仍为 `git_commit=null`、`tracked_worktree_dirty=null`。
5. 当前代码已经解决多算子任务中最主要的重复 Host/Device 搬运：C++17 `std::variant` 让同一 GPU API 接受 Host 或 Device 对象，Device 输出继续持有显存并可直接作为下游输入，任务只在首端上传、尾端 `.get()`。这不是 Unified Memory 或零拷贝；容量复用、语义对象复用和重复 Host 输入缓存是另外三类机制，必须分开说明。

### 0.2 三层证据模型

| 层级 | 事实源 | 可以证明 | 不能证明 |
|---|---|---|---|
| C：当前代码事实 | `README.md`、`CMakeLists.txt`、`include/`、`src/`、`demo/`、`tests/`、`scripts/` | 当前架构、接口、算法路径、分派条件、缓存和融合实现 | 未经执行不能证明当前工作树的性能与正确性 |
| R：已发布运行快照 | `data/reports/`，run `current-20260720-task-optimized-l6` | 与报告记录的 695 文件内容指纹一致的 81/81、任务、误差、E2E/GPU event 计时、L1-L6 和结构化门禁 | 当前复核为 691/695；两个 task demo 已漂移，不能证明未冻结当前工作树的性能 |
| H：冻结历史优化 | `docs/PERFORMANCE.md`、`docs/VERSION_HISTORY.md`、`docs/PROJECT_LEDGER_notsub.md` | V5.5/V6/V7 的优化前后、候选保留/回退和历史演示结果 | 不能冒充当前报告，也不能把不同协议拼成一次实验 |

PPT 中建议用角标区分：`[当前源码]`、`[RUN 2026-07-20 已发布快照]`、`[历史 A/B]`。

### 0.3 当前报告完整性与源码一致性

- 报告入口：`data/reports/summary.md`、`summary.json`、`provenance.json`。
- 运行编号：`current-20260720-task-optimized-l6`。
- 设备：`ZQ500-Q QUAD-0`，总显存字段为 16384 MiB。
- 报告包共 339 个普通文件；`FILES.sha256` 覆盖其余 338 个文件并可通过内部校验。
- 报告记录的源码文件数为 695，源码内容指纹为 `b3374633779c22b94c6b657b08baa3650a69239149329816fa90d4c2263c774e`。本轮复核为 691/695：`demo/task1_radar/task1_radar_demo.cpp`、`demo/task2_features/task2_features_demo.cpp`、`docs/BUILD_AND_RUN.md`、`scripts/explore_task_acceleration.sh` 已与报告快照不一致。正式答辩前必须在最终 commit 上重新生成或恢复一致性。
- `validation/task_step_reports.json` 显示 14/14 步同时具备 error 和 GPU event 计时；Task2 `measurement_conversion` 的 `0 ms` 是“浅层 Device storage 交接、不调用 CUDA”的合法值，不是缺失。
- `gpu_kernel_ms` 的准确含义是两个 GPU event 之间 default stream 上排队工作的耗时。复合步骤可能包含 memcpy、FFT/BLAS 库调用和多个 kernel，不能把它解释成某个单 kernel 的 profiler 时间。
- `provenance.json` 记录 `git_commit: null`、`tracked_worktree_dirty: null`。当前 Git 工作树本身并不干净，且新报告相对仓库提交为修改状态；这不影响内容哈希的一致性，但正式答辩版本仍应把源码、报告和制图脚本冻结到同一 commit。

### 0.4 必须避免的过期表述

- **答辩任务性能页的口径已更新**：正式 `task*/scales/L1…L6` 使用同一算法配置；原 `final-input` 已作为 L6，L1～L5 冻结算法、分块/批处理和阈值，只改变输入规模。P04、P09、P11、P14、P16 使用正式 L6 或正式曲线；旧 2026-07-20 task scale/final 数据已移至仓库外审计备份，不作为正式端到端效果。旧数值仅保留在本审计文档中，用于说明为什么不能混画。
- 测评计划、路径和直接导出公式见 `ppt_work/scale_retest_plan.md`：`speedup = CPU total / GPU total`。分块、Halo、CFAR 阈值与 batch/shape 的进一步搜索属于正式基线之后的独立 A/B，不属于本轮规模曲线。
- 不再引用已经删除的 `data/reports/zhongkexin/*`、`docs/performance/*`、`scripts/test/benchmark_all_ops_scales.py`、`scripts/build/build_v1.sh` 等旧路径。
- 不再引用旧运行 `current-20260719-165100`、旧指纹 `4944706f...`、73/81“无性能入口”或“14 个 task kernel 字段为空”等已经被当前报告替代的结论。
- 不把历史 V6 的 `486/486`、旧 71/81 L6、旧全库中位加速或 V7 的 Task 时间写成“当前代码结果”。它们只能作为 `docs/PERFORMANCE.md` 中明确标版本的历史事实。
- 不声称存在“通用自动调参框架”。当前真实实现是统一基础线程配置、shape/阶数/窗口感知的多路径分派，以及以 A/B 门禁决定保留或回退。
- 不声称 Task2 的 8 步全部由公共算子直接完成。契约明确为 8 个 `mixed` 步骤，GPU 主计时路径包含任务私有 batched/AOT/score-only helper。
- 不声称所有 dtype 都有独立原生 kernel。当前是逐算子兼容契约，其中大量 FP16/整数 edge 通过 FP32 或扩展累加实现。
- 不把设备驻留称为 Unified Memory、零拷贝或“C++ 自动搬运”。当前是 API 根据 `std::variant` 的实际分支显式选择复用 Device 数据或执行 H2D，并由调用方在需要 Host 结果时显式 `.get()`。
- 不把 DeviceStorage cache、模块 workspace/prepared cache 和 Host 内容缓存统称为“一个缓冲池”：三者分别复用容量、复用已准备语义对象、复用重复 Host 输入的已上传副本。
- 不声称已有生产级 CUDA Graph、多 stream overlap 或在线 autotuner。当前任务为单链顺序执行，shape-aware 阈值由代码显式分派。
- 不绘制 Roofline：当前仓库没有算术强度、带宽计数器、峰值带宽/峰值 FLOPS 的同协议测量。

---

## 1. 项目整体目标

本项目面向中科芯 ZQ500 国产 GPU，以 C++17 实现一套信号处理算子库。工程同时提供 CPU reference 与 ZQ500 GPU 后端，覆盖 12 个功能模块、81 个注册算子，并通过雷达处理和多域特征跟踪两条端到端任务验证这些算子能够组合成真实应用链路。

答辩可使用的一句话目标：

> 在 ZQ500 上完成 81 个信号处理算子的接口、数值与性能迁移，并用 CPU/GPU 双后端、两条端到端任务和可追溯报告形成工程闭环。

项目解决四个层次的问题：

- **功能迁移**：把波形、窗函数、滤波、频谱、雷达、小波、相关、解调、估计和峰值检测能力迁移到 ZQ500。
- **并行算法重构**：针对邻域访存、递归依赖、FFT 冗余、固定开销和小矩阵等不同瓶颈设计不同 GPU 路径。
- **应用组合**：让算子结果保持 device resident，并在 Task1/Task2 中执行批处理、融合和任务特化。
- **证据化交付**：用机器契约、81 个独立测试、结构化性能 case、14 步任务误差和 L1-L6 运行报告证明实现范围与边界。

主要证据：`README.md`、`docs/ARCHITECTURE.md`、`tests/contracts/operator_sets.json`、`data/reports/summary.json`。

---

## 2. 代码整体架构

### 2.1 当前真实目录结构

```text
CETC/
├── include/cusignal/             公共 C++ API、结果结构、core host/device 类型
├── src/common/                   CPU/GPU 共享参数、shape、axis 和数学语义
├── src/cpu/                      12 个模块的 CPU reference
├── src/zhongkexin/               12 个模块的 ZQ500 kernel、workspace 和平台库调用
├── demo/common/                  两任务共用的分步计时与报告模型
├── demo/task1_radar/             Task1：6 个正式计算步骤
├── demo/task2_features/          Task2：8 个正式计算步骤及 GPU 专用 helper
├── tests/unit/                   core 与 81 个注册算子的独立测试
├── tests/contracts/              all81、dtype、任务步骤机器契约
├── tests/tools/                  接口、dtype、任务和报告审计工具
├── tests/platform/               ZQ500 SDK/API 兼容夹具和探针
├── scripts/*.sh                  build/test/demo/validate/sync/pull/clean 入口
├── scripts/finalize_reports.py   验证报告强校验、staging rename 与异常回滚
├── data/reference/               固定参考输入、输出和 manifest
├── data/generated/               可再生任务输入及规模数据
├── data/.reports_staging/        被忽略的运行期报告暂存
├── data/reports/                 当前已发布的 units/demo/validation 报告
├── third_party/fftw/             固定版本 CPU FFTW 依赖
└── docs/                         当前架构、构建、性能、类型和交付说明
```

### 2.2 主要模块、调用关系和系统作用

| 模块 | 当前路径 | 主要功能 | 上游 / 下游 | 系统作用 |
|---|---|---|---|---|
| 公共 API | `include/cusignal/<module>/`、`cusignal.hpp` | 声明算子、参数和具名结果结构 | 上游：demo/测试/用户；下游：CPU/GPU 实现 | 稳定外部契约 |
| Core 类型与内存 | `include/cusignal/core/types.hpp` | `Tensor`、`DeviceSignal`、`DeviceArray`、host/device variant、DeviceStorage cache | 上游：全部 GPU 算子；下游：ZQ runtime | 数据所有权、H2D/D2H 与通用缓冲复用 |
| 共享语义 | `src/common/*_detail.hpp` | 参数合法性、axis/shape、窗口、频率轴和辅助算法 | 上游：两后端；下游：标准 C++ | 保证 CPU/GPU 语义一致 |
| CPU reference | `src/cpu/*.cpp` | 81 算子的对照实现，FFT-heavy 路径使用 FFTW | 上游：测试和任务；下游：FFTW/host | 正确性和 CPU 性能基线 |
| ZQ500 GPU 后端 | `src/zhongkexin/*.cu` | kernel、FFT/BLAS/Solver、workspace、plan 和 prepared cache | 上游：API/任务/测试；下游：ZQ500 SDK | 并行执行主体 |
| Task1 | `demo/task1_radar/task1_radar_demo.cpp` | 雷达输入、6 步公开算子链、分步误差和检测结果 | 上游：`scripts/demo.sh`；下游：radartools | 证明公共算子可直接组合 |
| Task2 | `demo/task2_features/*` | 多帧滤波、解调、相关、频谱、小波、融合与跟踪 | 上游：`scripts/demo.sh`；下游：公开算子 + 私有 batched helper | 证明应用特化与跨域组合 |
| 单元与契约测试 | `tests/unit/`、`tests/contracts/`、`tests/tools/` | 81 注册、接口、dtype、步骤和报告 schema | 上游：验证脚本；下游：可执行测试/JSON | 防止覆盖、语义和报告缺口 |
| 平台兼容与探针 | `include/cusignal/core/platform_zx_gpu_*`、`tests/platform/` | 集中部分 runtime/error helper，提供 SDK compile/runtime probe 与可选 fixture 审计 | 上游：GPU 后端/CMake；下游：SDK | 降低部分平台差异；后端仍直接耦合 ZQ500 CUDA-like library ABI |
| 构建与验证 | `scripts/build.sh`、`test_operators.sh`、`demo.sh`、`validate.sh` | 依赖检查、构建、81 算子、L1-L6 任务和审计 | 上游：开发/交付；下游：CMake/测试 | 单一可复现入口 |
| 报告发布 | `scripts/finalize_reports.py`、`data/reports/` | 强校验输入、生成摘要/哈希，staging/backup rename 并在异常时回滚 | 上游：完整验证；下游：PPT/交付 | 证据闭环；非严格单操作原子替换 |

### 2.3 构建目标和依赖关系

顶层 `CMakeLists.txt` 只接受 `CUSIGNAL_PLATFORM=ZHONGKEXIN`：

```text
FFTW ───────────────→ cusignal_cpu
                        ↑ public link
ZQ runtime/FFT/BLAS/    │
Solver + .cu sources → cusignal_zx_gpu
                        ├→ task1_radar_demo
                        ├→ task2_features_demo
                        └→ 81 unit targets + platform tests
```

- CPU 和 GPU 各显式列出 12 个模块源文件，避免目录变化导致隐式收集。
- `demo/task2_features/task2_features_zx_gpu.cu` 当前被编入 `cusignal_zx_gpu`，说明 Task2 专用 GPU helper 与库目标存在工程耦合；这应在架构图中明确，而不是隐藏。
- ZQ500 `.cu` 由 `dlcc -x cuda --cuda-gpu-arch=dlgput64` 作为 C++ 源编译。
- GPU 库链接 ZQ runtime、FFT、BLAS、Solver 和 DLEOL；CPU 库链接固定离线 FFTW。

证据：`CMakeLists.txt:3`、`:195`、`:211`、`:226`、`:250`、`:261`、`:298`。

### 2.4 公共数据和内存模型

当前实现包含四个目的不同、相互配合的层次。

#### A. Host/Device 双态接口与设备驻留：消除算子链中的往返搬运

- `RealSignalLike`、`ComplexSignalLike`、`RealArrayLike` 等由 C++17 `std::variant<HostType, DeviceType>` 定义。
- `core::as_device_signal/array` 先用 `std::get_if` 判断实际分支：若已经是 `ZxGpu*`，直接返回同一 Device 对象；只有 Host 分支才上传到调用者提供的 workspace storage。
- GPU 算子返回 `DeviceSignal/DeviceArray`，数据不会在函数返回时自动转成 Host。下一个 GPU 算子可以直接接收这一结果；只有调用 `.get()` 才执行 D2H。
- `DeviceSignal/DeviceArray` 内部使用 `std::shared_ptr<DeviceStorage<T>>` 管理所有权，因此按值传递或赋值可共享同一块 Device storage。Task2 的 `measurement_values = peak_track` 就是浅层共享，不会复制整条轨迹。

真实调用逻辑为：

```text
Host input
  → 第一个 GPU API：variant 命中 Host → H2D 一次
  → DeviceArray output
  → 后续 GPU API：variant 命中 Device → 复用 device pointer
  → DeviceArray output ...
  → 结果验证/落盘：显式 .get() → D2H 一次
```

Task1 在 `task1_radar_demo.cpp:1221` 左右上传输入，`:1236`～`:1282` 让压缩、Doppler、功率、CFAR、模糊函数和峰值检测保持 Device resident，`:1287` 后统一 materialize。Task2 在 `task2_features_demo.cpp:1660` 左右上传，`:1894`～`:2103` 运行 batched score/融合/跟踪链，`:2106` 后统一 materialize。

#### B. RAII 共享所有权与容量缓存：减少释放风险和重复分配

- `DeviceStorage` 由 RAII 对象托管，复制 Device 容器共享所有权；最后一个引用释放时才进入回收逻辑。
- core cache 是每个元素类型 `T`、每个 Host 线程一份 `thread_local DeviceStorageCache<T>`；同一 vector 可保存不同 device 的 block，命中时再按 `device_id` 过滤，并用线性 best-fit 选择最小可容纳 block。
- 默认上限为每类型、每线程 cache 8 blocks、512 MiB，单 block 256 MiB；不是进程全局 512 MiB，也不是按 device 独立建桶。环境变量可以关闭或调节。
- 它复用的是“容量”，不知道窗口、FFT 长度或数据内容；扩大容量四算子聚合仅改善 `0.0958%`，说明不能把“占更多显存”当成主要优化。

#### C. 模块 workspace / prepared cache：复用语义不变的准备结果

- 各模块维护 `thread_local` workspace，但其中要区分三类对象：按 capacity 复用的 scratch、单槽 `ensure(n,batch)` 式 library plan reuse，以及窗口/频率轴/模板 FFT 等 prepared-result cache。
- Host 内容 cache 使用精确内容 key；部分只读 Device prepared cache 使用 pointer identity + shape/size。后者依赖调用期间输入不原地变值，否则存在 stale-hit 风险；多数 plan key 也以当前单 device/default stream 为前提。
- 这层消除的是重复 setup 或预计算，不等价于 DeviceStorage 容量缓存。Periodogram setup cache 的历史 A/B 为 `0.659052 → 0.38725 ms`，E2E 下降 `41.24%`，而 kernel 基本不变。

#### D. 重复 Host 输入的精确内容缓存：优化独立 API 的反复调用

- Pulse compression 和 MVDR 等路径在输入仍由 Host API 传入、且连续调用内容完全相同时，比较 shape/size/内容或精确 key，命中后复用先前上传的 Device 副本。它们是每线程单槽 cache，同时保留最后一份 Host 内容和 Device 副本。
- 该机制是对 benchmark/重复独立调用的补充；任务主链已经预先上传并使用 Device variant，不依赖它来维持驻留。
- 冷启动、一次性调用、输入内容变化、来自 Device、超出容量条件或显式 bypass 时必须走正常准备路径。历史 A/B 中 MVDR Host cache 为 `11.111 → 2.39885 ms`，下降 `78.41%`；不能外推成所有 MVDR 调用都会获得该收益。

四层关系可以画成两条正交轴：

```text
数据流：Host/Device variant → Device-resident chain → 显式 materialize
资源流：RAII ownership → capacity cache → semantic/prepared cache
重复 Host 调用旁路：exact-content hit → reuse uploaded device copy
```

边界：这不是 Unified Memory 或 host/device 同地址零拷贝；H2D/D2H 当前使用同步 copy，没有 pinned-memory/async overlap。首次 Host 输入仍需要 H2D，最终 Host 消费仍需要 D2H。Device 容器是浅共享而非 copy-on-write，别名写入会影响同一 payload，也不代表跨 stream 自动同步。部分内部路径仍有小规模回传，例如 Wiener noise 标量、filter design 的 device 参数、CWT widths、spectral cache miss 的 window scale、Task2 小型 B-spline/window table，以及部分 filtering gust CPU fallback。

证据：`include/cusignal/core/types.hpp:311`～`:547`、`:601`、`:659`、`:722`、`:734`、`:800`、`:866`、`:873`、`:923`；`include/cusignal/core/helpers.hpp:538`～`:652`；`src/zhongkexin/radartools.cu:492`、`:1781`、`:2601`；上述两个任务 demo。

### 2.5 验证与报告调用链

```text
scripts/validate.sh
  → scripts/build.sh
  → 静态接口 / dtype / 算子集合 / 任务契约 / 平台审计
  → scripts/test_operators.sh（81 个独立目标）
  → scripts/demo.sh --scale-sweep（Task1/Task2, L1-L6 + final）
  → data/.reports_staging/
  → scripts/finalize_reports.py 强校验
  → staging 校验后 rename 发布 data/reports/ + hashes，异常时恢复 backup
```

任一发布前强检查失败时 finalizer 不进入替换；发布 rename 异常时尝试恢复 backup。这个 staged validation + rollback 机制可作为工程亮点，但两次 rename 之间 output path 会短暂不存在，不能称为严格原子目录替换。

---

## 3. 算子清单

### 3.1 全部 81 个注册算子

机器事实源为 `tests/contracts/operator_sets.json`；81 是独立测试/benchmark 条目数，不包含 Task1 后加的 `fftshift_rows`、`power_map`、`detect_peak`、`pulse_doppler_shifted` 等 public helper。

| 功能模块 | 数量 | 注册算子 |
|---|---:|---|
| `waveforms` | 5 | `chirp`, `gausspulse`, `sawtooth`, `square`, `unit_impulse` |
| `bsplines` | 3 | `cubic`, `quadratic`, `gauss_spline` |
| `windows` | 23 | `get_window`, `barthann`, `bartlett`, `blackman`, `blackmanharris`, `bohman`, `boxcar`, `chebwin`, `cosine`, `exponential`, `flattop`, `gaussian`, `general_cosine`, `general_gaussian`, `general_hamming`, `hamming`, `hann`, `kaiser`, `nuttall`, `parzen`, `taylor`, `triang`, `tukey` |
| `filter_design` | 5 | `kaiser_beta`, `kaiser_atten`, `cmplx_sort`, `firwin`, `firwin2` |
| `filtering` | 17 | `wiener`, `firfilter`, `lfilter`, `firfilter_zi`, `lfilter_zi`, `firfilter2`, `filtfilt`, `sosfilt`, `hilbert`, `hilbert2`, `detrend`, `freq_shift`, `channelize_poly`, `decimate`, `resample`, `resample_poly`, `upfirdn` |
| `radartools` | 6 | `pulse_compression`, `pulse_doppler`, `ambgfun`, `cfar_alpha`, `ca_cfar`, `mvdr` |
| `spectral` | 9 | `lombscargle`, `periodogram`, `welch`, `csd`, `spectrogram`, `stft`, `istft`, `coherence`, `vectorstrength` |
| `wavelets` | 5 | `qmf`, `morlet`, `ricker`, `morlet2`, `cwt` |
| `correlate` | 3 | `correlate`, `correlate2d`, `correlation_lags` |
| `demod` | 1 | `fm_demod` |
| `estimation` | 1 | `kalman_filter` |
| `peak_finding` | 3 | `argrelextrema`, `argrelmin`, `argrelmax` |

### 3.2 按并行结构分类

| 并行结构 | 代表算子 | 主要 GPU 方法 | 典型限制 |
|---|---|---|---|
| 点独立生成 | windows、waveforms、B-spline | 每线程写一个或成对输出、direct write | 小规模由 launch 固定成本主导 |
| 邻域/stencil | Wiener、FIR、CWT、CFAR | shared tile、Halo、积分图、分块卷积 | shared memory、边界分支、窗口尺寸 |
| 递归状态 | lfilter、filtfilt、sosfilt、Kalman | affine prefix scan、按 line 并行、单 launch 内串行 | 通用高阶/多线仍受依赖限制 |
| FFT 管线 | periodogram、Welch、STFT、pulse compression、ambgfun | R2C/C2C、batch、plan cache、输出融合 | ZQ500 FFT 点数/数值路径限制 |
| 归约/选择 | lombscargle、vectorstrength、detect_peak、peak finding | block reduction、两阶段归约 | 小输出时固定开销明显 |
| 小矩阵 | MVDR、Kalman | 三角协方差、8x8 特化、BLAS/Solver | 库调用和 H2D/D2H 固定成本 |
| 元数据/标量 | kaiser_beta、kaiser_atten、cfar_alpha、lags | GPU 兼容入口或小 kernel | CPU 极快，GPU E2E 往往不占优 |

### 3.3 公共优化机制：真实边界

1. **双态数据流与设备驻留**：`std::variant` 区分 Host/Device 输入，Device 结果继续传给下游，只在任务边界显式 materialize。
2. **分层资源复用**：core best-fit cache 复用容量；模块 scratch、library plan 和 prepared-result cache 分别复用不同对象；重复 Host 调用可用精确内容缓存复用已上传副本。
3. **形状感知多路径分派**：以 256 线程为常用基础，按 rank、axis 连续性、阶数、窗口、FFT 长度和工作量选择 direct/tiled/FFT/scan 路径。
4. **按算法结构重写**：邻域算子用 shared tile/Halo，低阶递归用 affine scan，频谱算子用 R2C/batch/fused output，小矩阵用尺寸特化路径。
5. **减少工作量和中间结果**：direct final write、多输出/对称成对生成、kernel fusion、compact output、reduction pushdown 和 score-only。
6. **类型与数值策略**：FP16/整数使用扩展累加，关键归约使用 Kahan 或精确范围门，dtype/bit-exact 契约约束优化不能改变语义。
7. **平台与基础 primitive**：兼容头集中部分 runtime/error 处理，后端仍面向 ZQ500 CUDA-like ABI；自写 reduction/scan/compaction 替代不适用的 CUB/Thrust 依赖。
8. **正确性优先 A/B 与可观测性**：E2E + GPU event 双层计时、路径强制/cache bypass、误差门和 staged report publish 共同决定保留或回退。

必须使用的准确名称：**“shape-aware 策略分派与 A/B 门控”**。当前没有搜索参数空间、在线训练或自动调优数据库，不能命名为“自动 GPU 参数优化框架”。

#### 3.3.1 全库优化技术矩阵

下表回答“除设备驻留外，代码库还有哪些同类技术”。“默认”表示当前主路径可达；“条件”表示只在 shape/参数满足时启用；“关闭”表示候选代码存在但默认不用于交付路径。

| 技术族 | 要解决的原始问题 | 当前技术逻辑 | 代表代码 | 状态、效果与边界 |
|---|---|---|---|---|
| Host/Device 双态与驻留 | 若每个算子都只收 Host、返 Host，长链会产生 `H2D + D2H + H2D` | `std::variant` 在入口识别实际位置；Device 输出持有显存并直接进入下一算子，链尾 `.get()` | `types.hpp:873`、`:923`；`helpers.hpp:538`；两个 task demo | **默认**；解决任务主数据往返，不是 Unified Memory/零拷贝，首尾传输仍存在 |
| RAII + 共享 Device storage | 手工 device pointer 容易泄漏；中间值赋值可能产生 payload copy | `shared_ptr<DeviceStorage>` 管理生命周期，Device 容器复制只共享所有权；最后引用释放后回收 | `types.hpp:601`、`:722`、`:734`、`:866`；Task2 `:2094` | **默认**；Task2 measurement/peak alias 无整段复制；共享所有权不等于跨算子自动同步 |
| 容量 best-fit cache | 高频 `malloc/free` 产生固定开销与碎片 | 每类型、每 Host 线程一份 cache；同一 vector 中按 device id 过滤，再在线性扫描中选最小可容纳 block | `types.hpp:311`～`:547`，核心选择在 `:490` | **默认**；8 blocks/512 MiB/256 MiB 是每类型每线程限额；扩容四算子聚合仅 `0.0958%`，只证明扩容无益，不量化默认 cache 收益 |
| scratch / plan / prepared-result reuse | raw buffer、FFT plan、window/axis/template 等重复生成 | 区分 capacity scratch、单槽 `ensure(n,batch)` plan reuse 和有 key 的语义结果 cache | `filtering.cu:219`、`spectral.cu:264`、`radartools.cu:221` | **默认/条件**；Periodogram 特定 setup cache 历史 `-41.24%`；部分 Device cache 用 pointer identity，只适合只读输入和当前单 device/default stream 前提 |
| 精确 Host 内容缓存 | 独立 API 被相同 Host 数据反复调用时，每次仍 H2D | 每线程单槽保存 Host 内容与 Device 副本，以 shape/size/逐字节内容和参数判定命中 | `radartools.cu:492`、`:1781`、`:2601` | **条件**；MVDR warmup 后重复输入历史 `-78.41%`；冷启动、一次性调用、内容变化或超限不受益 |
| shape/resource-aware 多路径 | 一个 kernel 无法同时适配连续/跨轴、小/大窗口、短/长序列和显存预算 | 按 rank、axis、window/order、FFT length、work count 分派；ambgfun 还按 free memory/6、8～128 MiB 预算选择 tile rows | `correlate.cu:209`；`filtering.cu:4301`；`radartools.cu:2165`～`:2183` | **默认**；手写 deterministic dispatch，不是 autotuner；ambgfun 更大 tile 历史仅小幅收益且增加峰值显存 |
| Shared Memory tile/Halo | 邻接输出反复读取重叠 global memory | block 协作装载 tile + Halo，块内复用并合并读取；部分 kernel 每线程计算多个输出 | `filtering.cu:989`；Task2 helper `:685`、`:1712` | **条件**；Wiener tiled 只覆盖 2D、奇数窗口且 `<=31`，shared/寄存器限制适用范围 |
| Affine prefix scan | IIR 每个时刻依赖前状态，无法直接“一线程一样本” | 把状态更新写为可结合的仿射变换，执行 tile scan、block transform、`<<<1,1>>>` 初态传播和 apply | `filtering.cu:2162`、`:2190`、`:2284`、`:3118` | **条件**；BA 仅低阶、无 state、单连续长线；SOS 每 section 仍串行且每节约四次 launch，多线/短序列并行度受限 |
| R2C/batch 与 FFT 前后处理融合 | C2C 计算无用负频率；逐帧 FFT；前后处理产生额外中间量 | 实数单边谱用 R2C，多帧用 batch；prepare kernel 融合 detrend+window，独立 FFT 库调用后由 PSD kernel 融合 power/scale/layout | `spectral.cu:1990`、`:2041`、`:2060`、`:2095` | **条件**；不是“FFT 与 PSD 合成一个 kernel”；plan 为单槽 `(n,batch)` 复用；CSD/spectrogram 因平台数值问题保留 C2C |
| Kernel fusion / direct final write | 多 kernel 间反复写中间数组并增加 launch | 融合频域乘法+缩放、transpose+shift、加权+平滑或直接最终布局 | `spectral.cu:2060`；Task1 radartools fusion；Task2 `:2091` | **默认/条件**；Task2 peak selection 仍是独立 `row_peak_track_kernel`；fusion 会增加寄存器压力和实现耦合 |
| 公共 compact output | peak finding 的候选索引不应全部回传 Host | 先生成 dense mask，再 atomic compact 到 index output，减少最终输出/D2H | `peak_finding.cu:241` | **默认**；仍按 total 申请 full-capacity scratch，未消除 O(N) mask/scratch，不等同于 score-only |
| 任务 reduction pushdown / score-only | 应用只需 band energy、跨尺度 max 或每帧 peak，却物化完整谱图/CWT/候选矩阵 | 在频带、尺度和 block 内提前归约，只输出同 shape score 或每帧紧凑摘要 | Task2 `:3051`、`:3206`、`:3398`；Task1 `detect_peak` | **任务特化**；真正避免大中间量；不能把 Task2 application stage speedup 当作同名公共算子 speedup |
| 预编译 radix-2 FFT task kernel | 已知任务范围承担通用 library plan/布局开销 | FFT size/log2 为运行期参数；使用预编译 radix-2 kernel、global-memory twiddle cache 和可复用 global workspace | Task2 helper `:214`、`:2830`、`:3051` | **条件**；correlate/spectrogram 保留、最大 4096；correlate 满足 AOT shape 但 pad 后超限会抛错，不自动 fallback；AOT filter 默认关闭 |
| 工作粗化与跨输出复用 | 每线程工作过少或多个输出重复读取同一输入 | 单线程多输出、8-channel point kernel 共用 polyphase 累加与 shared `8x8` twiddle | `filtering.cu:2802`、`:5007`～`:5025` | **条件/保留**；channelize 8-channel 历史 E2E/kernel 约 `-91.14%/-91.69%`，126 个 device A/B bit-exact |
| 公共成对/对称生成 | 输出公式具有可证明的镜像对称 | 单线程计算一侧并镜像写另一侧，或模板化常见公式减少分支 | `wavelets.cu:164`、`:211`；`waveforms.cu:388`；`windows.cu:754` | **默认/条件**；公共 Ricker/Morlet2/Hamming 为保留路径；Task2 CWT symmetry 是另一候选，因 E2E 回归默认关闭 |
| Warp-synchronous / paired reduction | shared tree 同步过多；相邻 workload 重复读输入 | public spectral 使用 shared-memory tree + `__syncwarp`，并按条件成对处理 period/frequency；Task2 grouped path 另有 shuffle | `spectral.cu:861`、`:931`；Task1 `detect_peak` | **条件**；Lomb pair 要求 sample/freq 均 `>=1024`，vector pair 要求 period vector 且 blocks/period 足够；小输出仍受 launch 主导 |
| 小矩阵与固定状态特化 | 通用 BLAS/Solver 对 8x8、2-state 等问题 setup 成本过高 | MVDR 在 `calc_cov && sensors<=8` 走小尺寸路径；公共 Kalman 并行独立点；Task2 单 kernel 顺序更新一条轨迹 | `radartools.cu:2621`；`estimation.cu:888`；Task2 Kalman helper | **条件**；MVDR solver 仍 `<<<1,1>>>` 并 D2H info 标量；Task2 只减少 host 往返/launch，没有并行化跨帧依赖 |
| 类型感知累加与 dtype contract | FP16/整数直接累加会溢出或损失精度；声明与测试容易漂移 | FP16→FP32、Int32→int64、Int16/Int8→int32 累加，再按契约转换/饱和 | `operator_type_contracts.json`；`latest_type_contracts.json` | **默认工程契约**；14 policy、12 native direct、69 converted compatibility、6 类 edge 缺口 0；多数 FP16/整数不是 native kernel |
| 数值稳定与 bit-exact 门 | 并行归约、对称公式和 rounding 改写可能放大误差 | Kahan accumulation、有限/精确范围门、固定 rounding intrinsic、device A/B bit-exact | `spectral.cu:435`；`filtering.cu:355`；历史台账 | **默认/条件**；解释了更快的 CWT symmetry、部分 R2C 和 AOT filter 为何不能成为默认路径 |
| 国产平台兼容与自定义 primitive | SDK 语义不同，CUB/Thrust 生态不能直接依赖 | compatibility header 集中部分 malloc/copy/device/error；自写 reduction、scan、compaction；平台 probe/fixture 审计 | `platform_zx_gpu_*`；`tests/platform/CMakeLists.txt:45` | **默认/条件**；后端仍大量直接调用 ZQ500 `cuda*/cufft*/cublas*/cusolver*` ABI；外部 fixture 门默认可选，不是完整 backend 隔离 |
| E2E + GPU event 可观测性 | 只看 E2E 或单次时间无法区分固定成本和 device work | steady clock 记录 E2E，GPU event 记录 default stream 区间，算子 warmup5/repeat30 并报告 median/P95；cache 有计数器 | `task_step_report.hpp`；benchmark JSON；`types.hpp:313` | **当前报告可用**；14/14 步有 event/error；复合 event 可含 memcpy/库调用/多个 kernel，不是 profiler/hardware counter |
| A/B、精度门与 staged publish | 局部更快不保证 E2E 更快或结果正确；失败报告不能直接覆盖有效证据 | 各候选使用路径强制/bypass、误差和 E2E 门；finalizer 校验 staging，旧目录 rename 为 backup，再 publish，异常时 rollback | `docs/PERFORMANCE.md`；`scripts/finalize_reports.py:998`～`:1012` | **默认交付机制**；保留 AOT corr/spec，拒绝扩大默认 cache，回退 AOT filter/CWT symmetry；两次 rename 间并非严格单操作原子替换 |

#### 3.3.2 这些技术如何组成一条执行链

```text
输入位置判断
  → Host：上传；Device：直接复用
  → shape-aware 选择算法路径
  → capacity cache 取得输出/scratch 容量
  → prepared cache 取得 plan/window/table/template
  → tile / scan / FFT / small-matrix kernel
  → fusion + reduction pushdown 直接形成紧凑 Device 输出
  → 下游继续消费；任务边界才 materialize
  → A/B、精度门和报告门决定该路径能否成为默认交付路径
```

这套逻辑比“我们有缓冲池和融合内核”更准确：它同时处理**数据在哪里、资源是否重复准备、算法如何并行、是否生成了不需要的结果、候选是否值得交付**五个不同问题。

### 3.4 重点算子一：Wiener 邻域滤波

| 项目 | 审计结论 |
|---|---|
| 功能 | 根据局部均值/方差估计对实数 N 维数组进行自适应降噪 |
| 输入 / 输出 | `RealArrayLike image`、窗口 `mysize`、可选 noise → 同 shape `ZxGpuRealArray` |
| 原始算法 | 每个输出点遍历邻域，计算 `sum` 和 `sum_sq`，再由局部方差应用 Wiener 公式 |
| 原始 GPU 瓶颈 | 相邻输出窗口高度重叠；通用 kernel 为每个输出重复读取同一 global memory 邻域 |
| GPU 并行 | 通用 N-D：每线程一个输出；2D 快路径：`16x16` block 协作加载含 Halo 的 shared tile |
| 优化方法 | shared-memory tile、合并加载、局部复用；shape/window metadata 缓存；噪声自动估计使用两级归约 |
| 当前限制 | tiled 仅覆盖 rank=2、两维奇数窗口且均 `<=31`；其他路径回退通用 N-D，rank 上限 8；ZQ500 自动噪声路径仍有一次标量 D2H，局部 mean/variance 仍写 global memory |
| 代码位置 | `src/zhongkexin/filtering.cu:918` 通用 kernel；`:989` tiled kernel；`:4301` 分派；`:4344` noise 归约/D2H |

证据效果：

- `[历史 A/B]` `214.44 → 3.50 ms`，GPU 版本耗时约降低 61 倍；见 `docs/PERFORMANCE.md:78`。
- `[RUN 2026-07-20 已发布快照]` 1,048,576 点图像：CPU `646.387 ms`，GPU E2E `3.52033 ms`，GPU event/kernel 字段 `3.34117 ms`，E2E `183.615x`；mixed error `9.75527e-7`。见 `data/reports/units/benchmarks/summary.json`。

PPT 核心结论：

> 共享内存分块把重叠窗口的重复全局读取转化为 block 内 Halo 数据复用，但自动噪声归约和中间统计量仍是剩余开销。

### 3.5 重点算子二：IIR / SOS 递归滤波

| 项目 | 审计结论 |
|---|---|
| 功能 | `lfilter` 执行 BA 递推，`sosfilt` 执行二阶节级联，`filtfilt` 执行正反向零相位滤波 |
| 输入 / 输出 | 系数 `b/a` 或 `[sections,6]` SOS、N-D 实数组、axis、可选 state → 同 shape 输出及可选终态 |
| 原始算法 | 每个样本依赖前一时刻状态，沿时间轴天然串行 |
| 并行难点 | 直接“一线程一个样本”无法计算；只按 line 并行时，单长序列仍只有一个有效线程 |
| GPU 并行 | 将二阶状态更新写为二维 affine transform；利用变换复合的结合律做 hierarchical prefix scan |
| 优化方法 | tile 内 shared scan → tile transform scan → 少量 block 初态传播 → 前缀状态回填；BA 低阶 fast path 转单节 SOS；filtfilt 正反向复用 scan |
| 当前限制 | `lfilter` scan 仅无 zi/zf、order `<=2`、`b/a<=3`、单条连续 line、axis 长度 `>=1024`；通用高阶/多线回退 line kernel；order 上限 256；每 SOS section 仍顺序执行多个 kernel |
| 代码位置 | `src/zhongkexin/filtering.cu:2162` affine 结构；`:2190` tile scan；`:2284` 层级 scan；`:2994` lfilter 分派；`:3118` scan 实现；`:3177` sosfilt 分派 |

证据效果：

- `[历史 A/B]` 特定灾难性旧路径：`lfilter 455.17 → 0.359 ms`，`filtfilt 909.94 → 0.679 ms`。见 `docs/PERFORMANCE.md:74`。
- `[RUN 2026-07-20 已发布快照]` 不同、较短 case 中，`lfilter` CPU/GPU E2E 为 `0.212856/0.422368 ms`，E2E 仅 `0.504x`，但 GPU event/kernel speedup `1.457x`；固定开销仍足以反转 E2E 结论。

这组数据非常适合讲算法优缺点：递推已经可以并行，但多级 launch、scratch 和 E2E 固定开销会吞掉短序列收益。

PPT 核心结论：

> 仿射状态复合把二阶递推转化为可结合的前缀扫描；它解决了并行性问题，却没有消除短序列的 launch 与 setup 成本。

### 3.6 重点算子三：Periodogram / 频谱流水

| 项目 | 审计结论 |
|---|---|
| 功能 | 对实数信号执行 detrend、加窗、FFT、功率谱缩放并返回频率轴和 PSD |
| 输入 / 输出 | 实数 N-D 数组、fs、window、nfft、detrend、onesided、scaling、axis → frequency + real PSD |
| 原始算法 | 准备分段 → 通用 C2C FFT → 功率 → 缩放 → 裁剪单边谱，且重复生成窗口/scale/频率轴/plan |
| GPU 并行 | 实数单边谱走 R2C；segment preparation 合并 constant detrend 与 window；频域 kernel 直接写 PSD |
| 优化方法 | R2C 避免负频率；融合预处理和输出；FFT plan 按 `(n,batch)` 复用；命名窗口、scale、频率轴精确 key 缓存 |
| 当前限制 | explicit host/device window 不缓存；cache miss 上仍需 D2H 计算 scale；ZQ500 的 CSD 与 spectrogram R2C 路径有数值发散注释，当前回退 C2C，不能把 R2C 结论推广到全部频谱算子 |
| 代码位置 | `src/zhongkexin/spectral.cu:1964` API；`:1990` cache key；`:2041` R2C 分派；`:2060` fused prepare；`:2095` FFT/PSD |

证据效果：

- `[历史 A/B]` R2C + detrend/PSD fusion：`72.91 → 0.669 ms`，约 109 倍降低；见 `docs/PERFORMANCE.md:77`。
- `[历史 A/B]` setup cache：`0.659052 → 0.387250 ms`，E2E 下降 `41.24%`，kernel `0.192644 → 0.192576 ms` 基本不变；见 `docs/PROJECT_LEDGER_notsub.md:815`。
- `[RUN 2026-07-20 已发布快照]` 当前 case：CPU `1.41709 ms`，GPU E2E `0.366592 ms`，GPU event/kernel 字段 `0.192732 ms`，E2E `3.866x`，mixed error `1.79739e-7`。

PPT 核心结论：

> R2C 和 PSD 输出融合减少无效频点与中间写回，setup cache 则专门削减 kernel 外固定成本；两者解决的是不同层级的问题。

### 3.7 重点算子四：CA-CFAR

| 项目 | 审计结论 |
|---|---|
| 功能 | 依据 guard/reference 窗口和虚警概率生成检测阈值与 detection map |
| 输入 / 输出 | 实数 1D/2D 功率图、guard/reference cells、PFA → threshold + detections |
| 原始算法 | 每个 cell 扫描参考窗口、排除 guard 区并求均值，窗口重叠造成重复读取 |
| GPU 并行 | 小 footprint 直接滑窗；较大路径可走 FFT 或二维 row prefix + integral image，再 O(1) 查询矩形和 |
| 优化方法 | 按 shape/footprint 分派；大行使用每行 256 线程 chunk prefix；积分图阈值 kernel 并行写结果 |
| 当前限制 | 分派阈值为经验策略而非自动调参；积分图需要额外 global workspace 和多次 launch；Task1 L6 CFAR 中间误差接近任务容限 |
| 代码位置 | `src/zhongkexin/radartools.cu:2396` 1D/FFT；`:2495` 2D；`:2555` integral workspace 和 prefix；`:2582` threshold |

证据效果：

- `[历史 A/B]` Task1 L6 row-prefix 并行化：`1.02946 → 0.734229 ms`，下降 `28.68%`；见 `docs/PROJECT_LEDGER_notsub.md:731`。
- `[RUN 2026-07-20 已发布快照]` 公共 perf case CPU/GPU `9.28336/1.18229 ms`，E2E `7.8520x`。
- Task1 final-input 的 CFAR threshold mixed error 为 `0.276398 < 0.5`；最终 CPU/GPU detection bin 与注入目标一致。不能写“所有中间误差都很小”。

### 3.8 重点应用算子组：CWT、相关与 score-only

Task2 不需要每帧完整保存所有中间谱图和尺度矩阵，其 GPU 热路径按最终任务目标做了特化：

| 路径 | 原始应用结构 | GPU 特化 | 主要限制 / 边界 | 代码位置 |
|---|---|---|---|---|
| Correlate score | CPU 逐帧完整相关 → magnitude → normalize | 批量预编译 radix-2 FFT task kernel 或 shared-halo direct，直接生成 score | FFT 对 pad 后的 power-of-two 执行且最大 4096；满足 AOT shape 但 pad 超限会抛错；应用级结果不能外推为公共 correlate | `task2_features_zx_gpu.cu:2830` |
| Spectrogram band score | 每帧完整 spectrogram → 选频带 → 投影样本轴 | AOT FFT 后只归约目标频带并回写 score | 是 Task2 helper，不是公共 spectrogram 输出语义 | `task2_features_zx_gpu.cu:3051` |
| CWT max score | 物化 `{frame,scale,sample}` 复数张量后跨 scale max | 缓存 Morlet kernel table，shared Halo 卷积并直接做尺度最大值 | Morlet 对称候选默认关闭；完整公共 CWT 仍需保留 | `task2_features_zx_gpu.cu:3206` |
| Fusion + peak | 四路 score 加权 → B-spline 平滑 → peak | 加权和平滑融合，随后每行 block 选峰 | 当前为任务私有 helper | `task2_features_zx_gpu.cu:3398` |

历史保留效果：

- AOT correlate L6 `4.45944 → 1.70953 ms`，热点下降 `61.66%`，Task2 E2E 下降 `9.77%`。
- AOT spectrogram L6 `5.08862 → 2.88187 ms`，热点下降 `43.37%`，Task2 E2E 下降 `7.78%`。
- V6 Task2 CWT L6 `34.0065 → 9.57086 ms`，下降 `71.86%`。
- AOT filter 因 demod mixed error `1.10305/2.02626 > 0.0005` 被关闭；CWT symmetry 因 L5/L6 E2E 退化被关闭。

证据：`docs/PERFORMANCE.md:208`、`:220`；`docs/PROJECT_LEDGER_notsub.md:846`、`:847`。

---

## 4. 任务整体运行链路

### 4.1 Task1：雷达目标检测与多普勒分析

```text
场景参数
  → chirp 模板 + 含目标/噪声的 complex64 脉冲矩阵
  → 模板和脉冲矩阵分别 H2D，形成 Device 输入
  ├→ 主检测链：pulse compression（batched FFT 匹配滤波）
  │    → pulse_doppler_shifted（慢时间 FFT + transpose/shift）
  │    → power_map（complex64 → float32）
  │    → ca_cfar（threshold + detections）
  │    → detect_peak（消费 power + detections，两级归约）
  └→ 模板旁路：ambgfun（独立生成二维模糊函数，不参与 peak 依赖）
  → 输出/验证边界：检测摘要 .get() + 其余 artifact materialize
  → range bin / Doppler bin / Doppler Hz / power
```

六个正式步骤全部是 public：

| 步骤 | CPU 路径 | GPU 路径 | 中间数据 |
|---|---|---|---|
| pulse compression | `cpu::radartools::pulse_compression` | 同名 GPU API | complex array，device resident |
| pulse Doppler | `pulse_doppler + fftshift_rows` | `pulse_doppler_shifted` | complex range-Doppler map |
| power map | `power_map` | `power_map` | float32 power map |
| CA-CFAR | `ca_cfar` | `ca_cfar` | threshold + detection arrays |
| ambiguity | `ambgfun` | `ambgfun` | float32 surface + axes |
| detection | `detect_peak` | `detect_peak` | 紧凑标量摘要 |

GPU 主检测链和 ambgfun 旁路都保持设备态；在输出/验证边界，`gpu_detection_device.get()` 回传紧凑检测摘要，随后 `materialize_gpu_artifacts()` 回传需要比对/落盘的其余中间量。当前每个步骤由 `measure_gpu_ms` 单独同步，因此代码虽有逻辑分支，执行上仍是串行分步，不是多 stream overlap。

证据：`demo/task1_radar/task1_radar_demo.cpp:1221`、`:1236`～`:1287`、`:1759`～`:1790`；`tests/contracts/task_step_contracts.json`。

### 4.2 Task1 的五项应用级优化

| 优化 | 改变的执行结构 | 历史效果证据 |
|---|---|---|
| 模板 FFT/prepared cache | 重复模板不再重复 pack、norm、FFT | L6 pulse compression 下降 `7.43%` |
| 频域缩放融合 | `input * conj(template)` 同时乘 `1/nfft`，删除 IFFT 后全矩阵 scale kernel | L6 pulse 再下降 `4.79%` |
| Doppler transpose + fftshift 融合 | 写回时直接 shifted，少一张全矩阵和一次 launch | L6 Doppler 下降 `11.57%` |
| CFAR row prefix 并行 | 每行 256 线程 chunk scan 替代单线程长行扫描 | L6 CA-CFAR 下降 `28.68%` |
| 峰值两级归约与紧凑回传 | block 局部最大 + 全局归约，仅回传 5 个标量 | `4.052 → 0.096 ms` |

另有 ambgfun 归一化输入缓存，历史 Task1 L6 hotspot 下降 `22.19%`；surface 计算本身仍完整执行。

### 4.3 Task2：多域特征提取和轨迹跟踪

```text
场景参数
  → 目标模板 + 多帧 complex64 接收数据 + truth track
  → FIR filtering / real projection
  → batched demod score ───────────────┐
  → batched correlate score ───────────┤
  → spectrogram band score ────────────┼→ weighted fusion + smoothing
  → CWT max-over-scale score ──────────┘             ↓
                                               row peak track
                                                     ↓
                                       measurement alias / Kalman track
                                                     ↓
                              统一 .get() + CPU/GPU/Truth 轨迹验证
```

八个正式步骤都被契约标记为 `mixed`：

- CPU reference 逐帧调用公共算子并执行 host 后处理。
- GPU 主计时路径一次上传后批量处理；公开算子用于语义锚点和代表帧校验，热点通常由任务专用 batched/AOT/score-only helper 执行。
- filter、demod、correlate、spectrogram、CWT、fusion、measurement、Kalman 的“步骤时间”因此是应用级实现对比，不是同名公共算子的纯算子 speedup。
- `measurement_conversion` 在当前源码中直接执行 `measurement_values = peak_track`，计时记录 0；契约仍引用 `copy_measurement_track_zx_gpu`。正式冻结前应统一契约和实现表述。
- Kalman 被封装为一次 kernel launch，但 `kalman_track_from_peaks_kernel<<<1,1>>>` 内仍按 frame 串行推进，减少的是 host 往返/launch，不是消除状态依赖。

证据：`demo/task2_features/task2_features_demo.cpp:1712`、`:1829`、`:1903`、`:1932`、`:1988`、`:2013`、`:2037`；`task2_features_zx_gpu.cu:2229`、`:3457`；任务契约 JSON。

### 4.4 Task2 的五项应用级优化

1. 逐帧 CPU 编排改为整批 GPU 执行，并使中间 score 保持 device resident。
2. 相关在满足 rows/cols/template 阈值时使用预编译 radix-2 task kernel，复用 global twiddle/workspace；未达到 AOT shape 阈值时走 tiled/direct，但进入 AOT 后 pad 超过 4096 会抛错而不是回退。
3. Spectrogram 只计算目标 band score，不物化每帧完整任务中间谱图。
4. CWT 把 Morlet 卷积与跨尺度 max 融合，避免巨大的三维复数中间量。
5. 四路融合、B-spline 平滑和 peak selection 压缩为少量 kernel，Kalman 状态链封装成一次 launch。

---

## 5. 性能证据

### 5.1 当前验证总览

| 门禁 | 已发布结果 | 证据 |
|---|---:|---|
| 注册算子 | `81/81` passed | `data/reports/summary.json` |
| 任务 | `2/2` passed | 同上 |
| 正式计算步骤 | `14/14` | 同上、`validation/task_steps/` |
| L1-L6 任务运行 | `12/12` | `data/reports/demo/*/scales/` |
| 运行期审计 | 6 份 JSON 全通过 | `data/reports/validation/` |
| 接口审计 | `81/81` | `validation/interfaces/latest_interface_audit.json` |
| dtype/type 契约 | 声明 edge 缺口 0 | `validation/dtype_coverage/`、`type_contracts/` |

### 5.2 当前算子 benchmark 的严格口径

- 81 个算子汇总均 `pass`，accuracy case 合计 241。
- 81 个算子现在都拥有结构化 `performance_cases`，合计 86 条；其中 73 个算子的 78 条来源为独立 `case_detail`，另 8 条来源为 `summary_aggregate`。
- 正式 perf case 统一为 GPU warmup 5、repeat 30；CPU/GPU/kernel 使用中位等统计。
- 8 条 `summary_aggregate` 来自 correlate 三项、`fm_demod`、`kalman_filter` 和三个 peak-finding；当前 schema 已将其标为 available，但它们没有独立 case 明细。严格分布图仍应只使用 78 条 `source=case_detail`，聚合行可以在附注中披露。
- 5 个算子含多个 perf case；operator `summary` 是跨 case 的再聚合。例如 chirp 的 `96.2879x` 不对应任何单一 case，真实两 case 为 `137.165x` 和 `66.4262x`。Top/Bottom 图优先使用 78 条 `source=case_detail` 记录。

按 81 个算子的 summary 行进行本次审计派生：

| 指标 | 值 |
|---|---:|
| GPU E2E 更快 | `70/81` |
| GPU E2E 更慢 | `11/81` |
| 中位 E2E speedup | `7.85204x` |
| 几何平均 E2E speedup | `7.29807x` |

按 78 个独立 `case_detail` 派生：中位 `17.4634x`、几何平均 `10.1128x`、69 快 9 慢。若把 8 条 aggregate 一起纳入，则为 86 条、75 快 11 慢；两种来源不能无说明混画。PPT 主图建议只画 78 个 detailed case，页眉同时写“81/81 有性能入口；78 detailed + 8 aggregate”。

若按 81 个 operator summary 各算子只计一个点，则为 70 快、11 慢，中位 `7.85204x`、几何平均 `7.29807x`。这个口径覆盖最完整，但 5 个多 case 算子的 summary 是跨 case 再聚合，不能用于 case 级 Top 排名。

### 5.3 当前代表性算子结果

| 算子 / case | samples | CPU median | GPU E2E median | GPU kernel median | E2E speedup | 技术解释 |
|---|---:|---:|---:|---:|---:|---|
| Wiener / large image | 1,048,576 | 646.387 ms | 3.52033 ms | 3.34117 ms | 183.615x | shared tile 复用邻域 |
| CWT / large | 33,554,432 | 24,686.9 ms | 59.7942 ms | 59.6755 ms | 412.864x | 大规模卷积并行，kernel 主导 |
| Lomb-Scargle | 见 case | 2,151.74 ms | 11.5381 ms | 11.2991 ms | 186.490x | 频率块并行与归约 |
| Pulse compression | 1,048,576 | 87.4760 ms | 1.77839 ms | 1.36953 ms | 49.1882x | batched FFT + template reuse |
| Spectrogram | 见 case | 346.662 ms | 6.87918 ms | 6.81352 ms | 50.3930x | 分段/FFT 吞吐充分 |
| Periodogram | 16,385 | 1.41709 ms | 0.366592 ms | 0.192732 ms | 3.86558x | R2C + 前后处理 fusion 有效，setup 仍明显 |
| MVDR | sensors=8 | 21.2433 ms | 2.37510 ms | 0.840180 ms | 8.94417x | 约 64.6% GPU E2E 为 event 区间外差额 |
| lfilter | 32,768 | 0.212856 ms | 0.422368 ms | 0.146067 ms | 0.503959x | GPU event 工作已快，E2E 固定开销反转结论 |
| filtfilt | 32,768 | 0.576492 ms | 0.666259 ms | 0.404461 ms | 0.865268x | scan 多级 launch/setup |
| boxcar | 见 case | 0.002830 ms | 0.073231 ms | 0.028258 ms | 0.0386448x | CPU 标量/短循环远小于 GPU 固定成本 |

当前 detailed case Top5：`general_gaussian 506.667x`、`CWT 412.864x`、`Kaiser 257.695x`、`Lomb-Scargle 186.490x`、`Wiener 183.615x`。

当前 detailed case Bottom5：`kaiser_atten 0.000959x`、`kaiser_beta 0.000967x`、`cfar_alpha 0.002301x`、`boxcar 0.037933x`、`firfilter_zi 0.043336x`。

### 5.4 当前 Task L1-L6 scaling

以下 CPU/GPU 时间来自每个 `metrics.json` 的已发布 `timings.total` 终值；total 已包含 `input_construction`。用于答辩的性能数据均为 `current-20260720-task-optimized-l6` 报告快照，正式答辩前仍需在最终 commit 上复验。

| 规模 | Task1 CPU / GPU median | Task1 speedup | Task2 CPU / GPU median | Task2 speedup |
|---|---:|---:|---:|---:|
| L1 | 3.04131 / 1.97985 ms | 1.536x | 254.293 / 3.58509 ms | 70.931x |
| L2 | 8.46167 / 2.17392 ms | 3.892x | 949.834 / 7.16343 ms | 132.595x |
| L3 | 9.98780 / 2.04135 ms | 4.893x | 1,862.05 / 5.81624 ms | 320.147x |
| L4 | 29.2159 / 2.73216 ms | 10.693x | 4,364.84 / 9.16118 ms | 476.450x |
| L5 | 72.1273 / 3.49582 ms | 20.632x | 8,268.24 / 12.0842 ms | 684.219x |
| L6 | 158.097 / 8.03348 ms | 19.680x | 18,726.3 / 20.9428 ms | 894.164x |

注意：L1-L6 同时改变脉冲/帧数、每行样本、模板长度、FFT 长度等多维参数，不是严格单变量复杂度实验。Task1 L6 speedup 较 L5 略回落，应结合入口准备、Doppler/FFT/CFAR 结构解释，不能硬画成单调曲线。

更重要的口径边界：CPU 的 `input_construction` 计入场景/Host 参数生成，GPU 的对应阶段是在同一批已生成 Host 输入上做 Device 上传与 GPU 参数准备，两侧并非严格相同工作量。以上 speedup 是**应用工作流对比**，不是纯 backend 或纯 kernel 加速比；Task2 的高倍数尤其受 CPU 逐帧/输入准备与 GPU batched 特化的结构差异影响。

`final/` 是另一组代表性 L6 输入，而非 `scales/L6` 的重复：Task1 `387.942/11.3444 = 34.197x`，Task2 `29,215.1/27.2606 = 1071.697x`。其 shape 分别为 `[128,4096]` 与 `[128,3072]`，不能与 scale 曲线的单一横坐标混画。

### 5.5 final-input 步骤构成（已发布终值）

| Task1 步骤 | GPU E2E | GPU event stream work | 占最后一次 total |
|---|---:|---:|---:|
| input construction / H2D | 3.42283 ms | 3.37695 ms | 30.17% |
| ambiguity function | 3.11511 ms | 3.07786 ms | 27.46% |
| pulse Doppler | 1.72463 ms | 1.67657 ms | 15.20% |
| pulse compression | 1.40683 ms | 1.36328 ms | 12.40% |
| CA-CFAR | 1.24733 ms | 1.21054 ms | 11.00% |
| power map + detection | 0.427707 ms | 0.358848 ms | 3.77% |
| **total** | **11.3444 ms** | **11.0640 ms** | **100%** |

| Task2 步骤 | GPU E2E | GPU event stream work | 占最后一次 total |
|---|---:|---:|---:|
| CWT | 12.5245 ms | 12.4446 ms | 45.94% |
| input construction / H2D | 5.21248 ms | 5.18566 ms | 19.12% |
| spectrogram | 3.80265 ms | 3.74277 ms | 13.95% |
| filter | 2.38945 ms | 2.37533 ms | 8.77% |
| correlate | 2.19892 ms | 2.13878 ms | 8.07% |
| 其余四步 | 1.13260 ms | 1.03756 ms | 4.15% |
| **total** | **27.2606 ms** | **26.9247 ms** | **100%** |

14/14 个正式计算步骤都有 GPU event 值；Task2 `measurement_conversion=0` 表示浅层别名交接没有 CUDA work。final-input total 的 E2E-event 差分别为 Task1 `0.2804 ms`、Task2 `0.3359 ms`，但这个差额只能表示 event 区间外的 host API/同步等开销。event 区间本身可能包含 H2D、库调用和多个 kernel，不能称为单一 kernel 时间，也不能仅凭当前报告反推出“若每步往返会多花多少”。

### 5.6 正确性证据和例外

- Task1 final-input：注入、CPU、GPU 均定位 `range_bin=768`、`doppler_bin=72`、`125 Hz`。
- Task2 final-input：CPU/GPU peak track 一致；CPU/GPU Kalman RMSE `0`，对真实轨迹 RMSE `0.477855 < 2`。
- 当前全库最大需要披露的 accuracy mixed error 是 `spectral/coherence` 的 `0.0683923`；算子仍按其校准门禁通过，不应表述为“所有算子误差接近零”。
- Task1 final-input CFAR threshold mixed error `0.276398 < 0.5`，最终检测位置正确；Task2 feature-score mixed error `9.83703e-5 < 1e-4`。最大相对误差在参考值近零时会失真，PPT 应优先画 mixed error/RMSE 与容限，不画巨大 max-rel 作为主图。
- dtype 覆盖六类 edge 缺口为 0，但 native direct 与 converted compatibility 必须区分；FP64、complex128 等明确不支持。

### 5.7 可使用的历史优化前后证据与机制归因口径

机制页不能把“某个优化路径的总 A/B”直接改写成“其中任一机制单独带来 X 倍”。只有设置了同配置的机制开关、且只改变该机制的 A/B，才能作严格独立归因；当前可直接用于此口径的是 Periodogram setup cache。其他记录应按“代表路径整体 A/B”使用：它们证明该路径有效，但不能提供各机制的全库最高加速比，也不能拆分总收益。

| 技术 | 历史 before → after | 正确表述 |
|---|---:|---|
| Wiener 16x16 shared tile | 214.44 → 3.50 ms | **代表路径整体 A/B**，记录的主变更为 Tile；没有仅开/关 Tile 的独立 A/B，不能外推为所有邻域算子收益 |
| lfilter affine scan | 455.17 → 0.359 ms | **代表路径整体 A/B**；同时包含 BA→单节 SOS 快路径与 prefix scan，不能全部归因给 Scan |
| filtfilt 双向 scan | 909.94 → 0.679 ms | 特定历史旧路径到保留路径 |
| periodogram R2C + fusion | 72.91 → 0.669 ms | **代表路径整体 A/B**；没有 R2C-only / Fusion-only A/B，不能拆分 109 倍 |
| coherence shared FFT/fusion | 5.27 → 0.751 ms | 历史 GPU 版本约降低 7 倍 |
| periodogram setup cache | 0.659052 → 0.387250 ms | **严格独立 A/B**：同进程 cache bypass/candidate，E2E 降 41.24%，kernel 基本不变，`1.70×` |
| Task2 AOT correlate L6 | 4.45944 → 1.70953 ms | hotspot 降 61.66%，E2E 降 9.77% |
| Task2 AOT spectrogram L6 | 5.08862 → 2.88187 ms | hotspot 降 43.37%，E2E 降 7.78% |

这些数字必须带 `[历史 A/B]`、版本/协议脚注；不能与当前 CPU/GPU 表拼接计算新的“优化倍数”。

### 5.8 应用性能对比对象边界

当前仓库没有发现独立 NVIDIA GPU、其他国产 GPU 或所谓“传统 GPU 实现”的可复现实验报告、结构化 metrics、设备信息和运行脚本。因此 Task1/Task2 的应用效果页只能使用以下三类证据：

1. 当前 CPU reference 与 ZQ500 GPU 的 application-total 对比。
2. 同一 ZQ500 实现内部、协议明确的历史候选 before/after A/B。
3. L1～L6 当前 Scaling、步骤热点和最终业务正确性。

PPT 不得增加“传统 GPU”柱、NVIDIA/CUDA 设备名或推测性倍数，也不得把 CPU reference 称为传统 GPU。若后续确需该比较，必须新增对照实现，并在同一输入、语义、精度、warmup/repeat 和计时边界下重新采集；在此之前，应用页使用“算法流程与核心技术 → CPU/ZQ500 当前结果 + 内部 A/B”的两页结构。

---

## 6. 性能瓶颈

### 6.1 计算瓶颈

| 结论 | 依据 |
|---|---|
| ambgfun 是当前最大单算子 GPU E2E 热点 | `168.131 ms` E2E、`167.367 ms` GPU event/kernel 字段，二者接近；二维 surface 和批量 FFT 主导 |
| 公共 CWT 大规模由 GPU 工作量主导 | `59.8248/59.6739 ms` E2E/event；生成 33,554,432 个规模量级输出 |
| STFT/CSD/Morlet2/Ricker 仍是较大 GPU 工作项 | 当前 E2E/event 分别约 `19.9645/19.8601`、`18.9037/18.7926`、`16.7840/16.6858`、`15.3485/15.2513 ms` |

结论边界：没有硬件计数器，`E2E≈kernel` 只能证明主体在 GPU 执行区，不足以进一步区分算术吞吐与显存带宽。

### 6.2 显存和访存瓶颈

- Wiener 通用路径的重叠窗口重复读来自代码结构；shared tile 的历史大幅收益支持“访存复用有效”。
- CWT、FIR 和 Task2 correlate 的 shared Halo/多输出设计减少 block 间重复加载，但边界判断、shared 容量和寄存器压力限制继续放大。
- Task2 score-only 避免完整 `{frames,scales,samples}` 或完整每帧谱图，是减少中间显存和写回的算法级优化。
- 当前报告没有 DRAM bytes、cache hit、bandwidth utilization 等指标，不能给出“带宽利用率 XX%”或严格 memory-bound 结论。

### 6.3 Kernel launch 与固定开销

- `kaiser_beta`、`kaiser_atten`、`cfar_alpha`、`boxcar`、`firfilter_zi` 等 CPU 极短路径的 GPU E2E speedup 远小于 1，主要依据是绝对 CPU 时间仅微秒量级，而 GPU 有 API/launch/sync 固定成本。
- lfilter 当前 case GPU event/kernel 字段 `0.146067 ms` 已快于 CPU `0.212856 ms`，但 E2E `0.422368 ms` 反而更慢，直接证明固定开销足以反转结论。
- IIR prefix 每 section 约四阶段 kernel；Task1/Task2 又对每步单独 event + synchronize，当前没有跨步骤 overlap。
- 当前 14/14 步已有 event 计时；final-input E2E-event 差为 Task1 `0.2804 ms`、Task2 `0.3359 ms`。它量化了 event 区间外 host API/同步差额，但 event 区间可包含 copy、库调用和多个 kernel，不能把差额全部归因于 launch，也不能把字段当单 kernel profiler 时间。

### 6.4 数据搬运和 setup

- Host 输入第一次进入 GPU API 仍需 H2D；`std::variant` + Device 输出驻留避免任务链中每步 `D2H → H2D`，重复独立 Host 调用还可由精确内容缓存命中已上传副本。三者适用场景不同。
- Device 容器浅拷贝共享 `DeviceStorage`，例如 Task2 `measurement_values = peak_track` 不复制 payload；这解决所有权/别名开销，不应和传输缓存混称。
- 主数据链已驻留，但部分实现仍有小规模或 fallback 搬运：Wiener 自动 noise 标量、filter design 的 device 参数、CWT widths、spectral cache miss 的 window scale、Task2 小型 B-spline/window table，以及部分 filtering gust CPU fallback。
- Periodogram cache miss 会把 window D2H 求 scale；历史 cache A/B 中 kernel 不变而 E2E 下降 41.24%，说明 setup 是该 case 的主要固定成本。
- MVDR `2.37510 ms` E2E 与 `0.840180 ms` GPU event/kernel 字段的差约 `1.53492 ms`，占 E2E 约 `64.63%`；其历史 host-input cache 也显示重复搬运是主因之一。
- DeviceStorage 扩容四算子历史聚合收益只有 `0.0958%`，说明“更多显存”本身不是主要性能方案。

### 6.5 串行依赖和并行度限制

- IIR 低阶长单线可用 affine scan，但高阶、多线、显式 state 和短序列回退；scan 中还保留单线程传播少量 block 初态。
- Task2 Kalman 通过 `<<<1,1>>>` 把跨帧状态链放在设备上串行执行，减少 host/launch，但没有数据级并行。
- 标量、索引和极小输出算子没有足够工作量占满 GPU，CPU 更合适。
- 当前 application-total 口径下，Task1 L1 仅约 `1.54x`，而 L5/L6 约 `20.63x/19.68x`，说明并行度和固定成本对规模敏感；这些 total 含两侧工作不完全对称的 input construction，不能解释为纯计算 scaling。

### 6.6 国产 GPU 平台限制

- 当前平台只允许 ZHONGKEXIN；CUDA-like 名称来自 SDK ABI，不代表 NVIDIA 路径。
- ZQ500 FFT 兼容层按文档只支持 2 的整数次幂，其他长度需显式 pad/crop。
- `spectral.cu` 明确记录 CSD/spectrogram 的 R2C 数值发散，当前部分路径保留 C2C；不能统一宣称“所有实数频谱都用 R2C”。
- Solver LU 需要有效 pivot buffer；compile/runtime probe 为默认平台检查，外部 compatibility matrix/禁止 API fixture 仅在 fixture 可用或显式要求时执行。
- 当前报告不含 telemetry、driver counter 或功耗，无法制作平台 Roofline、能效或峰值利用率图。

---

## 7. 项目亮点候选

### 亮点 1：按算法结构重写三类难并行算子

- **做了什么**：Wiener 用 shared tile，IIR 用 affine prefix scan，Periodogram 用 R2C + fused PSD。
- **为什么难**：三者分别受重叠访存、时间递归和频谱冗余约束，不能用同一个模板化 kernel 解决。
- **使用方法**：Halo 协作加载、结合律状态变换、实数 FFT 与前后处理融合。
- **效果**：历史版本分别出现约 61 倍、千倍级灾难性旧路径修复和约 109 倍 GPU 版本耗时降低；已发布快照中 Wiener `183.615x`、Periodogram `3.866x`，同时 IIR 当前短 case 如实暴露 E2E 不占优。

### 亮点 2：双态驻留与分层资源复用

- **做了什么**：用 C++17 `std::variant` 统一 Host/Device API，让 Device 输出在任务内继续驻留；用 `shared_ptr<DeviceStorage>` 支持安全浅层共享；再分别提供 core capacity cache、模块 prepared cache 和精确 Host 内容缓存。
- **为什么难**：既要避免无谓 H2D/D2H、payload copy、分配和重复准备，又要保证不同 device、线程、shape、窗口、参数和输入变值时不会错误命中。
- **使用方法**：入口位置分派、链尾显式 materialize、RAII 共享所有权、容量 best-fit、语义精确 key、内容比较和 cache bypass。
- **效果**：Task 链消除每步往返；Periodogram setup cache 历史 E2E 下降 41.24%，MVDR 重复 Host 输入 cache 下降 78.41%。扩大通用 cache 仅 0.0958% 后被拒绝，体现四层机制各自针对真实成本。

### 亮点 3：从公共算子到应用级 score-only 融合

- **做了什么**：Task1 六步全公开算子组合；Task2 把逐帧公共语义转换为批量 radix-2 task kernel、band-score-only、CWT max-score、融合加权/平滑和独立峰值选择路径。
- **为什么难**：必须保持公共算子语义和代表帧正确性，同时避免为任务不需要的完整中间量付费。
- **使用方法**：批处理、固定尺寸 FFT、跨尺度归约融合、device-resident score、紧凑输出。
- **效果**：已发布 final-input 快照中 Task1 `34.20x`、Task2 `1071.70x`；L6 scale 分别为 `19.68x/894.16x`。两者均含 input construction，后者还包含 CPU 逐帧与 GPU batched 特化的结构差异，不能称为公共算子或纯 kernel speedup。

### 亮点 4：正确性优先的 A/B 保留与回退

- **做了什么**：候选优化有精度、热点、E2E、稳定性和完整回归门；失败候选明确回退。
- **为什么难**：局部 kernel 更快、分配更少或显存更多，并不保证任务 E2E 更快或数值仍正确。
- **使用方法**：路径强制、cache bypass、L1/L5/L6 A/B、重复运行和完整门禁。
- **效果**：保留 AOT correlate/spectrogram；关闭 AOT filter、CWT symmetry、cache 扩容和不稳定 buffer 生命周期方案。

### 亮点 5：机器契约驱动的完整交付

- **做了什么**：81 算子、dtype edge、14 步任务和报告 schema 都有机器可读契约。
- **为什么难**：代码、测试、文档和报告容易在重构时失配。
- **使用方法**：根级 validate 流程、失败不发布、文件/源码 SHA256、当前运行 provenance。
- **效果**：已发布运行 81/81、2/2、14/14、12/12 通过；338/338 report payload hash 匹配，14/14 步同时有 error 与 GPU event 字段。当前 source hash 为 691/695，差异包含两个 task demo、说明文档与探索脚本；这不改写当次报告，但正式答辩必须在最终 commit 重新冻结。

---

## 8. 当前不足与改进方向

### 8.1 算法层面

| 当前不足 | 证据 | 改进方向 |
|---|---|---|
| ambgfun 二维 surface 仍是最大 GPU 热点 | E2E/event `168.131/167.367 ms` | 研究分层/稀疏搜索、只计算任务需要区域、跨 tile 数据复用，而非只加大显存 |
| IIR fast scan 覆盖面窄 | 仅低阶、单连续长线、无 state | 推广 segmented scan/多线 batched scan；为不同阶数建立稳定变换形式 |
| Task2 Kalman 设备内仍单线程 | `<<<1,1>>>` | 多目标/多 track 批处理；单轨保持 CPU fallback 或与前后步骤融合 |
| Task2 应用 speedup 与公共算子语义并非完全同路径 | mixed 8 步 | 将成熟的 score/reduction helper 提炼为可复用 public API，并分别报告 public 与 application 性能 |

### 8.2 Kernel 层面

| 当前不足 | 证据 | 改进方向 |
|---|---|---|
| 短算子 launch 主导 | lfilter kernel 快但 E2E 慢；标量算子极慢 | 对可组合路径做 fusion；批量小调用；对标量自动 CPU 执行 |
| IIR scan 每 section 多 kernel | 四阶段层级 scan | 合并 tile/block scan、减少 global scratch；评估 cooperative/Graph 但先验证平台支持与收益 |
| Wiener 仍写 mean/variance 中间量 | tiled stats 后独立 apply | 尝试局部统计与 apply 融合、设备端完成 noise 标量路径 |
| Task 串行同步 | 每步 `measure_gpu_ms` device synchronize | 区分“测量模式”和“生产模式”；生产模式减少同步，必要时使用 event 依赖 |

### 8.3 显存层面

| 当前不足 | 证据 | 改进方向 |
|---|---|---|
| core cache 与 module workspace 是两套机制 | 代码结构 | 统一观测接口和容量预算，不必强行合并所有 ownership |
| 主链驻留但内部仍有小 D2H/fallback | noise/scale/widths/table/gust 路径 | 将可归约标量留在设备端参与后续 kernel；为动态参数提供 Device-native 准备路径；保留可验证 fallback |
| 当前报告只有前后 free memory/RSS，不含峰值时间线 | `metrics.json` | 在正式性能跑加入稳定采样的显存/利用率 telemetry，单独保存演示素材 |
| cache 容量扩大收益不足 | 历史仅 0.0958% | 优先缓存能消除明确 setup/H2D 的对象；用 reuse distance/命中统计决定容量 |

### 8.4 工程层面

| 当前不足 | 证据 | 改进方向 |
|---|---|---|
| 报告内部完整但当前源树有四项漂移 | report payload 338/338；source 691/695，差异为两个 task demo、BUILD_AND_RUN 与探索脚本；`git_commit=null` | 在最终答辩 commit 上重跑/复核，记录 commit 与 clean 状态，并把图表脚本纳入同一冻结 |
| input total 两侧工作不完全对称 | CPU 含场景/Host 参数构造，GPU 含已生成输入上传/Device 参数准备 | 同时发布 compute-only 与 application-total 口径，或把共同输入生成从两侧 total 中剥离 |
| GPU event 可用但不是 profiler 分解 | 14/14 有值；复合区间可含 copy、库调用和多个 kernel | 保留 event 审计，同时增加 profiler trace/硬件计数器；图中改称 stream work |
| Task2 contract 与默认实现有细节漂移 | contract 仍列 `copy_measurement_track_zx_gpu`，源码/报告是 `measurement_values = peak_track`、0 ms | 更新 contract，使 alias/no-CUDA 默认路径与报告 note 一致；继续区分主 fast path 与代表帧 public 校验 |
| benchmark README 与 JSON 口径漂移 | README 仍描述 8 项无 case；JSON 已提供 78 detailed + 8 aggregate | 更新说明文档，并在图表脚本强制按 `source` 分类，禁止静默混入 aggregate |
| 当前报告无现成 PNG/SVG/日志 | 报告发布策略明确排除 | 从 JSON/CSV 生成答辩专用图，脚本和输入一起冻结；不要截图终端替代全部图表 |

### 8.5 国产 GPU 适配层面

| 当前不足 | 证据 | 改进方向 |
|---|---|---|
| 部分 R2C 路径数值不稳定 | CSD/spectrogram 源码注释并回退 C2C | 建立最小复现与平台库版本矩阵；通过后再启用 R2C |
| shape/阈值策略手工编码 | 多处 if/阈值分派 | 建立离线参数扫描与设备 profile，生成可审计策略表；仍保留 deterministic fallback |
| CUDA-like ABI 容易被误解 | SDK 使用 `cuda*`/`cufft*` 名称 | PPT 明确“ZQ500 兼容 ABI”，展示平台适配层，不写成 NVIDIA CUDA 运行 |

### 8.6 优先级建议

1. **P0：冻结 commit 与证据口径**。记录 Git commit/clean 状态，修正 Task2 alias contract 和 benchmark README，并冻结制图脚本。
2. **P0：拆分 task total**。同时提供共同输入之后的 compute-only 与含输入准备的 application-total，避免高倍数被误解为纯 kernel 加速。
3. **P1：生产/测量模式分离**。保留可审计 event，同时减少正常任务中的逐步 synchronize，并补 profiler/hardware-counter 证据。
4. **P2：优化剩余热点**。优先 ambgfun、Task2 CWT/filter，再研究 IIR 多线 scan。
5. **P2：平台特化与离线策略生成**。以实测 profile 替代散落经验阈值，但不包装为当前已有能力。

---

## 9. PPT 可使用的真实素材

### 9.1 可截图的运行结果

| 素材 | 路径 | 建议用途 | 注意事项 |
|---|---|---|---|
| 当前验证总览 | `data/reports/summary.md` | 81/81、2/2、14/14、12/12 结果页 | 标注 run id 和“已发布运行” |
| Task1 L3 检测 | `data/reports/demo/task1_radar/final/metrics.json` | 注入/CPU/GPU bin 一致 | 建议重绘为简洁检测卡，不截整页 JSON |
| Task2 L3 轨迹 | `data/reports/demo/task2_features/final/metrics.json` | truth/CPU/GPU track 曲线 | 可直接从数组生成折线图 |
| Task L6 步骤 | `data/reports/demo/*/scales/L6/stage_timings.csv` | 两任务热点构成 | 这是最后一次迭代，不是五次中位 |
| 接口/任务审计 | `data/reports/validation/interfaces/`、`task_steps/` | 完整性证明 | 只摘核心数字 |
| 报告 provenance | `data/reports/provenance.json` | 备份页说明设备、run id 和 source fingerprint | 披露 `git_commit=null`、dirty 状态未记录；不要写成 clean commit |

当前报告不包含 PNG、SVG、console 日志或 telemetry；不存在可直接复用的“当前性能图”。

### 9.2 可以生成图表的数据

| 图表 | 数据源 | 推荐编码 |
|---|---|---|
| 78 个 detailed perf case 加速比分布 | `units/benchmarks/summary.json -> operators[].performance_cases` | 只取 `source=case_detail`；log 轴排序点图，1x 参考线；8 aggregate 另作注记 |
| Top/Bottom 代表算子 | 同上 | Top5 + Bottom5 分组条形图，不使用跨 case summary |
| CPU/GPU/kernel 三层时间 | `units/benchmarks/summary.csv` | Wiener、Periodogram、MVDR、lfilter 4 组对比 |
| Task1/Task2 scaling | `demo/*/scales/L1-L6/metrics.json -> repeat_runs` | 两张小图；时间与 speedup 分开；标“5 次中位，审计派生” |
| Task L6 hotspot 与 E2E/event 分账 | `stage_timings.csv` | 横向 stacked bar；标 input construction、final iteration，并把 event 称为 stream work |
| Task2 truth/track | Task2 final/L6 `metrics.json` | truth、CPU、GPU 三线，误差注记 |
| 正确性门禁 | benchmark summary + validation JSON | mixed error 与各自 tolerance，不画失真的 max-rel |
| 历史优化前后 | `docs/PERFORMANCE.md`、ledger 指定行 | 每项单独 before/after；明确 `[历史 A/B]` 与协议 |

### 9.3 可以展示的关键代码

| 技术 | 推荐代码片段 | 页面表达 |
|---|---|---|
| Wiener shared tile | `filtering.cu:989`、`:4301` | 只保留 Halo 装载、sync、局部窗口循环和分派条件 |
| IIR affine scan | `filtering.cu:2162`、`:2177`、`:2190` | 变换结构 + compose + scan 三个短片段 |
| Periodogram R2C/fusion | `spectral.cu:2041`、`:2060`、`:2095` | C2C 旧流程与当前 R2C pipeline 对比 |
| Host/Device 双态分派 | `types.hpp:873`、`:923`；`helpers.hpp:538` | `variant → get_if → Host 上传 / Device 直通`，用于解释“只在首尾搬运” |
| Device storage 浅层共享 | `types.hpp:722`、`:866`；`task2_features_demo.cpp:2094` | RAII 所有权与 `measurement_values = peak_track` 无 payload copy |
| DeviceStorage best-fit | `types.hpp:490` | cache block 搜索和自定义 deleter 回收示意 |
| 精确 Host 内容缓存 | `radartools.cu:1781`、`:2601` | 与驻留对比：相同 Host 输入重复调用时复用已上传副本 |
| Task1 设备驻留 | `task1_radar_demo.cpp:1221`、`:1236`、`:1287` | 连续返回 DeviceArray，最后统一 `.get()` |
| Task2 score-only | `task2_features_demo.cpp:1903`、`:1932`、`:1988`、`:2013` | 四路 score → fused feature → peak |
| Task2 固定尺寸 AOT | `task2_features_zx_gpu.cu:214`、`:2830`、`:3051` | radix-2 kernel、适用条件及 correlate/spectrogram 保留路径 |
| 成对/对称与 warp 归约 | `wavelets.cu:164`、`spectral.cu:861`、`:931` | 减少重复数学和同步；同时标明候选回退边界 |

代码页每次只显示 8～15 行；完整路径放脚注，不把源码截图当正文段落。

### 9.4 可以绘制的流程图和架构图

1. `public API → shared semantics → CPU/ZQ500 backend → task/test/report` 四层架构图。
2. `variant 位置分派 → Device-resident chain → .get()` 数据流图，与 `RAII → capacity cache → prepared/content cache` 资源流并列。
3. Wiener `16x16 output tile + Halo` 共享内存访问图。
4. IIR `sample affine transform → tile scan → block scan → apply` 四阶段图。
5. Periodogram `prepare+detrend+window → R2C → fused PSD` 前后流程对比。
6. Task1 六步 device-resident 流水线与五项应用优化标注。
7. Task2 CPU 逐帧完整中间量 vs GPU batched score-only 的上下对比图。
8. Task2 预编译 radix-2 task kernel、目标频带计算和 CWT max-score 的“完整中间量 → 紧凑输出”图。
9. `发现瓶颈 → 候选 A/B → 精度/E2E 门 → 保留或回退` 工程闭环图。

技术图必须由真实代码结构绘制，不使用 AI 生图替代 thread/block、内存或性能图。

### 9.5 团队分工和 AI 使用的证据缺口

当前精简仓库没有可作为团队分工事实源的成员表，也已删除旧协作记录。Git 历史只显示单一提交身份，不能据此推断真实团队分工。PPT 制作前必须由团队补充：

- 成员姓名与负责模块。
- 需求/接口设计、CPU reference、GPU kernel、Task、测试/性能、文档/答辩的实际责任人。
- 交叉复核关系，避免只写“共同完成”。

当前仓库也没有完整、可核验的 AI 工具使用台账。AI 页应由团队如实填写：

- 使用过的工具与用途，例如代码检索、方案讨论、测试脚本、文档整理。
- 哪些内容由人类复核：公式、接口、kernel、实验命令、结果与最终取舍。
- 明确 AI 未替代真实 ZQ500 执行、性能采集和最终工程决策。
- 不写无法证明的 token 数、代码占比或“AI 自动完成全部迁移”。

### 9.6 正式制图前的证据清单

- [x] `FILES.sha256` 338/338 通过。
- [ ] 最终 `SOURCE_FILES.sha256` 仍需处理 task demo、BUILD_AND_RUN 与探索脚本四项漂移（当前 691/695）。
- [x] 14/14 个任务步骤已有 error 和 GPU event 字段；measurement 的 0 ms 已确认是 no-CUDA alias。
- [ ] 在最终答辩 commit 上再次复核并记录 commit/clean 状态，避免只有内容 hash、没有 Git 绑定。
- [ ] 统一 Task2 measurement/fast-path 与 `task_step_contracts.json`。
- [ ] 更新 benchmark README；正式主图固定使用 78 detailed case 或 81 operator summary，并显式区分 8 aggregate。
- [ ] Task scaling 图明确 application-total 含 input construction，且 CPU/GPU 输入阶段工作不完全对称。
- [ ] 每张图保留 run id、设备、规模、warmup/repeat、统计量和证据路径。
- [ ] 历史 A/B 与当前 CPU/GPU 图使用不同视觉角标，禁止混算。
- [ ] 团队补齐分工和 AI 工具使用事实。

---

## 9.7 2026-07-21 正式 L1～L6 实测补充（正式性能页依据）

为消除旧规模曲线同时改变算法参数与输入规模、以及独立 `final-input` 未纳入曲线的口径问题，已在 ZQ500-Q QUAD-0 上按 `final_l1_l6_v1` 重测两条任务。每个规模启动 7 次，首轮仅 warm-up；CPU/GPU `total` 取其余 6 次中位数，`speedup` 在报告中直接计算为 `CPU median total / GPU median total`。所有 12 个点的验证均 PASS。

| 任务 | L1～L6 输入 | 固定项 | L6 CPU / GPU median total | L6 direct speedup | 正确性 |
|---|---|---|---:|---:|---|
| Task1 雷达检测 | `16×1536 → 128×4096` | 窗口、CFAR 参数与公开算子链 | `364.798 / 11.023 ms` | `33.09×` | Expected/CPU/GPU detection 均为 range 768、doppler 72；CFAR threshold mixed error `0.276398 < 0.5` |
| Task2 特征融合/跟踪 | `8×3072 → 128×3072` | filter、spectrogram、CWT、track、B=8、score-only | `28363.050 / 27.044 ms` | `1048.78×` | CPU/GPU peak track 一致；RMSE `0.477855 < 2`；feature-score mixed error `9.83703e-05 < 1e-4` |

完整曲线结论：Task1 为 `25.53×～33.09×`，可见固定开销影响；Task2 为 `415.96×～1048.78×`，随帧数增加释放批量并行度。L6 就是原 final-input；L1～L5 只改变输入规模，不再改变分块、阈值或算法语义。

L6 的 raw final GPU event（仅代表 stream work，不是单 kernel profiler）Top3 为：Task1 `ambgfun 3.208110 ms (29.84%)`、`input_construction 3.163750 ms (29.43%)`、`pulse_doppler 1.512064 ms (14.06%)`；Task2 `cwt 12.512743 ms (47.82%)`、`input_construction 4.077844 ms (15.58%)`、`spectrogram 3.773453 ms (14.42%)`。这些热点是后续独立 A/B 的优先级，不应与规模曲线混为同一个优化效果。

正式证据文件：

- `data/reports/demo/scale_summary.md` 与 `scale_summary.csv`：12 点汇总、统计方法和路径。
- `data/reports/demo/task1_radar/scales/L1…L6/metrics.json`、`task2_features/scales/L1…L6/metrics.json`：每次运行、参数、total、验证和原始结果。
- `ppt_work/data_tables/task_scaling.csv`、`l6_correctness.csv`、`l6_hotspots.csv`：P09/P11/P14/P16 可直接使用的制图表。
- `ppt_work/generated/P09_Task1_L1-L6_实测_v08.png`、`P11_Task2_L1-L6_实测_v08.png`、`P14_L6正确性_实测_v08.png`、`P16_L1-L6规模与热点_实测_v08.png`：真实数据渲染的页面成品。

---

## 审计后的 PPT 主线建议

根据最终叙事选择，采用您去年“两层技术路线”的升级版：

```text
封面 / 团队（用户自制，快速带过）
  → 赛题重述：交付对象、验收目标、三类难题
  → 两层技术路线：公共算子库优化 / 应用级算法构建
  → 三项公共技术各一页：原理 + 历史 A/B + 当前效果 + 边界
      Wiener Tile/Halo / IIR Affine Scan / FFT-PSD R2C+Fusion
  → 两条应用各两页：流程与核心技术 / 性能与正确性
      Task1 雷达检测 / Task2 batched score-only 多域跟踪
  → 当前软件架构、81 算子覆盖与公共执行机制
  → 当前正确性、算子分布、L1-L6 与瓶颈
  → 亮点与改进 → 工程结论 → 致谢（用户自制）
```

应用性能页不制作不存在的传统 GPU 对比，改用 CPU reference vs ZQ500 当前 application-total，加同一 ZQ500 实现内部的历史 A/B。该结构让每项公共技术和每条应用都紧邻真实性能效果，同时在 20 页、8:33 主讲预算下保留 87 秒机动。详细页序和讲解预算见 `ppt_work/deck_spec.md`。
