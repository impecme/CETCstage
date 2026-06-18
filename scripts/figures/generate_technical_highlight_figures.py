#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from textwrap import fill

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib import patches


REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = REPO_ROOT / "docs" / "submission" / "figures" / "technical_highlights"

FIGSIZE = (12.8, 7.2)
DPI = 300

COLORS = {
    "ink": "#263238",
    "muted": "#607d8b",
    "line": "#8fa3ad",
    "problem": "#d7e5ef",
    "solution": "#dcebdc",
    "value": "#f3ead5",
    "cache": "#e6def0",
    "device": "#d8e9f6",
    "host": "#eeeeee",
    "accent": "#3f6f8f",
    "accent2": "#5e8c61",
    "warn": "#a6611a",
    "good": "#4c7f52",
    "grid": "#edf2f5",
}


@dataclass(frozen=True)
class Highlight:
    slug: str
    category: str
    zh_name: str
    visual_focus: str
    problem: tuple[str, ...]
    solution: tuple[str, ...]
    value: tuple[str, ...]
    evidence: tuple[str, ...]
    tokens: tuple[str, ...]


HIGHLIGHTS: tuple[Highlight, ...] = (
    Highlight(
        "01_sosfilt_prefix_scan",
        "parallel",
        "sosfilt 递推算子 prefix-scan",
        "serial recurrence is converted into tiled affine transforms and prefix scan.",
        ("sample dependency", "serial state", "long sequence"),
        ("tile transform", "prefix scan", "apply initials"),
        ("parallel state propagation", "large-N throughput"),
        ("src/zhongkexin/filtering.cu", "tests/unit/filtering/test_sosfilt.cpp"),
        ("x[n-1] -> x[n]", "A_i, b_i", "scan(T_i)", "y[n]"),
    ),
    Highlight(
        "02_detrend_two_stage_reduction_kahan",
        "parallel",
        "detrend 两级 reduction 与 Kahan 补偿",
        "axis-wise sums are stabilized with partial/final reduction and Kahan compensation.",
        ("axis reduction", "float order", "CPU/ZQ500 drift"),
        ("partial sums", "Kahan local", "coeff apply"),
        ("single-precision alignment", "lower error"),
        ("src/zhongkexin/filtering.cu", "scripts/test/READMEV3_7_0.md"),
        ("sum_y", "sum_ty", "Kahan", "a*x+b"),
    ),
    Highlight(
        "03_batched_fft_frequency_acceleration",
        "parallel",
        "批量 FFT 频域加速",
        "batched FFT plans move radar/filtering/spectral workloads from host loops to device batches.",
        ("long signals", "segment loops", "PSD postprocess"),
        ("batch plan", "R2C/C2C", "device PSD"),
        ("higher throughput", "less host loop"),
        ("src/zhongkexin/radartools.cu", "src/zhongkexin/spectral.cu"),
        ("segments", "cuFFT batch", "R2C/C2C", "PSD"),
    ),
    Highlight(
        "04_ca_cfar_multi_strategy_integral_image",
        "parallel",
        "CA-CFAR 多策略积分图",
        "window geometry is split into direct, FFT convolution, and 2D integral-image paths.",
        ("guard window", "training cells", "edge cases"),
        ("direct 1D", "FFT long window", "integral image"),
        ("fast thresholds", "same CPU semantics"),
        ("src/zhongkexin/radartools.cu", "tests/unit/radartools/test_ca_cfar.cpp"),
        ("guard", "train", "prefix rows", "rect sum"),
    ),
    Highlight(
        "05_vectorstrength_lombscargle_parallel_reduction",
        "parallel",
        "vectorstrength/lombscargle 并行归约",
        "sample loops per period/frequency are mapped to shared-memory reductions.",
        ("per-period loop", "near-zero relative", "D2H sync"),
        ("partial kernel", "shared reduction", "finalize"),
        ("more parallelism", "device-resident mean/dot"),
        ("src/zhongkexin/spectral.cu", "scripts/test/READMEV3_8_4.md"),
        ("periods", "freq blocks", "sin/cos", "power"),
    ),
    Highlight(
        "06_fm_demod_phase_difference_fusion",
        "parallel",
        "fm_demod 相位差融合",
        "phase, unwrap, and diff are fused into adjacent complex-sample phase differences.",
        ("phase array", "unwrap pass", "diff pass"),
        ("adjacent samples", "phase diff kernel", "fallback path"),
        ("less intermediate data", "lower e2e cost"),
        ("src/zhongkexin/demod.cu", "tests/unit/demod/test_fm_demod.cpp"),
        ("z[n]", "conj(z[n-1])", "angle", "fm[n]"),
    ),
    Highlight(
        "07_pulse_doppler_safe_packing",
        "parallel",
        "pulse_doppler 安全 packing",
        "pulse/sample matrices are packed with explicit padding and truncation guards before batched FFT.",
        ("pulse matrix", "padding", "truncation"),
        ("safe pack", "pulse FFT", "boundary checks"),
        ("stable range-Doppler map", "no out-of-bounds"),
        ("src/zhongkexin/radartools.cu", "tests/unit/radartools/test_pulse_doppler.cpp"),
        ("pulse", "sample", "pack", "FFT_pulse"),
    ),
    Highlight(
        "08_mvdr_linear_algebra_path",
        "parallel",
        "MVDR 线性代数路径",
        "complex covariance and solves use cuBLAS/cuSOLVER instead of handwritten matrix kernels.",
        ("covariance", "complex solve", "numeric risk"),
        ("cublasCgemm", "LU factor", "solve + dot"),
        ("trusted primitives", "beam response"),
        ("src/zhongkexin/radartools.cu", "tests/unit/radartools/test_mvdr.cpp"),
        ("R = XX^H", "LU", "R^-1 a", "w^H x"),
    ),
    Highlight(
        "09_device_storage_cache",
        "cache",
        "DeviceStorage 分配缓存",
        "device allocations are recycled by type and device id to reduce fixed e2e overhead.",
        ("cudaMalloc", "cudaFree", "small ops"),
        ("type cache", "device-aware", "thread-local"),
        ("less allocation cost", "clear e2e view"),
        ("include/cusignal/core/types.hpp", "scripts/test/READMEV3_8_3.md"),
        ("Host API", "DeviceStorage", "cache hit", "kernel"),
    ),
    Highlight(
        "10_filtering_workspace_line_bases_cache",
        "cache",
        "FilteringWorkspace 与 line bases cache",
        "axis line bases and metadata are cached across repeated filtering calls.",
        ("axis lines", "shape metadata", "H2D repeats"),
        ("LineBasesCache", "cached breaks", "workspace buffers"),
        ("less metadata copy", "repeat stability"),
        ("src/zhongkexin/filtering.cu",),
        ("line bases", "shape/stride", "workspace", "timed path"),
    ),
    Highlight(
        "11_resample_channelizer_prepared_cache",
        "cache",
        "重采样与 channelizer prepared cache",
        "window, polyphase filter, and padded taps are prepared once and reused.",
        ("window build", "polyphase taps", "padded taps"),
        ("cache keys", "D2D reuse", "tap pruning"),
        ("lower setup cost", "stable large-gpu repeat"),
        ("src/zhongkexin/filtering.cu", "scripts/test/READMEV3_8_4.md"),
        ("resample", "poly filter", "channel taps", "upfirdn"),
    ),
    Highlight(
        "12_wiener_deterministic_reduction",
        "cache",
        "wiener deterministic reduction",
        "auto-noise estimation stays on device with deterministic two-stage reduction.",
        ("atomic sum", "noise estimate", "repeat jitter"),
        ("local stats", "block sum", "apply noise"),
        ("reproducible error", "device-resident"),
        ("src/zhongkexin/filtering.cu", "scripts/test/READMEV3_8_1.md"),
        ("local mean", "variance", "final sum", "apply"),
    ),
    Highlight(
        "13_spectral_workspace_segment_window_plan_reuse",
        "cache",
        "SpectralWorkspace 分段窗与 plan 复用",
        "segment window, scaling, axes, and real FFT plans are reused across spectral calls.",
        ("window H2D", "segment prep", "FFT plan"),
        ("segment key", "real plan", "R2C fast path"),
        ("higher spectral throughput", "less setup"),
        ("src/zhongkexin/spectral.cu", "tests/unit/spectral/test_spectrogram.cpp"),
        ("window", "segments", "R2C plan", "PSD"),
    ),
    Highlight(
        "14_firwin2_full_spectrum_template_cache",
        "cache",
        "firwin2 full-spectrum template cache",
        "full-spectrum templates and windows are cached before timed FFT extraction.",
        ("interp response", "full spectrum", "FFT setup"),
        ("prepared cache", "template D2D", "extract taps"),
        ("timed device path", "filter design speed"),
        ("src/zhongkexin/filter_design.cu", "scripts/test/READMEV3_8_3.md"),
        ("freq/gain", "spectrum template", "FFT", "taps"),
    ),
    Highlight(
        "15_chebwin_window_workspace_cache",
        "cache",
        "chebwin WindowWorkspace 缓存",
        "Chebyshev frequency response and normalized final windows are cached in workspace.",
        ("response build", "FFT", "normalize max"),
        ("GPU template", "CUB max", "final cache"),
        ("repeat mostly D2D", "fast large window"),
        ("src/zhongkexin/windows.cu", "scripts/test/READMEV3_8_4.md"),
        ("freq response", "IFFT", "max", "window"),
    ),
    Highlight(
        "16_ambgfun_tile_fft_normalized_cache",
        "cache",
        "ambgfun tile FFT 与归一化缓存",
        "normalized inputs and tiled FFT workspace control memory pressure for the 2D ambiguity surface.",
        ("2D surface", "large output", "memory pressure"),
        ("normalized cache", "tile rows", "2D FFT workspace"),
        ("bounded peak memory", "visible bottleneck"),
        ("src/zhongkexin/radartools.cu", "scripts/test/READMEV3_8_4.md"),
        ("delay", "doppler", "tile FFT", "surface"),
    ),
    Highlight(
        "17_cwt_wavelet_kernel_cache_shared_tile",
        "cache",
        "CWT 小波核缓存与 shared-memory tile",
        "wavelet kernel tables are cached and ricker loads are tiled in shared memory.",
        ("width loop", "kernel table", "global loads"),
        ("kernel cache", "width key", "shared tile"),
        ("less H2D", "less repeated load"),
        ("src/zhongkexin/wavelets.cu", "tests/unit/wavelets/test_cwt.cpp"),
        ("widths", "wavelet table", "shared tile", "CWT"),
    ),
    Highlight(
        "18_task2_fused_postprocessing",
        "pipeline",
        "Task2 fused 后处理",
        "feature smoothing, peak tracking, and Kalman smoothing stay on device.",
        ("stage returns", "Host sync", "feature fusion"),
        ("fused score", "row peaks", "track kernel"),
        ("device pipeline", "lower e2e overhead"),
        ("demo/task2_features/task2_features_zx_gpu.cu",),
        ("features", "smooth", "peaks", "track"),
    ),
    Highlight(
        "19_kalman_points_batched_fast_path",
        "pipeline",
        "Kalman points-batched fast path",
        "many small Kalman states are batched and fixed dimensions use register kernels.",
        ("small state", "serial track", "low occupancy"),
        ("points batch", "fixed dim", "register path"),
        ("enough parallelism", "task RMSE gate"),
        ("src/zhongkexin/estimation.cu", "tests/unit/estimation/test_kalman_filter.cpp"),
        ("points", "predict", "update", "RMSE"),
    ),
    Highlight(
        "20_peak_select_cub_path",
        "pipeline",
        "峰值筛选 CUB 路径",
        "flagged extrema are compacted with CUB instead of handwritten collection loops.",
        ("compare mask", "index compact", "manual scan"),
        ("DeviceSelect", "flagged indices", "device output"),
        ("fast peak list", "Task2 localization"),
        ("src/zhongkexin/peak_finding.cu", "tests/unit/peak_finding/"),
        ("mask", "CUB select", "indices", "peaks"),
    ),
    Highlight(
        "21_task1_radar_pipeline",
        "pipeline",
        "Task1 雷达链路组合",
        "radar operators are connected into a validated range-Doppler detection pipeline.",
        ("single op pass", "not enough", "business result"),
        ("pulse compression", "pulse Doppler", "CA-CFAR + ambgfun"),
        ("target hit", "e2e evidence"),
        ("demo/task1_radar/", "data/reports/demo/task1_radar/"),
        ("echo", "matched filter", "Doppler map", "detections"),
    ),
    Highlight(
        "22_task2_multidomain_pipeline",
        "pipeline",
        "Task2 多域链路组合",
        "filtering, demodulation, correlation, spectrogram, CWT, and tracking use task-level gates.",
        ("mixed metrics", "track truth", "multi-domain"),
        ("filter + demod", "spectrogram + CWT", "Kalman gate"),
        ("track match", "RMSE validation"),
        ("demo/task2_features/", "data/reports/demo/task2_features/"),
        ("signal", "features", "score", "track"),
    ),
    Highlight(
        "23_unit_test_unified_reporting",
        "report",
        "81 个单测入口统一报告",
        "unit tests write the same metrics, summary, and cases schema across modules.",
        ("many modules", "different outputs", "manual merge"),
        ("common report", "JSON + CSV", "summary md"),
        ("traceable cases", "schema consistency"),
        ("tests/unit/common/report.hpp", "tests/unit/**/test_*.cpp"),
        ("test_*.cpp", "latest_metrics", "cases.csv", "summary.md"),
    ),
    Highlight(
        "24_all_ops_six_scale_benchmark",
        "report",
        "53 算子六档 benchmark",
        "scale families expose copy-bound small cases and throughput large cases.",
        ("single scale", "cherry-pick risk", "copy-bound"),
        ("L1-L6", "e2e/kernel", "mixed_error"),
        ("scale trend", "fair comparison"),
        ("scripts/test/benchmark_all_ops_scales.py",),
        ("53 ops", "L1..L6", "speedup", "error"),
    ),
    Highlight(
        "25_gpu_only_cpu_baseline_cache",
        "report",
        "GPU-only 复测与 CPU baseline cache",
        "GPU timing can be refreshed while CPU baseline and accuracy status stay fixed.",
        ("full CPU timing", "slow onsite retest", "baseline drift"),
        ("gpu-only", "reuse cache", "refresh option"),
        ("fast retest", "known baseline"),
        ("scripts/test/benchmark_all_ops_scales.py", "scripts/test/README.md"),
        ("CPU JSON", "GPU timing", "reuse", "CSV"),
    ),
    Highlight(
        "26_precision_audit_pipeline",
        "report",
        "全量精度审计 pipeline",
        "precision baseline, fix queue, and perf snapshots are generated as one audit trail.",
        ("hidden errors", "manual checks", "fix tracking"),
        ("audit script", "baseline CSV", "fix queue"),
        ("repeatable risk list", "submit ready"),
        ("scripts/test/audit_all_ops_precision.py", "data/reports/unit/audit/"),
        ("baseline", "queue", "snapshot", "report"),
    ),
    Highlight(
        "27_task_demo_self_validation",
        "report",
        "Task demo 自验收",
        "demos return nonzero on failed validation and write validation/resource/repeat records.",
        ("pretty figure only", "no pass/fail", "manual judge"),
        ("ValidationResult", "repeat_runs", "resource_usage"),
        ("CI-like demo", "business gate"),
        ("demo/task1_radar/", "demo/task2_features/"),
        ("run demo", "validation", "metrics JSON", "pass/fail"),
    ),
    Highlight(
        "28_invalid_input_resource_drift_gate",
        "report",
        "异常输入与资源漂移 gate",
        "invalid configs and repeat resource drift are explicit task-level gates.",
        ("happy path only", "leak risk", "unclear errors"),
        ("invalid checks", "jitter", "GPU/RSS drift"),
        ("robustness evidence", "stable repeat"),
        ("scripts/test/READMEV3_9.md", "scripts/test/run_task_demos.sh"),
        ("bad config", "std::invalid_argument", "drift", "gate"),
    ),
    Highlight(
        "29_compute_sanitizer_deep_check",
        "report",
        "compute-sanitizer 深检",
        "memcheck runs as a deep check while timing gates are skipped to avoid polluted metrics.",
        ("timing inflation", "mem errors", "latest pollution"),
        ("leak-check", "memcheck", "skip timing"),
        ("deep memory evidence", "clean metrics"),
        ("scripts/test/run_task_demos.sh", "data/reports/demo/leak_check/"),
        ("normal run", "memcheck", "skip timing", "restore"),
    ),
    Highlight(
        "30_plot_report_generation_pipeline",
        "report",
        "图件与报告生成 pipeline",
        "benchmark and task CSV artifacts flow into publication-style Word/PPT figures.",
        ("raw CSV", "manual plotting", "inconsistent figures"),
        ("plot scripts", "PNG/SVG/PDF", "README index"),
        ("reproducible visuals", "answer evidence"),
        ("scripts/test/plot_all_ops_benchmark.py", "scripts/test/plot_task_demo_scale_benchmark.py"),
        ("CSV", "plot", "figures", "Word/PPT"),
    ),
)


