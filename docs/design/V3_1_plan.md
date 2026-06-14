# V3.2 `task2_features` 任务级 Demo 与 Python 可视化

## Summary

- 在 `demo/task2_features` 下新增任务二的正式任务级入口，交付形式与任务一保持一致：
  - 一个 C++/CUDA demo，完成完整“多域特征提取定位”链路并输出 CSV/JSON/Markdown
  - 一个 Python 可视化脚本，只消费 demo 产物，不独立重跑算法
- 版本默认推进为 `V3.2`，同步更新：
  - `README.md`
  - `docs/design/V3_2_plan.md`
  - `docs/submission/READMEV3_2.md`
- 场景与算法路线固定为已选方案：
  - 场景：单目标 + 单干扰 + 噪声
  - 特征链：`fm_demod + correlate + spectrogram + cwt("morlet2")`
  - 其余环节固定使用 `firwin + firfilter`、`bsplines::cubic`、`argrelmax`、`KalmanFilter`

## Key Changes

### 1. `demo/task2_features` 目录与入口

- 在 `demo/task2_features` 下新增：
  - `CMakeLists.txt`
  - `task2_features_demo.cpp`
  - `task2_features_cuda.hpp/.cu`
  - `visualize_task2.py`
  - `README.md`
- 根 `CMakeLists.txt` 接入 `demo/task2_features`，生成单一可执行目标 `task2_features_demo`。
- 不改 `run_all_tests.sh`；任务二 demo 不混入 unit 流程。

### 2. 固定场景与信号构造

- 任务二固定为“单目标特征轨迹 + 单干扰源 + 噪声”的多帧场景，不扩展到多目标。
- 场景参数固定：
  - `fs = 1e6`
  - `num_frames = 48`
  - `samples_per_frame = 1024`
  - `template_length = 256`
  - `target_start_sample_0 = 220`
  - `target_step_per_frame = 3`
  - `interferer_start_sample = 640`
  - `target_amplitude = 1.0`
  - `interferer_amplitude = 0.45`
  - `snr_db = 12`
  - `seed = 20260414`
- 波形生成固定至少使用 3 种 `waveforms` 算子，实际采用 4 种：
  - 目标模板：`chirp(type="complex")`
  - 目标包络：`gausspulse`
  - 干扰 1：`sawtooth`
  - 干扰 2：`square`
- 回波/输入构造固定为：
  - 每帧把目标模板插入到逐帧漂移的位置
  - 干扰信号固定插入到另一时域位置
  - 叠加复高斯白噪声
- CPU 负责一次性生成确定性输入；CPU/GPU 后续处理链共享同一份输入数据。

### 3. 任务二处理链

- 滤波：
  - `filter_design::firwin`
  - `filtering::firfilter`
  - 固定设计带通 FIR：
    - `numtaps = 129`
    - `cutoff = {60000, 220000}`
    - `pass_zero = "bandpass"`
    - `fs = 1e6`
    - `window = ("kaiser", 8.0)`
- B 样条平滑：
  - 用 `bsplines::cubic` 在固定偏移 `[-2, -1, 0, 1, 2]` 上生成权重
  - 权重归一化后用于平滑最终融合特征分数
- 四类特征提取固定如下：
  - 解调：`demod::fm_demod`
  - 相关性：`correlate::correlate(..., mode="same", method="fft")`
  - 谱分析：`spectral::spectrogram`
  - 小波：`wavelets::cwt(data, "morlet2", widths)`
- `spectrogram` 参数固定：
  - `window = "hann"`
  - `nperseg = 128`
  - `noverlap = 96`
  - `nfft = 256`
  - `mode = "magnitude"`
  - `scaling = "spectrum"`
- `cwt` 参数固定：
  - `wavelet = "morlet2"`
  - `widths = [4, 6, 8, ..., 32]`
  - 使用实部输入
- 特征融合固定为逐帧的一维定位分数：
  - `corr_score = normalize(abs(correlate_result))`
  - `demod_score = normalize(abs(fm_demod_result))`，尾部补 1 点对齐长度
  - `wavelet_score = normalize(max(abs(cwt_values), axis=0))`
  - `spectrogram_score = normalize(由 spectrogram 在目标频带积分得到的时间能量，并按最近邻映射到样本轴)`
  - `fused_score = 0.45 * corr_score + 0.20 * demod_score + 0.20 * wavelet_score + 0.15 * spectrogram_score`
  - 再对 `fused_score` 做 cubic B-spline 平滑
- 关键点定位：
  - 对平滑后的 `fused_score` 使用 `peak_finding::argrelmax(order=8, mode="clip")`
  - 若某帧没有峰，则回退到 `argmax(fused_score)`
  - 每帧输出一个 `peak_sample`
- 参数估计：
  - 用 `estimation::KalmanFilter(dim_x=2, dim_z=1, dim_u=0, points=1, dtype="float32")`
  - 状态定义为 `[position, velocity]`
  - 固定矩阵：
    - `F = [[1, 1], [0, 1]]`
    - `H = [[1, 0]]`
    - `Q = diag(0.25, 0.05)`
    - `R = [[4.0]]`
    - `P = diag(25.0, 4.0)`
  - 首帧测量初始化 `x = [first_peak, 0]^T`
  - 每帧用 `peak_sample` 作为观测，输出 `kalman_position`
- CPU 与 GPU 都执行完整链路，并输出：
  - 各阶段时间
  - 总时间
  - 关键中间结果误差
  - 峰值序列与 Kalman 轨迹对真值的误差

### 4. CUDA 实现与 demo 内复用

