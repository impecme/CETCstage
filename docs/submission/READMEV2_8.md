# V2.8 unit data schema 统一

## 版本信息

- 版本名称：`V2.8 unit data schema 统一`
- 完成时间：`2026-04-05`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.8` 统一了 unit 测试链路的数据 schema、reference 命名、generated sample 命名和报告 artifacts 语义，使 `waveforms`、`windows`、`filter_design`、`filtering` 全部对齐 `waveforms/sawtooth`。

## 本轮范围

- 纳入：
  - `waveforms`
  - `windows`
  - `filter_design`
  - `filtering`
- 排除：
  - `bsplines`

## 本轮改动

- accuracy manifest 主输出字段统一为 `expected_signal_file`
- `filtering` 主输入字段统一为 `x_file` / `x_shape`
- single-output reference 主输出统一为 `expected/<case_id>.csv`
- single-output generated sample 统一为 `output_samples/<case_id>__{cpu|gpu}__signal.csv`
- 移除 `generated/input/*__spec.json`
- 单输出 artifacts 角色统一为 `cpu_signal` / `gpu_signal`

多输出算子继续保留附加语义文件：

- `quadrature`
- `envelope`
- `indices`
- `state`
- `time`

## 受影响文件

- 测试侧 schema / loader / writer：
  - `tests/unit/waveforms/waveform_test_support.cu`
  - `tests/unit/windows/windows_test_support.cu`
  - `tests/unit/filter_design/filter_design_test_support.cu`
  - `tests/unit/filtering/filtering_test_support.cu`
- 数据生成脚本：
  - `scripts/data/generate_filter_design_data.py`
  - `scripts/data/generate_filtering_data.py`
- 参考数据与生成数据：
  - `data/reference/unit/waveforms`
  - `data/reference/unit/windows`
  - `data/reference/unit/filter_design`
  - `data/reference/unit/filtering`
  - `data/generated/unit/waveforms`
  - `data/generated/unit/windows`
  - `data/generated/unit/filter_design`
  - `data/generated/unit/filtering`

## 测试方式

重跑数据脚本：

```bash
python3 scripts/data/generate_filter_design_data.py
python3 scripts/data/generate_filtering_data.py
```

重跑模块测试并落报告：

```bash
./scripts/test/run_all_tests.sh --module waveforms --emit-report
./scripts/test/run_all_tests.sh --module windows --emit-report
./scripts/test/run_all_tests.sh --module filter_design --emit-report
./scripts/test/run_all_tests.sh --module filtering --emit-report
```

## 验收结果

- reference manifest 不再提交 `expected_file`、`expected_values_file`、`expected_output_file`、`input_file`、`input_shape`
- single-output reference 不再提交 `__window.csv`、`__values.csv`、`__output.csv`
- single-output generated sample 不再落 `__window.csv`、`__values.csv`、`__output.csv`
- `waveforms/gausspulse`、`filter_design/cmplx_sort`、`filtering/resample`、`filtering/firfilter`、`filtering/lfilter`、`filtering/sosfilt` 的附加输出继续保留并参与校验

## 说明

- `bsplines` 不在本轮范围内，相关 schema 差异不在 `V2.8` 处理。
- 测试侧保留旧 key 的读兼容 fallback，用于本地旧数据过渡；仓库内 canonical schema 以 `V2.8` 为准。