def setup_style() -> None:
    plt.rcParams.update(
        {
            "font.family": ["Droid Sans Fallback", "DejaVu Sans"],
            "font.size": 10,
            "axes.linewidth": 0.8,
            "axes.unicode_minus": False,
            "figure.facecolor": "white",
            "savefig.facecolor": "white",
            "savefig.dpi": DPI,
            "svg.fonttype": "none",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )


ZH_TEXT = {
    "sample dependency": "样本依赖",
    "serial state": "串行状态",
    "long sequence": "长序列",
    "tile transform": "分块状态变换",
    "prefix scan": "前缀扫描",
    "apply initials": "初值回填",
    "parallel state propagation": "并行状态传播",
    "large-N throughput": "大规模吞吐提升",
    "axis reduction": "按轴归约",
    "float order": "单精度累积顺序",
    "CPU/ZQ500 drift": "CPU/ZQ500 偏差",
    "partial sums": "分块部分和",
    "Kahan local": "局部 Kahan 补偿",
    "coeff apply": "系数回写",
    "single-precision alignment": "单精度口径对齐",
    "lower error": "误差降低",
    "long signals": "长序列输入",
    "segment loops": "分段循环",
    "PSD postprocess": "PSD 后处理",
    "batch plan": "批量 plan",
    "device PSD": "Device 侧 PSD",
    "higher throughput": "吞吐提升",
    "less host loop": "减少 Host 循环",
    "guard window": "保护窗",
    "training cells": "训练单元",
    "edge cases": "边界处理",
    "direct 1D": "1D 直接核",
    "FFT long window": "长窗 FFT",
    "integral image": "积分图",
    "fast thresholds": "阈值快速计算",
    "same CPU semantics": "保持 CPU 语义",
    "per-period loop": "逐周期循环",
    "near-zero relative": "近零相对误差",
    "D2H sync": "D2H 同步",
    "partial kernel": "部分和 Kernel",
    "shared reduction": "共享内存归约",
    "finalize": "最终归约",
    "more parallelism": "并行度提升",
    "device-resident mean/dot": "均值/dot 保留 Device",
    "phase array": "相位数组",
    "unwrap pass": "unwrap 阶段",
    "diff pass": "差分阶段",
    "adjacent samples": "相邻样本",
    "phase diff kernel": "相位差 Kernel",
    "fallback path": "兼容路径",
    "less intermediate data": "减少中间数据",
    "lower e2e cost": "降低 e2e 开销",
    "pulse matrix": "脉冲矩阵",
    "padding": "填充",
    "truncation": "截断",
    "safe pack": "安全打包",
    "pulse FFT": "脉冲维 FFT",
    "boundary checks": "边界检查",
    "stable range-Doppler map": "稳定距离-多普勒图",
    "no out-of-bounds": "避免越界",
    "covariance": "协方差矩阵",
    "complex solve": "复数线性求解",
    "numeric risk": "数值风险",
    "LU factor": "LU 分解",
    "solve + dot": "求解 + dot",
    "trusted primitives": "成熟库原语",
    "beam response": "波束响应",
    "cudaMalloc": "cudaMalloc 分配",
    "cudaFree": "cudaFree 释放",
    "small ops": "小粒度算子",
    "type cache": "类型缓存",
    "device-aware": "设备感知",
    "thread-local": "线程本地",
    "less allocation cost": "减少分配开销",
    "clear e2e view": "e2e 口径更清晰",
    "axis lines": "按轴线处理",
    "shape metadata": "shape 元数据",
    "H2D repeats": "重复 H2D",
    "LineBasesCache": "LineBasesCache",
    "cached breaks": "breaks 缓存",
    "workspace buffers": "Workspace buffer",
    "less metadata copy": "减少元数据拷贝",
    "repeat stability": "repeat 更稳定",
    "window build": "窗口构造",
    "polyphase taps": "多相 taps",
    "padded taps": "补齐 taps",
    "cache keys": "Cache key",
    "D2D reuse": "D2D 复用",
    "tap pruning": "tap 裁剪",
    "lower setup cost": "降低准备开销",
    "stable large-gpu repeat": "large-gpu repeat 稳定",
    "atomic sum": "原子累加",
    "noise estimate": "噪声估计",
    "repeat jitter": "repeat 抖动",
    "local stats": "局部统计",
    "block sum": "分块求和",
    "apply noise": "噪声回写",
    "reproducible error": "误差可复现",
    "device-resident": "Device 驻留",
    "window H2D": "窗口 H2D",
    "segment prep": "分段准备",
    "FFT plan": "FFT plan",
    "segment key": "segment key",
    "real plan": "实数 plan",
    "R2C fast path": "R2C 快路径",
    "higher spectral throughput": "谱分析吞吐提升",
    "less setup": "减少准备",
    "interp response": "响应插值",
    "full spectrum": "全频谱",
    "FFT setup": "FFT 准备",
    "prepared cache": "prepared Cache",
    "template D2D": "模板 D2D",
    "extract taps": "提取 taps",
    "timed device path": "Device 计时路径",
    "filter design speed": "滤波器设计加速",
    "response build": "响应构造",
    "normalize max": "最大值归一化",
    "GPU template": "GPU 模板",
    "CUB max": "CUB 最大值",
    "final cache": "最终 Cache",
    "repeat mostly D2D": "repeat 主要为 D2D",
    "fast large window": "大窗口快速生成",
    "2D surface": "二维曲面",
    "large output": "大输出",
    "memory pressure": "显存压力",
    "normalized cache": "归一化 Cache",
    "tile rows": "分块行",
    "2D FFT workspace": "2D FFT Workspace",
    "bounded peak memory": "峰值显存受控",
    "visible bottleneck": "瓶颈可定位",
    "width loop": "尺度循环",
    "kernel table": "小波核表",
    "global loads": "global load",
    "kernel cache": "Kernel Cache",
    "width key": "width key",
    "shared tile": "shared-memory tile",
    "less H2D": "减少 H2D",
    "less repeated load": "减少重复读取",
    "stage returns": "阶段回传",
    "Host sync": "Host 同步",
    "feature fusion": "特征融合",
    "fused score": "融合得分",
    "row peaks": "逐行峰值",
    "track kernel": "轨迹 Kernel",
    "device pipeline": "Device 流水线",
    "lower e2e overhead": "降低 e2e 开销",
    "small state": "小状态",
    "serial track": "串行轨迹",
    "low occupancy": "占用率不足",
    "points batch": "点批处理",
    "fixed dim": "固定维度",
    "register path": "寄存器路径",
    "enough parallelism": "并行度充足",
    "task RMSE gate": "任务 RMSE gate",
    "compare mask": "比较 mask",
    "index compact": "索引压缩",
    "manual scan": "手写 scan",
    "DeviceSelect": "DeviceSelect",
    "flagged indices": "标记索引",
    "device output": "Device 输出",
    "fast peak list": "快速峰值列表",
    "Task2 localization": "Task2 定位",
    "single op pass": "单算子通过",
    "not enough": "不足以验收任务",
    "business result": "业务结果",
    "pulse compression": "脉冲压缩",
    "pulse Doppler": "脉冲多普勒",
    "CA-CFAR + ambgfun": "CA-CFAR + ambgfun",
    "target hit": "目标命中",
    "e2e evidence": "e2e 证据",
    "mixed metrics": "多指标口径",
    "track truth": "轨迹真值",
    "multi-domain": "多域特征",
    "filter + demod": "滤波 + 解调",
    "spectrogram + CWT": "spectrogram + CWT",
    "Kalman gate": "Kalman gate",
    "track match": "轨迹匹配",
    "RMSE validation": "RMSE 验证",
    "many modules": "多模块",
    "different outputs": "多输出类型",
    "manual merge": "人工汇总",
    "common report": "统一报告层",
    "JSON + CSV": "JSON + CSV",
    "summary md": "summary.md",
    "traceable cases": "case 可追溯",
    "schema consistency": "schema 一致",
    "single scale": "单一规模",
    "cherry-pick risk": "选点风险",
    "copy-bound": "copy-bound",
    "L1-L6": "L1-L6",
    "e2e/kernel": "e2e/kernel",
    "mixed_error": "mixed_error",
    "scale trend": "规模趋势",
    "fair comparison": "公平对比",
    "full CPU timing": "完整 CPU 计时",
    "slow onsite retest": "现场复测慢",
    "baseline drift": "基线漂移",
    "gpu-only": "GPU-only",
    "reuse cache": "复用 Cache",
    "refresh option": "可刷新",
    "fast retest": "快速复测",
    "known baseline": "固定基线",
    "hidden errors": "隐藏误差",
    "manual checks": "人工抽查",
    "fix tracking": "修复跟踪",
    "audit script": "审计脚本",
    "baseline CSV": "baseline CSV",
    "fix queue": "修复队列",
    "repeatable risk list": "可复跑风险清单",
    "submit ready": "提交前体检",
    "pretty figure only": "只有展示图",
    "no pass/fail": "无 pass/fail",
    "manual judge": "人工判断",
    "ValidationResult": "ValidationResult",
    "repeat_runs": "repeat_runs",
    "resource_usage": "resource_usage",
    "CI-like demo": "CI 式 demo",
    "business gate": "业务 gate",
    "happy path only": "仅正常路径",
    "leak risk": "泄露风险",
    "unclear errors": "错误不明确",
    "invalid checks": "异常输入检查",
    "jitter": "耗时抖动",
    "GPU/RSS drift": "GPU/RSS 漂移",
    "robustness evidence": "鲁棒性证据",
    "stable repeat": "repeat 稳定",
    "timing inflation": "计时放大",
    "mem errors": "内存错误",
    "latest pollution": "污染 latest",
    "leak-check": "leak-check",
    "memcheck": "memcheck",
    "skip timing": "跳过 timing",
    "deep memory evidence": "深度内存证据",
    "clean metrics": "metrics 干净",
    "raw CSV": "原始 CSV",
    "manual plotting": "手工作图",
    "inconsistent figures": "图件不一致",
    "plot scripts": "作图脚本",
    "PNG/SVG/PDF": "PNG/SVG/PDF",
    "README index": "README 索引",
    "reproducible visuals": "可复现图件",
    "answer evidence": "答辩证据",
    "segments": "分段",
    "cuFFT batch": "cuFFT batch",
    "guard": "保护窗",
    "train": "训练窗",
    "prefix rows": "行前缀和",
    "rect sum": "矩形求和",
    "periods": "周期",
    "freq blocks": "频率块",
    "sin/cos": "sin/cos",
    "power": "功率",
    "pack": "打包",
    "FFT_pulse": "FFT_pulse",
    "window": "窗口",
    "segments": "分段",
    "taps": "taps",
    "delay": "时延",
    "doppler": "多普勒",
    "surface": "曲面",
    "features": "特征",
    "smooth": "平滑",
    "peaks": "峰值",
    "track": "轨迹",
    "points": "点批",
    "predict": "预测",
    "update": "更新",
    "mask": "mask",
    "indices": "索引",
    "echo": "回波",
    "matched filter": "匹配滤波",
    "Doppler map": "多普勒图",
    "detections": "检测结果",
    "signal": "信号",
    "score": "得分",
    "test_*.cpp": "test_*.cpp",
    "latest_metrics": "latest_metrics",
    "cases.csv": "cases.csv",
    "summary.md": "summary.md",
    "53 ops": "53 算子",
    "L1..L6": "L1..L6",
    "speedup": "加速比",
    "error": "误差",
    "CPU JSON": "CPU JSON",
    "GPU timing": "GPU timing",
    "reuse": "复用",
    "baseline": "baseline",
    "queue": "队列",
    "snapshot": "快照",
    "report": "报告",
    "run demo": "运行 demo",
    "validation": "validation",
    "metrics JSON": "metrics JSON",
    "pass/fail": "pass/fail",
    "bad config": "非法配置",
    "std::invalid_argument": "std::invalid_argument",
    "drift": "漂移",
    "gate": "gate",
    "normal run": "正常运行",
    "restore": "恢复 latest",
    "CSV": "CSV",
    "plot": "作图",
    "figures": "图件",
    "Word/PPT": "Word/PPT",
}


def zh(text: str) -> str:
    return ZH_TEXT.get(text, text)


def wrap_text(text: str, width: int) -> str:
    if any("\u4e00" <= ch <= "\u9fff" for ch in text) and " " not in text:
        return "\n".join(text[index : index + width] for index in range(0, len(text), width))
    return fill(text, width)


def make_axes() -> tuple[plt.Figure, plt.Axes]:
    fig, ax = plt.subplots(figsize=FIGSIZE)
    ax.set_xlim(0, 16)
    ax.set_ylim(0, 9)
    ax.axis("off")
    fig.subplots_adjust(left=0, right=1, bottom=0, top=1)
    return fig, ax


def rounded_box(
    ax: plt.Axes,
    x: float,
    y: float,
    w: float,
    h: float,
    text: str,
    *,
    face: str,
    edge: str | None = None,
    fontsize: float = 10,
    weight: str = "normal",
    lines: int = 18,
) -> patches.FancyBboxPatch:
    box = patches.FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.02,rounding_size=0.08",
        linewidth=1.1,
        edgecolor=edge or COLORS["line"],
        facecolor=face,
    )
    ax.add_patch(box)
    ax.text(
        x + w / 2,
        y + h / 2,
        wrap_text(text, lines),
        ha="center",
        va="center",
        fontsize=fontsize,
        color=COLORS["ink"],
        fontweight=weight,
    )
    return box


