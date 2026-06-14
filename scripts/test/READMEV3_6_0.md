# V3.6.0 全仓单精度清理与 README 收敛

## 版本信息

- 版本名称：`V3.6.0 全仓单精度清理与 README 收敛`
- 版本定位：在 V3.5.0 大规模 GPU 并行性复测之后，统一当前代码线、测试链路、数据生成脚本、demo 与活动 manifest 的单精度实现口径，并将根目录 README 收敛为最终交付首页。
- 约束：不改公开 C++ API 的主体形态，不改 benchmark 主 CSV 字段，不放宽现有误差阈值。

## 更改思路

根目录 README 只保留最终版本必要信息：

- 项目特色
- 环境要求
- 代码结构
- 编译命令
- demo 运行命令
- smoke 与单算子测试入口
- 全量 benchmark 与作图入口
- 版本说明入口
- 清理命令

更细的演进说明、验收记录、候选报告解释、规模策略和历史背景放在 `scripts/test/READMEV*_*.md` 系列文档中，避免根 README 变成变更日志。

单精度清理遵循同一原则：生产库、测试、数据生成和报告口径保持一致，CPU/CUDA 对照仍使用相同字段输出误差与耗时，已有阈值保持不变。

## 关键变更

- 生产实现
  - `waveforms_detail` 改为单精度常量与单精度数学函数。
  - `filtering/detrend` 的 CUDA/CPU reduction workspace、shared memory、系数与统计改为单精度。
  - `spectral/vectorstrength` 的 CUDA/CPU partial/final reduction 改为单精度 scratch 与单精度三角函数。
  - `correlate_detail` 的复数累加改为项目内 `Complex` 语义。
- 公开接口与 dtype
  - `unit_impulse` 默认 dtype 收敛到 `float32`。
  - dtype 校验函数收敛到 `ensure_float32`。
  - 注释、错误信息、README 和测试文档同步到单精度描述。
- 测试、demo、数据生成
  - 测试误差统计、timing 字段、demo 计时字段改为单精度口径。
  - `scripts/data/generate_*.py` 的数组 dtype 与复数 dtype 改为 `float32` / `complex64`。
  - `data/reference` 与 `data/generated` 的活动 manifest 同步到 `float32` / `complex64` 描述。
  - `windows/get_window` 中命名实数参数统一为 `named_float` 语义。
- README 收敛
  - 根 README 删除详细数据目录说明、单轮验收细节和过长背景解释。
  - 根 README 只保留最终交付所需入口。
  - 本文件记录 V3.6.0 的详细更改与验收。

## 验收命令

静态检查：使用 `rg` 在 `include src tests scripts demo data/reference data/generated README.md scripts/test/README*.md` 范围内检索显式高精度类型关键字，排除 `build/**`、`third_party/**` 与 `*.pyc`。预期为无命中。

构建与脚本检查：

```bash
cmake --build build --target cusignal_cpu cusignal_cuda
python3 -m py_compile scripts/data/generate_*.py scripts/test/*.py
git diff --check -- include src tests scripts demo data/reference data/generated README.md
```

精准单测：

```bash
cmake --build build --target \
  waveforms_test_unit_impulse waveforms_test_gausspulse waveforms_test_sawtooth waveforms_test_chirp waveforms_test_square \
  filtering_test_detrend spectral_test_vectorstrength correlate_test_correlate estimation_test_kalman_filter windows_test_get_window

ctest --test-dir build -R 'waveforms_test_(unit_impulse|gausspulse|sawtooth|chirp|square)|filtering_test_detrend|spectral_test_vectorstrength|correlate_test_correlate|estimation_test_kalman_filter|windows_test_get_window' --output-on-failure
```

采样大规模回归：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --operators detrend,vectorstrength,gausspulse,sawtooth,chirp,square,unit_impulse,kalman_filter,correlate \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/precision_cleanup_check
```

## 验收结果

- 静态显式高精度类型检索：无命中。
- `cusignal_cpu` / `cusignal_cuda`：构建通过。
- 数据生成脚本与测试脚本 py_compile：通过。
- 定向 CTest：`11/11` 通过。
- 采样 large-gpu benchmark：`54/54` 行全部 `passed`。
- `git diff --check`：通过。

采样最大规模结果摘要：

| 算子 | 最大规模 | kernel speedup | e2e speedup | max rel error | 说明 |
|---|---:|---:|---:|---:|---|
| `chirp` | `16777216` | `1865.09x` | `2.214x` | `2.07795` | 相对误差受近零参考值放大 |
| `gausspulse` | `16777216` | `3385.19x` | `5.877x` | `3.53e-7` | 单精度数值路径稳定 |
| `sawtooth` | `16777216` | `1513.76x` | `1.583x` | `0.375` | 绝对误差小，相对误差受近零参考值放大 |
| `square` | `16777216` | `1704.01x` | `1.552x` | `0` | 完全一致 |
| `unit_impulse` | `16777216` | `29879.1x` | `202.548x` | `0` | 完全一致 |
| `detrend` | `1048576` | `104.247x` | `2.456x` | `195.85` | 去趋势后近零结果放大 ratio |
| `vectorstrength` | `1048576` | `838.24x` | `233.474x` | `35.8268` | reduction 单精度化后通过现有阈值 |
| `correlate` | `8192` | `65.195x` | `40.849x` | `0` | 完全一致 |
| `kalman_filter` | `524288` | `684.378x` | `1.944x` | `0` | 批处理 fast path 保持一致 |

## 说明

`max_rel_error` 是 GPU 输出相对 CPU 输出的 ratio。若参考值接近零，极小的绝对误差也可能被放大成较大的相对误差。因此 V3.6.0 仍保留原始相对误差字段，同时建议结合 `max_abs_error` 与 `rmse` 判断数值质量。
