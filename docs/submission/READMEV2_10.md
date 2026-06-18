# V2.10 `radartools` 模块完整接入

## 版本信息

- 版本名称：`V2.10 radartools 模块完整接入`
- 完成时间：`2026-04-13`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.10` 在现有 `V2.4` host/device 双输入、`V2.5` 显存复用和 `V2.8+` unit data schema 基础上，补齐了 `radartools` 模块的实现、测试与数据链路。

## 本轮内容

- `radartools`
  - CPU 实现：`pulse_compression`、`pulse_doppler`、`ambgfun`、`cfar_alpha`、`ca_cfar`、`mvdr`
  - ZQ500 GPU 实现：`cuFFT`、`cuBLAS`、`cuSOLVER` 路径与 device-native 输出
  - 公共实现：`src/common/radartools_detail.hpp`
  - CUDA 计时：`radartools_test_hooks::consume_last_kernel_ms()`
- unit 测试
  - 新增 `tests/unit/radartools`
  - 一键脚本注册 `radartools` 的 6 个 operator
- 数据与报告
  - 新增 `data/reference/unit/radartools`
  - 新增 `data/generated/unit/radartools`
  - 新增 `data/reports/unit/radartools`
  - perf 输入改为运行时生成，`--emit-report` 时落盘

## 行为基准

本轮 `radartools` 的行为基准按以下优先级固定：

1. `cusignal/python/cusignal/radartools/radartools.py`
2. `cusignal/python/cusignal/radartools/beamformers.py`
3. `cusignal/python/cusignal/test/test_radartools.py`
4. 仓库内提交的 reference 数据

## 测试链路

- 新增单测目录：
  - `tests/unit/radartools`
- 新增 reference 与 perf manifest：
  - `data/reference/unit/radartools`
  - `data/generated/unit/radartools`
- 数据脚本：
  - `scripts/data/generate_radartools_data.py`

## 一键测试

```bash
./scripts/test/run_all_tests.sh --module radartools
```

输出报告：

```bash
./scripts/test/run_all_tests.sh --module radartools --emit-report
```

全量回归：

```bash
./scripts/test/run_all_tests.sh --emit-report
```

## 报告口径

- `gpu_e2e_perf`：host 输入到 CUDA 调用完成，不包含显式 `get()`
- `gpu_kernel_perf`：由 `radartools_test_hooks` 输出的 GPU 计算阶段总时长
- 报告文件保持统一格式：
  - `latest_summary.md`
  - `latest_metrics.json`
  - `latest_cases.csv`

## 说明

- `pulse_compression` 与 `pulse_doppler` 使用 FFTW / `cuFFT`
- `ambgfun` 保持 Python 的 `2d` / `delay` / `doppler` 数值路径
- `ca_cfar` 同时覆盖 1D / 2D
- `mvdr` 的 ZQ500 GPU 路径新增 `cuBLAS` / `cuSOLVER` 依赖
- `radartools` 的 generated sample 命名继续遵守当前 canonical schema，CPU/GPU 两套样本都会落盘