def arrow(ax: plt.Axes, x1: float, y1: float, x2: float, y2: float, *, color: str | None = None) -> None:
    ax.annotate(
        "",
        xy=(x2, y2),
        xytext=(x1, y1),
        arrowprops=dict(
            arrowstyle="-|>",
            lw=1.25,
            color=color or COLORS["accent"],
            shrinkA=4,
            shrinkB=4,
            mutation_scale=12,
        ),
    )


def small_label(ax: plt.Axes, x: float, y: float, text: str, *, color: str | None = None, fontsize: float = 8.4) -> None:
    ax.text(x, y, text, ha="left", va="center", fontsize=fontsize, color=color or COLORS["muted"])


def evidence(ax: plt.Axes, h: Highlight) -> None:
    text = " | ".join(h.evidence)
    ax.text(
        15.55,
        0.34,
        fill(text, 70),
        ha="right",
        va="bottom",
        fontsize=7.2,
        color=COLORS["muted"],
    )


def draw_wave(ax: plt.Axes, x: float, y: float, w: float, h: float, *, color: str = "#4c7899") -> None:
    t = np.linspace(0, 1, 180)
    yy = y + h * (0.5 + 0.28 * np.sin(2 * np.pi * (4 * t + 0.08)) * np.exp(-0.3 * t))
    xx = x + w * t
    ax.plot(xx, yy, color=color, lw=1.5)
    ax.plot([x, x + w], [y + h * 0.5, y + h * 0.5], color=COLORS["line"], lw=0.6, alpha=0.55)


