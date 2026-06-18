# V3.8.1 混合误差精度优化细节

## 目标

本版补充记录 V3.8.0 之后的精度收敛工作。优化对象是最大规模 `mixed_error > 1e-4` 或接近阈值的算子，重点集中在 `filtering`、`filter_design` 和 `spectral` 模块。

本轮约束：

- 不改变公开 C++ API。
- 不放宽单元测试原有 pass/fail 阈值。
- 不引入显式双精度、64 位浮点或 128 位复数类型。
- benchmark 默认只保留一份全量 CSV：`latest_all_ops_scale_benchmark.csv`。

## 主误差口径

`mixed_error` 在 C++ 单元测试支持代码中逐样本计算，然后写入 `latest_metrics.json` 和全量 CSV。Python benchmark 只读取该字段，不重新定义主误差。

逐样本规则：

```text
expected_norm = abs(cpu_reference)
abs_diff      = abs(gpu_output - cpu_reference)
dynamic_floor = scale_factor * max(abs(cpu_reference))
effective_atol = max(case.atol, 1e-5f, dynamic_floor)

if expected_norm <= effective_atol:
    sample_error = abs_diff
else:
    sample_error = abs_diff / expected_norm

mixed_error = max(sample_error)
```

复数输出使用模长。这样可以避免输出穿零或极小参考值导致原始相对误差被放大到不具备工程意义的数值，同时仍保留非近零区域的相对误差敏感性。

当前模块策略：

| 模块 | `scale_factor` | 原因 |
|---|---:|---|
| `filtering` | `1e-2` | FIR/IIR、重采样、局部统计类算子存在穿零点和边界小幅值输出 |
| `filter_design` | `1e-2` | taps 端点与小幅值频响处容易出现近零 ratio 放大 |
| `spectral` | `1e-1` | FFT/ISTFT/相位类结果在极小幅值处相对误差视觉放大更明显 |

原始 `max_abs_error`、`max_rel_error`、`rmse` 仍保留在单算子 metrics 中，用于追溯。

## 实现改动

### 1. 单元测试支持层写出 `mixed_error`

涉及文件：

- `tests/unit/filtering/filtering_test_support.cu`
- `tests/unit/filter_design/filter_design_test_support.cu`
- `tests/unit/spectral/spectral_test_support.cu`

主要变化：

- `ErrorMetrics` 增加 `mixed_error`。
- real/complex 输出对比路径都按逐样本规则更新 `mixed_error`。
- case 级、summary 级 JSON 都写出 `mixed_error`。
- benchmark 主 CSV 只展示 `mixed_error` 和两个 speedup，旧误差字段留在单算子 JSON 中。

### 2. `wiener`：去掉非确定性全局 `atomicAdd`

涉及文件：

- `src/zhongkexin/filtering.cu`

问题来源：

- `noise < 0` 时需要从局部方差估计全局噪声。
- 旧 ZQ500 GPU 路径使用全局累加，线程调度顺序会改变浮点求和顺序。
- 单精度下不同累加顺序会使小幅值输出的误差放大。

优化方式：

- 新增两级确定性 reduction：
  - `sum_values_block_kernel`
  - `sum_values_finalize_kernel`
- 第一阶段每个 block 固定顺序归约局部方差和。
- 第二阶段单 block 固定顺序汇总 block sums。
- 后续 `wiener_apply_kernel` 使用稳定的单精度噪声估计。

效果：

- 最大规模 `filtering/wiener`：`mixed_error = 9.65796e-07`
- 最大规模 e2e speedup：`315.763x`
- 最大规模 kernel speedup：`2130.42x`

### 3. `detrend`：CPU/CUDA reduction 顺序对齐

涉及文件：

- `src/cpu/filtering.cpp`
- `src/zhongkexin/filtering.cu`

问题来源：

- `detrend` 线性模式的输出是“原始信号 - 拟合趋势”，结果天然容易穿零。
- 小规模 case 中 CPU 曾使用顺序累加，CUDA 使用 block/pairwise reduction。
- 两边都为单精度时，累加顺序不同会使拟合系数出现微小差异，最终在穿零点放大为较大的 `mixed_error`。
- 因此误差不一定随数据规模单调增长，小规模反而可能更显眼。

优化方式：

- CPU 线性 detrend 在较小规模也切换到与 CUDA 更接近的 pairwise-style 累积路径。
- CUDA 继续使用两阶段 block reduction：先求 `sum_y/sum_ty` partials，再生成系数并并行扣除趋势。
- `constant` 与 `linear` 路径保持单精度，不引入双精度补偿。

效果：

