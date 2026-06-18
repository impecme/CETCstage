# V2.11 spectral 模块完整接入

## 版本范围

`V2.11` 在现有 `waveforms`、`windows`、`filter_design`、`filtering`、`bsplines`、`radartools` 基础上，补齐了 `spectral` 模块的实现、测试、一键链路和数据组织。

本轮实现的公开 API：

- `lombscargle`
- `periodogram`
- `welch`
- `csd`
- `spectrogram`
- `stft`
- `istft`
- `coherence`
- `vectorstrength`

## 接口语义

- `cpu::*` 保持 host 输入输出。
- `zx_gpu_backend::*` 保持 host/device 双输入、device 输出。
- 不改头文件签名。
- `include/` 中现有注释块结构保留，仅移除占位语义。

## 实现说明

- 公共逻辑集中在 `src/common/spectral_detail.hpp`
- CPU 频域计算使用 FFTW
- CUDA 频域计算使用 `cuFFT`
- ZQ500 GPU 侧通过 `thread_local SpectralWorkspace` 复用：
  - 输入归一化 scratch
  - segment/FFT 缓冲
  - iSTFT overlap-add 缓冲
  - `cuFFT` plan

## 当前支持子集

实现范围严格以当前 C++ 头文件为准。

- `periodogram/welch/csd/spectrogram/stft/coherence` 只覆盖当前头文件可表达的 `RealArray` 输入子集。
- unit case 也只覆盖当前 C++ 签名可表达的参数组合，不扩接口。

## 测试与数据组织

新增：

- `tests/unit/spectral/`
- `data/reference/unit/spectral/<op>/`
- `data/generated/unit/spectral/<op>/`
- `data/reports/unit/spectral/<op>/`
- `scripts/data/generate_spectral_data.py`

约定保持与当前主线一致：

- accuracy 使用提交入库的 `reference` 数据
- perf 输入运行时生成
- `--emit-report` 时写回 `generated/input` 和 `generated/output_samples`
- `output_samples` 同时包含 CPU/GPU 两套样本

## 性能口径

- `gpu_e2e_perf`：host 输入 + H2D + GPU 计算，不包含 `get()`
- `gpu_kernel_perf`：真实 GPU 计算阶段时间，包含 kernel 与 `cuFFT`

## 验证命令

模块级：

```bash
./scripts/test/run_all_tests.sh --module spectral --emit-report
```

全量：

```bash
./scripts/test/run_all_tests.sh --emit-report
```

## 版本结论

`V2.11` 完成了 `spectral` 模块的 CPU/ZQ500 GPU 实现、unit test、reference/perf 数据链路和一键测试接入，当前主线模块已继续扩展到 `spectral`。