def draw_grid(ax: plt.Axes, x: float, y: float, w: float, h: float, rows: int, cols: int, *, active: tuple[int, int] | None = None) -> None:
    ax.add_patch(patches.Rectangle((x, y), w, h, fill=False, edgecolor=COLORS["line"], lw=0.9))
    for i in range(1, cols):
        ax.plot([x + w * i / cols, x + w * i / cols], [y, y + h], color=COLORS["grid"], lw=0.8)
    for j in range(1, rows):
        ax.plot([x, x + w], [y + h * j / rows, y + h * j / rows], color=COLORS["grid"], lw=0.8)
    if active:
        row, col = active
        ax.add_patch(
            patches.Rectangle(
                (x + w * col / cols, y + h * row / rows),
                w / cols,
                h / rows,
                facecolor="#bfd8cc",
                edgecolor=COLORS["good"],
                lw=0.8,
                alpha=0.9,
            )
        )


def draw_metric(ax: plt.Axes, x: float, y: float, label: str, value: str, *, color: str = "#5e8c61") -> None:
    ax.plot([x, x + 1.35], [y, y], color=color, lw=2.0)
    ax.text(x + 1.5, y, label, ha="left", va="center", fontsize=8.5, color=COLORS["muted"])
    ax.text(x + 1.5, y - 0.38, value, ha="left", va="center", fontsize=10.5, color=COLORS["ink"], fontweight="bold")