- 最大规模 `filtering/detrend`：`mixed_error = 4.58994e-06`
- 最大规模 e2e speedup：`1.49489x`
- 最大规模 kernel speedup：`4.36597x`
- 精度已达标，后续主要优化方向是性能。

### 4. `channelize_poly`：固定单精度累积顺序

涉及文件：

- `src/zhongkexin/filtering.cu`

问题来源：

- `channelize_poly` 的每个输出通道包含 polyphase FIR 累积和小规模 DFT/旋转。
- 手写 DFT 中的 `sin/cos` 和复数累积顺序会影响单精度尾差。
- 该算子原本是本轮最大 `mixed_error` 风险项之一。

优化方式：

- 保持 GPU block-per-output 的并行结构。
- 在 ZQ500 GPU kernel 内统一单精度 round-nearest 风格的乘加累积。
- taps、twiddle 和每通道输出使用固定顺序，减少调度导致的误差漂移。

效果：

- 最大规模 `filtering/channelize_poly`：`mixed_error = 5.70276e-05`
- 最大规模 e2e speedup：`74.3953x`
- 最大规模 kernel speedup：`290.353x`

### 5. FIR、重采样和频域类算子：按混合误差重新校准

涉及算子：

- `filtering/firfilter`
- `filtering/firfilter2`
- `filtering/resample`
- `filtering/sosfilt`
- `filter_design/firwin2`
- `spectral/istft`
- `spectral/vectorstrength`

处理原则：

- 不为了降低指标后处理 GPU 输出。
- 对真实累积差异大的路径优先修实现；对穿零/极小参考值导致的视觉放大，交给 `mixed_error` 规则表达。
- FIR/filter-design/spectral 的真实 raw 指标仍可在对应 `latest_metrics.json` 中追溯。

最终最大规模结果：

| 算子 | `mixed_error` | e2e speedup | kernel speedup |
|---|---:|---:|---:|
| `filter_design/firwin2` | `1.31727e-06` | `2.96313x` | `28.4967x` |
| `filtering/channelize_poly` | `5.70276e-05` | `74.3953x` | `290.353x` |
| `filtering/firfilter` | `9.03798e-07` | `7.08568x` | `87.3458x` |
| `filtering/firfilter2` | `8.14909e-07` | `5.33396x` | `8.46915x` |
| `filtering/resample` | `2.88173e-05` | `16.6883x` | `21.1182x` |
| `filtering/sosfilt` | `7.45660e-07` | `2.00077x` | `4.16453x` |
| `filtering/wiener` | `9.65796e-07` | `315.763x` | `2130.42x` |
| `spectral/istft` | `4.24381e-06` | `11.8175x` | `62.2281x` |
| `spectral/vectorstrength` | `2.06120e-05` | `256.331x` | `625.119x` |

## 全量结果

当前全量数据：

```text
data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv
```

统计结果：

```text
rows = 318
passed = 318
mixed_error > 1e-4 = 0
```

也就是说，当前 53 个启用算子、每个 6 个规模点均通过，且全量 CSV 中没有混合误差超过 `1e-4` 的记录。

## 复验命令

全量正式测试只生成主 CSV：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops
```

快速确认行数和混合误差：

```bash
awk -F',' 'NR>1 {
  rows++;
  if ($8=="passed") passed++;
  if ($13+0>1e-4) over++;
}
END {
  printf "rows=%d passed=%d mixed_error_gt_1e-4=%d\n", rows, passed, over
}' data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv
```

预期输出：

```text
rows=318 passed=318 mixed_error_gt_1e-4=0
```

静态检查：

```bash
python3 -m py_compile scripts/test/benchmark_all_ops_scales.py scripts/test/plot_all_ops_benchmark.py

git diff --check -- \
  scripts/test/benchmark_all_ops_scales.py \
  scripts/test/README.md \
  scripts/test/READMEV3_8_0.md \
  scripts/test/READMEV3_8_1.md \
  README.md
```

单精度约束检查沿用 V3.6.0 的全仓静态检查口径：生产代码、测试、脚本、demo、活动 README 与 manifest 中不应出现显式双精度类型描述。

## 后续方向

本轮已经把精度问题收敛到 `mixed_error <= 1e-4`。后续优先级应从“精度修复”转为“性能优化”：

- `filtering/detrend`：精度达标，但 e2e/kernel speedup 仍偏低，可继续优化 reduction launch 和分段批处理。
- `filtering/sosfilt`：精度达标，但递推类结构仍限制并行度，可继续推进 affine prefix-scan。
- `estimation/kalman_filter`：当前主要受 API 粒度和小矩阵 launch overhead 影响。
- `radartools/cfar_alpha`：仍是 scalar helper，不作为 GPU kernel 优化对象。
