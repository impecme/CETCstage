# V2.6 `filter_design` / `filtering` 模块完整实现

## 版本定位

`V2.6` 在 `V2.4` 的 host/device 双输入、device 输出语义和 `V2.5` 的内部显存复用基础上，补齐了 `filter_design` 与 `filtering` 两个模块的实现、数据与单测链路。

## 本轮内容

- `filter_design`
  - CPU 实现：`kaiser_beta`、`kaiser_atten`、`cmplx_sort`、`firwin`、`firwin2`
  - ZQ500 GPU 实现：`cmplx_sort` 的 device 排序、`firwin` 的 device tap 生成、`firwin2` 的 `cuFFT` 逆变换设计路径
- `filtering`
  - CPU 实现：`wiener`、`fir/lfilter`、`filtfilt`、`sosfilt`、`hilbert/hilbert2`、`detrend`、`freq_shift`、`channelize_poly`、`decimate`、`resample`、`resample_poly`、`upfirdn`
  - ZQ500 GPU 实现：保持 host/device 双输入与 device 输出边界，补齐完整返回链路与测试接入

## 测试链路

- 新增单测目录：
  - `tests/unit/filter_design`
  - `tests/unit/filtering`
- 新增参考数据与 perf manifest：
  - `data/reference/unit/filter_design`
  - `data/generated/unit/filter_design`
  - `data/reference/unit/filtering`
  - `data/generated/unit/filtering`
- 数据生成脚本：
  - `scripts/data/generate_filter_design_data.py`
  - `scripts/data/generate_filtering_data.py`

## 一键测试

```bash
./scripts/test/run_all_tests.sh
```

按模块筛选：

```bash
./scripts/test/run_all_tests.sh --module filter_design
./scripts/test/run_all_tests.sh --module filtering
```

输出报告：

```bash
./scripts/test/run_all_tests.sh --emit-report
```

## 报告口径

- `gpu_e2e_perf`：host 输入到 CUDA 调用完成，不包含显式 `get()`
- `gpu_kernel_perf`：由模块对应的 CUDA test hook 输出；对当前未细分 kernel 的混合实现，结果可能为 `0`
- 报告文件继续保持：
  - `latest_summary.md`
  - `latest_metrics.json`
  - `latest_cases.csv`

## 说明

- FFT 依赖保持当前仓库约定：
  - CPU FFT-heavy 路径使用 `third_party/fftw/install`
  - CUDA FFT-heavy 路径使用系统 CUDA Toolkit 的 `cuFFT`
- `filter_design` / `filtering` 的 reference 数据由 SciPy 脚本生成并提交到仓库。

## V2.6.x 增量

### `generated/output_samples` 统一

- `waveforms` 保持现有输出方式不变，作为统一模板。
- `windows`、`filter_design`、`filtering` 的 perf 样本目录现在也统一同时输出 `cpu` 和 `gpu` 两套样本。
- 文件命名规则统一为：
  - `windows`：`case_id__cpu__window.csv`、`case_id__gpu__window.csv`
  - `filter_design`：`case_id__{cpu|gpu}__value.csv` / `values.csv` / `indices.csv`
  - `filtering`：`case_id__{cpu|gpu}__output.csv`，以及可选的 `state.csv`、`time.csv`
- `filtering` 的 perf case 额外在 `generated/input/` 下写入 `case_id__spec.json`。
- `latest_metrics.json` 的 case 级条目现在会同步记录这些样本 artifacts。

### `filtering` ZQ500 GPU 路径

- `filtering` 的 ZQ500 GPU 后端已从原先的 hybrid 路径收敛为 device-native 主计算。
- 保持 `V2.4/V2.5` 语义不变：
  - 输入继续支持 host/device 双态
  - host 输入自动 H2D
  - device 输入直接复用
  - 输出继续为 device 对象
- `gust` 是唯一仍允许使用 CPU helper 的例外：只负责初值求解，主滤波仍在 GPU 完成。

### 性能口径

- `gpu_e2e_perf`：host 输入到 GPU 计算完成，不包含显式 `get()`
- `gpu_kernel_perf`：算子全部 GPU 计算阶段总时长
- 对 `filtering` 而言，`gpu_kernel_perf` 不再是系统性的 `0.000`