def panel(ax: plt.Axes, x: float, y: float, w: float, h: float, label: str, *, edge: str = "#c8d3da") -> None:
    ax.add_patch(
        patches.FancyBboxPatch(
            (x, y),
            w,
            h,
            boxstyle="round,pad=0.015,rounding_size=0.06",
            linewidth=0.9,
            edgecolor=edge,
            facecolor="#fbfcfd",
            alpha=0.96,
        )
    )
    ax.text(
        x + 0.22,
        y + h - 0.32,
        label,
        ha="left",
        va="center",
        fontsize=8.2,
        color=COLORS["muted"],
        fontweight="bold",
    )


def mini_bar_chart(
    ax: plt.Axes,
    x: float,
    y: float,
    w: float,
    h: float,
    labels: tuple[str, ...],
    values: tuple[float, ...],
    *,
    color: str = "#5c8da8",
) -> None:
    ax.add_patch(patches.Rectangle((x, y), w, h, facecolor="#ffffff", edgecolor=COLORS["grid"], lw=0.8))
    ymax = max(values) if values else 1.0
    count = len(values)
    for i, (label, value) in enumerate(zip(labels, values)):
        bw = w / max(count, 1) * 0.52
        bx = x + w * (i + 0.26) / max(count, 1)
        bh = h * 0.72 * value / ymax
        ax.add_patch(patches.Rectangle((bx, y + 0.28), bw, bh, facecolor=color, edgecolor="none", alpha=0.82))
        ax.text(bx + bw / 2, y + 0.12, zh(label), ha="center", va="bottom", fontsize=6.4, color=COLORS["muted"])
    ax.plot([x + 0.15, x + w - 0.08], [y + 0.28, y + 0.28], color=COLORS["line"], lw=0.6)


def mini_heatmap(ax: plt.Axes, x: float, y: float, w: float, h: float, *, seed: int) -> None:
    rng = np.random.default_rng(seed)
    data = rng.normal(size=(8, 12))
    data = np.cumsum(data, axis=1)
    data = (data - data.min()) / max(float(data.max() - data.min()), 1.0e-6)
    rows, cols = data.shape
    for r in range(rows):
        for c in range(cols):
            value = data[r, c]
            color = (
                0.92 - 0.28 * value,
                0.96 - 0.12 * value,
                0.98 - 0.02 * value,
            )
            ax.add_patch(
                patches.Rectangle(
                    (x + w * c / cols, y + h * r / rows),
                    w / cols,
                    h / rows,
                    facecolor=color,
                    edgecolor="#ffffff",
                    lw=0.15,
                )
            )
    ax.add_patch(patches.Rectangle((x, y), w, h, fill=False, edgecolor=COLORS["line"], lw=0.7))


def mini_curve(ax: plt.Axes, x: float, y: float, w: float, h: float, *, kind: str = "speed") -> None:
    t = np.linspace(0.0, 1.0, 160)
    if kind == "speed":
        y1 = 0.16 + 0.68 * (1.0 - np.exp(-4.0 * t))
        y2 = 0.13 + 0.20 * np.log1p(5.0 * t) / np.log(6.0)
        ax.plot(x + w * t, y + h * y1, color=COLORS["good"], lw=1.6)
        ax.plot(x + w * t, y + h * y2, color=COLORS["warn"], lw=1.3, linestyle="--")
    elif kind == "error":
        y1 = 0.70 * np.exp(-4.0 * t) + 0.14
        ax.plot(x + w * t, y + h * y1, color="#8c5f7e", lw=1.5)
        ax.fill_between(x + w * t, y + h * y1, y + h * 0.08, color="#eadff0", alpha=0.65)
    else:
        y1 = 0.48 + 0.22 * np.sin(2 * np.pi * (2.5 * t + 0.07))
        ax.plot(x + w * t, y + h * y1, color=COLORS["accent"], lw=1.4)
    ax.add_patch(patches.Rectangle((x, y), w, h, fill=False, edgecolor=COLORS["grid"], lw=0.7))