- 不改任何库公开接口；demo 内只新增任务级辅助代码。
- `task2_features_demo.cpp` 调用现有模块的 CPU/CUDA API；`task2_features_cuda.hpp/.cu` 只承接 demo 自己需要的局部 GPU 辅助：
  - 复信号功率/幅值
  - 一维分数归一化
  - `spectrogram` 时间能量积分
  - `cwt` 沿尺度取最大
  - 融合分数加权
  - 必要的逐帧 reduce 辅助
- demo 内引入 `thread_local Task2Workspace`，复用：
  - 输入上传 scratch
  - 中间分数缓冲
  - `spectrogram/cwt` 派生的一维特征缓冲
  - Kalman 输入缓冲
- 返回给最终写盘和统计的对象始终是独立结果；workspace 只复用内部 scratch。
- `gpu_e2e_perf` 口径保持与任务一一致：host 输入 + H2D + GPU 计算，不包含 `get()`。

### 5. 输出数据与报告

- C++ demo 固定写入：
  - `data/generated/demo/task2_features/input/`
  - `data/generated/demo/task2_features/output_samples/`
  - `data/reports/demo/task2_features/`
- `input/` 固定包含：
  - `scenario.json`
  - `target_template.csv`
  - `rx_frames.csv`
  - `truth_track.csv`
- `output_samples/` 固定同时输出 CPU/GPU 两套样本：
  - `filtered__cpu__values.csv` / `__gpu__values.csv`
  - `correlate__cpu__values.csv` / `__gpu__values.csv`
  - `spectrogram__cpu__values.csv` / `__gpu__values.csv`
  - `spectrogram_freqs__cpu__values.csv` / `__gpu__values.csv`
  - `spectrogram_times__cpu__values.csv` / `__gpu__values.csv`
  - `cwt__cpu__values.csv` / `__gpu__values.csv`
  - `feature_score__cpu__values.csv` / `__gpu__values.csv`
  - `peak_track__cpu__values.csv` / `__gpu__values.csv`
  - `kalman_track__cpu__values.csv` / `__gpu__values.csv`
- `reports/` 固定包含：
  - `latest_summary.md`
  - `latest_metrics.json`
  - `latest_stage_timings.csv`
- `latest_metrics.json` 固定记录：
  - 场景参数
  - 真值轨迹
  - CPU/GPU 峰值轨迹
  - CPU/GPU Kalman 轨迹
  - 各阶段时间
  - `filtered` / `correlate` / `spectrogram` / `cwt` / `feature_score` / `kalman_track` 误差统计
  - `cpu_gpu_track_match`
  - `gpu_matches_truth_within_tolerance`
- 任务二成功条件固定为：
  - CPU/GPU 每帧峰值位置一致
  - GPU Kalman 轨迹相对真值的 RMSE 小于等于 `2.0 samples`

### 6. Python 可视化脚本

- `visualize_task2.py` 只消费 C++ demo 输出，不独立重跑算法。
- Python 依赖固定只要求：
  - `python3`
  - `numpy`
  - `matplotlib`
- 固定输出 PNG 到 `data/reports/demo/task2_features/figures/`：
  - `target_template_components.png`
  - `raw_frame_real_imag.png`
  - `filtered_vs_raw_frame.png`
  - `correlate_trace_cpu_gpu.png`
  - `spectrogram_gpu.png`
  - `cwt_gpu.png`
  - `feature_score_peaks.png`
  - `kalman_track_vs_truth.png`
  - `stage_timing_bar.png`
- 图内容固定为：
  - 目标模板的复数实部/虚部及包络
  - 一帧原始输入实部/虚部
  - 滤波前后对比
  - 相关性曲线 CPU/GPU 对比
  - GPU `spectrogram` 热图
  - GPU `cwt` scalogram
  - 融合分数、峰值点和真值位置
  - 跨帧真值/CPU/GPU/Kalman 轨迹对比
  - CPU/GPU 分阶段时间柱状图
- 脚本同时生成 `figures/README.md`，列出图文件名和用途。

## Public Interfaces

- 不改任何库公开函数签名、返回类型、头文件注释或模块接口。
- 新增的公开入口只有任务级可执行：
  - `task2_features_demo`
- Python 脚本不是库 API，只是 `demo/task2_features` 下的辅助交付入口。

## Test Plan

- 构建：
  - `./scripts/build/build_v1.sh`
  - 单独确认 `task2_features_demo` 编译通过
- 运行：
  - 运行 `./build/demo/task2_features/task2_features_demo`
  - 再运行 `python3 demo/task2_features/visualize_task2.py`
- 验收标准：
  - demo 成功生成 `generated` 与 `reports`
  - CPU 和 GPU 都完成完整链路
  - CPU/GPU 峰值序列逐帧一致
  - GPU Kalman 轨迹 RMSE 对真值不超过 `2.0 samples`
  - `filtered`、`correlate`、`spectrogram`、`cwt`、`feature_score`、`kalman_track` 都有误差统计
  - Python 脚本成功生成全部 PNG 图
  - `latest_summary.md`、`latest_metrics.json`、`latest_stage_timings.csv` 与 `figures/` 内容一致
- 回归：
  - 现有 `tests/unit` 与 `run_all_tests.sh` 行为不变，不受 demo 接入影响

## Assumptions

- 版本号默认推进为 `V3.2`。
- 任务二 demo 继续采用“C++/CUDA demo + Python 只做可视化”的标准，不额外做 Python 算法实现。
- 任务二场景固定为“单目标 + 单干扰 + 噪声”的多帧基线，不扩展多目标。
- 四类特征提取固定采用：
  - `fm_demod`
  - `correlate`
  - `spectrogram`
  - `cwt("morlet2")`
- 滤波固定采用 `firwin + firfilter`，窗口固定为 `kaiser(8.0)`。
- `KalmanFilter` 保持当前接口，`dtype` 固定使用 `"float32"`。
