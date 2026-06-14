# cuSignal C++ V2.2 README

## 版本信息

- 版本名称：`V2.2 waveform 实现与验证`
- 完成时间：`2026-04-04`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.2` 补齐 `waveforms` 模块的真实数值实现，并恢复单算子验证、CPU/GPU 误差统计、性能统计和数据落盘，

本轮目标聚焦于以下三件事：

- 完成 `waveforms` 模块 CPU 与 CUDA 两条路径的真实实现。
- 恢复 `tests/unit/` 下按模块、按算子组织的 runner。

## 本轮新增内容

### 1. `waveforms` 模块真实实现

当前已补齐以下算子：

- `chirp`
- `gausspulse`
- `sawtooth`
- `square`
- `unit_impulse`

实现特点如下：

- `cpu::waveforms::*` 使用 C++17 双精度公式实现，作为对照基线。
- `cuda_backend::waveforms::*` 使用 CUDA kernel + host wrapper 实现，显式完成 H2D、kernel launch、D2H 和同步。
- 继续沿用 `V2.1` 的公开头文件签名与返回类型，不新增破坏性接口。
- 非法输入保持显式异常语义，不使用 NaN 静默吞错。

### 2. 单测与 runner 恢复

本轮在 `waveforms` 模块下按算子拆分单独文件：

```text
tests/unit/
└─ waveforms/
   ├─ test_chirp.cpp
   ├─ test_gausspulse.cpp
   ├─ test_sawtooth.cpp
   ├─ test_square.cpp
   ├─ test_unit_impulse.cpp
   ├─ waveform_test_support.hpp
   └─ waveform_test_support.cu
```

当前每个算子 runner 默认执行 correctness 校验，并支持以下参数：

- `--emit-report` 打开后会写文件到 data/reports 和 data/generated，不开的话，默认只在终端输出并做断言，不落盘
- `--case-set smoke|accuracy|perf|full` accuracy：只跑正确性 case；perf：只跑性能 case；full：两者都跑；底层 runner 当前源码默认值为 `accuracy`
- `--warmup N` 性能测试前先空跑 N 次，不记入统计，用来让缓存、CUDA 上下文、首次 launch 抖动先稳定下来；默认为 `5`
- `--repeat N` 性能测试时重复执行 N 次，取平均值作为最终统计结果；默认为 `30`
- `--verbose` 打开后会在终端输出每个 case 的详细输入参数、误差结果和性能结果，关闭的话则只输出模块级摘要

默认通过 `ctest` 运行 correctness；显式使用 `--emit-report --case-set full` 时，会同时生成算子级与模块级报告文件。仓库同时新增 `scripts/test/run_all_tests.sh`，脚本默认会自动构建并显式以 `--case-set full` 跑完整已注册测试集合。

### 3. 数据目录

当前 `waveforms` 对应的数据目录组织如下：

```text
data/
├─ reference/
│  └─ unit/waveforms/<op>/
│     ├─ manifest.json
│     ├─ input/
│     └─ expected/
├─ generated/
│  └─ unit/waveforms/<op>/
│     ├─ manifest.json
│     ├─ input/
│     └─ output_samples/
└─ reports/
   └─ unit/waveforms/
      ├─ latest_summary.md
      ├─ latest_metrics.json
      ├─ latest_cases.csv
      └─ <op>/
         ├─ latest_summary.md
         ├─ latest_metrics.json
         ├─ latest_cases.csv
         └─ history/
```

职责约定如下：

- `data/reference/`：存放小型固定基准输入和输出，服务 correctness。
- `data/generated/`：存放性能 case 的生成输入和输出样本，。
- `data/reports/`：存放机器可读指标、表格汇总和摘要。

## 当前验证链路

当前 runner 的执行顺序为：

1. 从 `manifest.json` 读取固定 accuracy case 与 perf case。
2. 对 accuracy case 同时执行 CPU 与 GPU，输出 `GPU vs CPU` 误差，并在存在黄金值时输出 `CPU/GPU vs reference`。
3. 对 perf case 统计：
   - CPU 端到端延迟
   - GPU 端到端延迟（复用 device buffer，避免把重复 `cudaMalloc/cudaFree` 抖动混入稳态结果）
   - GPU kernel-only 延迟
4. 终端打印 5 行摘要。
5. 写入：
   - `latest_summary.md`
   - `latest_metrics.json`
   - `latest_cases.csv`
6. 汇总生成模块级 `data/reports/unit/waveforms/latest_*` 文件。

当前误差指标包括：

- `max_abs_error`
- `max_rel_error`
- `rmse`
- `l2_error`
- `exact_match`
- `first_mismatch_index`

`latest_metrics.json` 现在除误差指标外，也会为 `perf` case 写出以下时间字段：

- `cpu_perf`
- `gpu_e2e_perf`
- `gpu_kernel_perf`

每个 timing 对象都包含 `warmup`、`repeat`、`mean_ms`、`median_ms`、`p95_ms`、`min_ms`、`max_ms`、`std_ms`。

终端摘要、算子级 `latest_summary.md` 与 `latest_metrics.json` 的 `summary` 中，都会同时给出：

- `gpu_e2e_speedup`
- `gpu_kernel_speedup`

## 构建与运行

### 构建

```bash
cmake -S . -B build
cmake --build build --target cusignal_cpu cusignal_cuda --parallel
cmake --build build --target \
  waveforms_test_chirp \
  waveforms_test_gausspulse \
  waveforms_test_sawtooth \
  waveforms_test_square \
  waveforms_test_unit_impulse \
  --parallel
```

### correctness 运行

```bash
ctest --test-dir build --output-on-failure
```

### 一键运行

```bash
./scripts/test/run_all_tests.sh
./scripts/test/run_all_tests.sh --emit-report
./scripts/test/run_all_tests.sh --operator chirp --case-set perf --warmup 1 --repeat 3
```

### 生成报告

示例：

```bash
./build/tests/unit/waveforms/waveforms_test_chirp --emit-report --case-set full
./build/tests/unit/waveforms/waveforms_test_gausspulse --emit-report --case-set full
./build/tests/unit/waveforms/waveforms_test_sawtooth --emit-report --case-set full
./build/tests/unit/waveforms/waveforms_test_square --emit-report --case-set full
./build/tests/unit/waveforms/waveforms_test_unit_impulse --emit-report --case-set full
```

报告主入口：

- 模块级摘要：`data/reports/unit/waveforms/latest_summary.md`
- 模块级指标：`data/reports/unit/waveforms/latest_metrics.json`
- 模块级表格：`data/reports/unit/waveforms/latest_cases.csv`