def mini_timeline(ax: plt.Axes, x: float, y: float, w: float, h: float, labels: tuple[str, ...]) -> None:
    ax.add_patch(patches.Rectangle((x, y + h * 0.43), w, h * 0.14, facecolor=COLORS["grid"], edgecolor="none"))
    count = len(labels)
    for i, label in enumerate(labels):
        cx = x + w * (i + 0.5) / count
        ax.add_patch(patches.Circle((cx, y + h * 0.5), 0.095, facecolor=COLORS["accent"], edgecolor="white", lw=0.8))
        ax.text(cx, y + 0.03, zh(label), ha="center", va="bottom", fontsize=6.2, color=COLORS["muted"])


def mini_memory_blocks(ax: plt.Axes, x: float, y: float, w: float, h: float, *, active: int = 4) -> None:
    cols = 8
    rows = 3
    gap = 0.035
    for r in range(rows):
        for c in range(cols):
            idx = r * cols + c
            face = "#d9e8f3" if idx < active else "#f4f7f8"
            ax.add_patch(
                patches.Rectangle(
                    (x + c * w / cols + gap, y + r * h / rows + gap),
                    w / cols - 2 * gap,
                    h / rows - 2 * gap,
                    facecolor=face,
                    edgecolor=COLORS["line"],
                    lw=0.3,
                )
            )
    ax.add_patch(patches.Rectangle((x, y), w, h, fill=False, edgecolor=COLORS["line"], lw=0.7))


def mini_report_table(ax: plt.Axes, x: float, y: float, w: float, h: float, rows: tuple[tuple[str, str], ...]) -> None:
    ax.add_patch(patches.Rectangle((x, y), w, h, facecolor="white", edgecolor=COLORS["line"], lw=0.7))
    row_h = h / (len(rows) + 1)
    ax.add_patch(patches.Rectangle((x, y + h - row_h), w, row_h, facecolor="#e8f0f5", edgecolor="none"))
    ax.text(x + 0.18, y + h - row_h / 2, "字段", ha="left", va="center", fontsize=6.7, color=COLORS["ink"], fontweight="bold")
    ax.text(x + w * 0.58, y + h - row_h / 2, "值", ha="left", va="center", fontsize=6.7, color=COLORS["ink"], fontweight="bold")
    for i, (left, right) in enumerate(rows):
        yy = y + h - row_h * (i + 2)
        ax.plot([x, x + w], [yy, yy], color=COLORS["grid"], lw=0.5)
        ax.text(x + 0.18, yy + row_h / 2, zh(left), ha="left", va="center", fontsize=6.3, color=COLORS["muted"])
        ax.text(x + w * 0.58, yy + row_h / 2, zh(right), ha="left", va="center", fontsize=6.3, color=COLORS["ink"])


def mini_badges(
    ax: plt.Axes,
    x: float,
    y: float,
    labels: tuple[str, ...],
    *,
    width: float = 1.0,
    gap: float = 0.22,
) -> None:
    for i, label in enumerate(labels):
        face = "#dcebdc" if i == 0 else "#eef3f6"
        rounded_box(ax, x + i * (width + gap), y, width, 0.38, zh(label), face=face, fontsize=6.2, lines=8)


def detail_caption(ax: plt.Axes, x: float, y: float, text: str) -> None:
    ax.text(x, y, zh(text), ha="left", va="center", fontsize=6.9, color=COLORS["muted"])


def draw_parallel(h: Highlight) -> plt.Figure:
    fig, ax = make_axes()
    panel(ax, 0.5, 0.72, 4.35, 7.65, "A. 串行瓶颈")
    panel(ax, 5.05, 0.72, 6.15, 7.65, "B. ZQ500 并行设计")
    panel(ax, 11.4, 0.72, 4.05, 7.65, "C. 可观测价值")

    rounded_box(ax, 0.8, 6.88, 3.7, 0.72, zh(h.problem[0]), face=COLORS["problem"], weight="bold", fontsize=9.0)
    rounded_box(ax, 0.8, 5.94, 3.7, 0.68, zh(h.problem[1]), face="#f3f6f8", fontsize=8.5)
    rounded_box(ax, 0.8, 5.05, 3.7, 0.68, zh(h.problem[2]), face="#f3f6f8", fontsize=8.5)
    for y in (6.88, 5.94):
        arrow(ax, 2.65, y, 2.65, y - 0.24, color=COLORS["warn"])
    mini_curve(ax, 0.95, 3.78, 3.35, 0.9, kind="wave")
    detail_caption(ax, 0.95, 3.55, "依赖链 / 串行扫描")
    for i in range(7):
        x = 0.95 + i * 0.45
        ax.add_patch(patches.Circle((x, 2.75), 0.12, facecolor="#f4e8da", edgecolor=COLORS["warn"], lw=0.8))
        if i < 6:
            arrow(ax, x + 0.12, 2.75, x + 0.33, 2.75, color=COLORS["warn"])
    mini_bar_chart(ax, 0.9, 1.35, 3.2, 0.9, ("准备", "搬运", "循环"), (0.42, 0.58, 1.0), color="#b98045")

    for i, token in enumerate(h.tokens[:4]):
        x = 5.55 + i * 1.28
        rounded_box(ax, x, 6.82, 1.0, 0.58, zh(token), face=COLORS["device"], fontsize=7.4, lines=9)
        if i < 3:
            arrow(ax, x + 1.0, 7.1, x + 1.28, 7.1)
    rounded_box(ax, 5.45, 5.65, 1.55, 0.72, zh(h.solution[0]), face=COLORS["solution"], weight="bold", fontsize=8.0)
    rounded_box(ax, 7.3, 5.65, 1.55, 0.72, zh(h.solution[1]), face=COLORS["solution"], weight="bold", fontsize=8.0)
    rounded_box(ax, 9.15, 5.65, 1.55, 0.72, zh(h.solution[2]), face=COLORS["solution"], weight="bold", fontsize=8.0)
    arrow(ax, 7.0, 6.0, 7.3, 6.0)
    arrow(ax, 8.85, 6.0, 9.15, 6.0)
    for lane in range(4):
        yy = 4.22 - lane * 0.42
        ax.plot([5.55, 10.55], [yy, yy], color=COLORS["grid"], lw=1.1)
        for step in range(6):
            ax.add_patch(
                patches.Rectangle(
                    (5.7 + step * 0.78 + (lane % 2) * 0.15, yy - 0.12),
                    0.42,
                    0.24,
                    facecolor="#cfe2ee" if step <= lane + 1 else "#edf3f6",
                    edgecolor=COLORS["line"],
                    lw=0.35,
                )
            )
    detail_caption(ax, 5.55, 2.22, "tile / warp 并行通道")
    for i in range(6):
        draw_grid(ax, 7.05 + i * 0.48, 1.35, 0.34, 0.34, 3, 3, active=(i % 3, (i + 1) % 3))
    mini_curve(ax, 8.95, 1.22, 1.55, 0.82, kind="speed")

    rounded_box(ax, 11.75, 6.75, 3.25, 0.72, zh(h.value[0]), face=COLORS["value"], weight="bold", fontsize=8.6, lines=18)
    rounded_box(ax, 11.75, 5.82, 3.25, 0.68, zh(h.value[1]), face="#f7f2e6", fontsize=8.2, lines=18)
    mini_bar_chart(ax, 11.85, 4.15, 3.05, 1.05, ("CPU", "e2e", "Kernel"), (1.0, 0.32, 0.12), color=COLORS["good"])
    detail_caption(ax, 11.85, 3.85, "延迟构成")
    mini_curve(ax, 11.85, 2.55, 3.05, 0.85, kind="error")
    detail_caption(ax, 11.85, 2.25, "误差保持受控")
    mini_badges(ax, 11.85, 1.25, ("通过", "CSV", "JSON"))
    evidence(ax, h)
    return fig


def draw_cache(h: Highlight) -> plt.Figure:
    fig, ax = make_axes()
    panel(ax, 0.5, 0.72, 4.25, 7.65, "A. 重复准备开销")
    panel(ax, 4.98, 0.72, 6.05, 7.65, "B. Cache 感知 Workspace")
    panel(ax, 11.28, 0.72, 4.18, 7.65, "C. Device 计时路径")

    rounded_box(ax, 0.85, 6.85, 3.35, 0.68, zh(h.problem[0]), face=COLORS["problem"], weight="bold", fontsize=8.5)
    rounded_box(ax, 0.85, 5.92, 3.35, 0.64, zh(h.problem[1]), face="#f3f6f8", fontsize=8.0)
    rounded_box(ax, 0.85, 5.05, 3.35, 0.64, zh(h.problem[2]), face="#f3f6f8", fontsize=8.0)
    mini_timeline(ax, 0.85, 3.78, 3.35, 0.72, ("分配", "H2D", "构造", "释放"))
    mini_bar_chart(ax, 0.85, 2.25, 3.25, 1.0, ("分配", "搬运", "准备", "Kernel"), (0.82, 0.68, 0.75, 0.32), color="#b98045")
    detail_caption(ax, 0.85, 1.78, "小规模调用被固定开销主导")

    rounded_box(ax, 5.35, 6.75, 1.55, 0.62, "Host", face=COLORS["host"], weight="bold", fontsize=8.0)
    rounded_box(ax, 5.35, 4.85, 1.55, 0.62, "Device", face=COLORS["device"], weight="bold", fontsize=8.0)
    rounded_box(ax, 7.25, 6.35, 2.75, 0.68, zh(h.solution[0]), face=COLORS["cache"], weight="bold", fontsize=8.2, lines=18)
    rounded_box(ax, 7.25, 5.35, 2.75, 0.64, zh(h.solution[1]), face="#eee8f5", fontsize=7.8, lines=18)
    rounded_box(ax, 7.25, 4.38, 2.75, 0.64, zh(h.solution[2]), face="#eee8f5", fontsize=7.8, lines=18)
    arrow(ax, 6.9, 7.05, 7.25, 6.72)
    arrow(ax, 6.9, 5.15, 7.25, 4.7)
    ax.annotate(
        "",
        xy=(10.15, 6.7),
        xytext=(10.15, 4.7),
        arrowprops=dict(arrowstyle="<|-|>", lw=1.2, color=COLORS["accent2"], mutation_scale=12),
    )
    detail_caption(ax, 10.35, 5.67, "Cache 命中 / 复用")
    mini_memory_blocks(ax, 5.45, 2.68, 2.35, 0.95, active=12)
    detail_caption(ax, 5.45, 2.36, "Device 分配池")
    mini_report_table(
        ax,
        8.15,
        2.43,
        2.35,
        1.25,
        (("key", h.tokens[1][:12]), ("容量", ">= 请求"), ("设备", "same id")),
    )
    for i, token in enumerate(h.tokens[:3]):
        rounded_box(ax, 5.35 + i * 1.55, 1.22, 1.32, 0.46, zh(token), face="#f8fafb", fontsize=6.6, lines=10)

    rounded_box(ax, 11.7, 6.55, 3.25, 0.68, zh(h.tokens[-2]), face=COLORS["solution"], weight="bold", fontsize=8.4)
    rounded_box(ax, 11.7, 5.48, 3.25, 0.68, zh(h.tokens[-1]), face=COLORS["value"], weight="bold", fontsize=8.4)
    arrow(ax, 10.25, 5.68, 11.7, 6.9)
    arrow(ax, 13.32, 6.55, 13.32, 6.16)
    mini_bar_chart(ax, 11.82, 3.92, 2.95, 0.95, ("before", "after"), (1.0, 0.36), color=COLORS["good"])
    detail_caption(ax, 11.82, 3.58, "准备开销")
    mini_curve(ax, 11.82, 2.2, 2.95, 0.85, kind="speed")
    detail_caption(ax, 11.82, 1.9, "repeat 计时稳定性")
    mini_badges(ax, 11.82, 1.18, ("D2D", "Cache", "复测"))

    evidence(ax, h)
    return fig


def draw_pipeline(h: Highlight) -> plt.Figure:
    fig, ax = make_axes()
    panel(ax, 0.5, 0.72, 10.35, 7.65, "A. Device 驻留流水线")
    panel(ax, 11.08, 0.72, 4.38, 7.65, "B. 任务级 gate")

    y_cpu = 6.83
    y_gpu = 5.15
    small_label(ax, 0.92, y_cpu + 0.55, "CPU 参考链路", color=COLORS["muted"])
    small_label(ax, 0.92, y_gpu + 0.55, "ZQ500 GPU 链路", color=COLORS["accent"])
    ax.plot([1.0, 10.35], [y_cpu + 0.3, y_cpu + 0.3], color=COLORS["grid"], lw=1.1)
    ax.plot([1.0, 10.35], [y_gpu + 0.3, y_gpu + 0.3], color=COLORS["grid"], lw=1.1)

    for i, token in enumerate(("参考", "对照", "metrics")):
        x = 1.05 + i * 2.15
        rounded_box(ax, x, y_cpu, 1.42, 0.62, token, face="#f3f5f6", fontsize=7.6)
        if i < 2:
            arrow(ax, x + 1.42, y_cpu + 0.31, x + 2.15, y_cpu + 0.31, color=COLORS["muted"])
    for i, token in enumerate(h.tokens[:4]):
        x = 1.05 + i * 2.12
        rounded_box(ax, x, y_gpu, 1.42, 0.62, zh(token), face=COLORS["device"], weight="bold", fontsize=7.5, lines=10)
        if i < len(h.tokens[:4]) - 1:
            arrow(ax, x + 1.42, y_gpu + 0.31, x + 2.12, y_gpu + 0.31)

    rounded_box(ax, 1.02, 3.75, 2.2, 0.64, zh(h.problem[0]), face=COLORS["problem"], weight="bold", fontsize=7.7)
    rounded_box(ax, 3.62, 3.75, 2.2, 0.64, zh(h.problem[1]), face="#f3f6f8", fontsize=7.7)
    rounded_box(ax, 6.22, 3.75, 2.2, 0.64, zh(h.solution[0]), face=COLORS["solution"], weight="bold", fontsize=7.7)
    rounded_box(ax, 8.22, 2.72, 1.78, 0.64, zh(h.solution[1]), face=COLORS["solution"], weight="bold", fontsize=7.4)
    rounded_box(ax, 6.22, 1.72, 2.2, 0.64, zh(h.solution[2]), face=COLORS["solution"], weight="bold", fontsize=7.7)
    arrow(ax, 3.22, 4.07, 3.62, 4.07)
    arrow(ax, 5.82, 4.07, 6.22, 4.07)
    arrow(ax, 8.42, 3.8, 8.85, 3.36)
    arrow(ax, 8.15, 2.72, 7.32, 2.36)
    mini_heatmap(ax, 1.08, 1.45, 2.25, 1.25, seed=len(h.slug))
    detail_caption(ax, 1.08, 1.13, "中间特征图")
    mini_curve(ax, 3.78, 1.45, 1.95, 1.0, kind="wave")
    detail_caption(ax, 3.78, 1.13, "轨迹 / 响应曲线")

    rounded_box(ax, 11.45, 6.72, 3.4, 0.66, zh(h.value[0]), face=COLORS["value"], weight="bold", fontsize=8.0, lines=18)
    rounded_box(ax, 11.45, 5.72, 3.4, 0.62, zh(h.value[1]), face="#f7f2e6", fontsize=7.8, lines=18)
    mini_report_table(
        ax,
        11.55,
        3.82,
        3.15,
        1.28,
        (("业务", "通过"), ("mixed_error", "受控"), ("RMSE", "gate")),
    )
    mini_curve(ax, 11.55, 2.45, 3.1, 0.82, kind="error")
    detail_caption(ax, 11.55, 2.12, "任务级阈值")
    mini_badges(ax, 11.55, 1.28, ("通过", "repeat", "JSON"))

    evidence(ax, h)
    return fig


def draw_report(h: Highlight) -> plt.Figure:
    fig, ax = make_axes()
    panel(ax, 0.5, 0.72, 4.25, 7.65, "A. 输入证据")
    panel(ax, 5.0, 0.72, 4.95, 7.65, "B. 可复现 runner")
    panel(ax, 10.2, 0.72, 5.25, 7.65, "C. 报告产物")

    sources = h.tokens[:2]
    artifacts = h.tokens[2:]
    rounded_box(ax, 0.9, 6.82, 3.35, 0.62, zh(sources[0]), face=COLORS["host"], weight="bold", fontsize=8.0)
    rounded_box(ax, 0.9, 5.92, 3.35, 0.62, zh(sources[1]) if len(sources) > 1 else "输入", face=COLORS["host"], fontsize=8.0)
    rounded_box(ax, 0.9, 5.02, 3.35, 0.62, zh(h.problem[0]), face=COLORS["problem"], fontsize=7.8, lines=16)
    mini_report_table(ax, 0.92, 2.95, 3.3, 1.35, (("case", "scale"), ("repeat", "N"), ("status", "raw")))
    mini_curve(ax, 0.92, 1.52, 3.3, 0.82, kind="wave")
    detail_caption(ax, 0.92, 1.2, "源文件 / 原始测量")

    rounded_box(ax, 5.42, 6.65, 3.95, 0.66, zh(h.solution[0]), face=COLORS["solution"], weight="bold", fontsize=8.0, lines=22)
    rounded_box(ax, 5.42, 5.58, 3.95, 0.64, zh(h.solution[1]), face=COLORS["solution"], fontsize=7.8, lines=22)
    rounded_box(ax, 5.42, 4.52, 3.95, 0.64, zh(h.solution[2]), face=COLORS["solution"], fontsize=7.8, lines=22)
    for y in (7.13, 6.23, 5.33):
        arrow(ax, 4.25, y - 0.2, 5.42, y - 0.14)
    mini_timeline(ax, 5.5, 3.32, 3.65, 0.68, ("构建", "运行", "解析", "写出"))
    mini_bar_chart(ax, 5.5, 1.78, 3.6, 0.94, ("L1", "L2", "L3", "L4", "L5", "L6"), (0.22, 0.35, 0.5, 0.66, 0.8, 0.95), color=COLORS["accent"])

    for i, token in enumerate(artifacts[:4]):
        x = 10.62 + (i % 2) * 2.2
        y = 6.62 - (i // 2) * 1.12
        rounded_box(ax, x, y, 1.85, 0.6, zh(token), face=COLORS["value"], weight="bold", fontsize=7.3, lines=12)
        arrow(ax, 9.37, 5.28, x, y + 0.3, color=COLORS["accent2"])
    mini_report_table(
        ax,
        10.62,
        3.34,
        2.45,
        1.32,
        (("pass", "true"), ("误差", "mixed"), ("加速比", "e2e")),
    )
    mini_heatmap(ax, 13.3, 3.34, 1.72, 1.32, seed=len(h.slug) + 30)
    mini_curve(ax, 10.62, 1.75, 2.2, 0.82, kind="speed")
    mini_badges(ax, 13.1, 1.92, ("PNG", "SVG", "MD"), width=0.72, gap=0.12)
    rounded_box(ax, 10.62, 1.05, 4.38, 0.44, zh(h.value[0]) + " / " + zh(h.value[1]), face="#f7f2e6", fontsize=6.8, lines=42)

    evidence(ax, h)
    return fig


def render_highlight(h: Highlight) -> plt.Figure:
    if h.category == "parallel":
        return draw_parallel(h)
    if h.category == "cache":
        return draw_cache(h)
    if h.category == "pipeline":
        return draw_pipeline(h)
    if h.category == "report":
        return draw_report(h)
    raise ValueError(f"unknown category: {h.category}")


def save_highlight(h: Highlight) -> None:
    fig = render_highlight(h)
    png_path = OUTPUT_DIR / f"{h.slug}.png"
    svg_path = OUTPUT_DIR / f"{h.slug}.svg"
    fig.savefig(png_path, dpi=DPI)
    fig.savefig(svg_path)
    plt.close(fig)


def write_readme() -> None:
    lines = [
        "# CETC 技术亮点逐图索引",
        "",
        "本目录图片由 `scripts/figures/generate_technical_highlight_figures.py` 生成，来源为 `docs/submission/technical_document_framework_final.md` 第 7 章。图片采用 16:9 白底科研风复合示意模板，面向 PPT 展示，不设置总标题；图内说明中文为主，必要技术词保留英文。",
        "",
        "| 序号 | 技术亮点 | PNG | SVG | 视觉表达重点 | 证据路径 |",
        "|---:|---|---|---|---|---|",
    ]
    for index, h in enumerate(HIGHLIGHTS, start=1):
        evidence_text = "<br>".join(f"`{item}`" for item in h.evidence)
        visual_focus = f"{zh(h.problem[0])} -> {zh(h.solution[0])} -> {zh(h.value[0])}"
        lines.append(
            f"| {index} | {h.zh_name} | [`{h.slug}.png`]({h.slug}.png) | "
            f"[`{h.slug}.svg`]({h.slug}.svg) | {visual_focus} | {evidence_text} |"
        )
    lines.append("")
    lines.append("重新生成：")
    lines.append("")
    lines.append("```bash")
    lines.append("python3 scripts/figures/generate_technical_highlight_figures.py")
    lines.append("```")
    (OUTPUT_DIR / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    setup_style()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for highlight in HIGHLIGHTS:
        save_highlight(highlight)
    write_readme()
    print(f"wrote {len(HIGHLIGHTS)} PNG/SVG figure pairs to {OUTPUT_DIR.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
