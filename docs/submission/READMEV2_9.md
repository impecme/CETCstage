# V2.9 `bsplines` 模块完整接入

## 版本信息

- 版本名称：`V2.9 bsplines 模块完整接入`
- 完成时间：`2026-04-12`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.9` 在 `V2.4` 的 host/device 双输入、device 输出语义，`V2.5` 的显存复用原则，以及 `V2.8` 的 unit data schema 基础上，补齐了 `bsplines` 模块的实现、测试与数据链路。

## 本轮内容

- `bsplines`
  - CPU 实现：`cubic`、`quadratic`、`gauss_spline`
  - CUDA 实现：逐元素 device kernel、host/device 双输入归一化、device 输出
  - 公共实现：`src/common/bsplines_detail.hpp`
  - CUDA kernel 计时：`bsplines_test_hooks::consume_last_kernel_ms()`
- unit 测试
  - 新增 `tests/unit/bsplines`
  - 一键脚本注册 `bsplines` 的 3 个 operator
- 数据与报告
  - 新增并规范化 `data/reference/unit/bsplines`
  - 新增并规范化 `data/generated/unit/bsplines`
  - 新增 `data/reports/unit/bsplines`
  - perf 输入改为运行时生成，`--emit-report` 时落盘

## 行为基准

本轮 `bsplines` 的行为基准按以下优先级固定：

1. `cusignal/python/cusignal/bsplines/bsplines.py`
2. `cusignal/python/cusignal/test/test_bsplines.py`
3. 仓库内提交的 reference 数据

## 测试链路

- 新增单测目录：
  - `tests/unit/bsplines`
- 新增 reference 与 perf manifest：
  - `data/reference/unit/bsplines`
  - `data/generated/unit/bsplines`
- 数据脚本：
  - `scripts/data/generate_bsplines_data.py`

## 一键测试

```bash
./scripts/test/run_all_tests.sh --module bsplines
```

输出报告：

```bash
./scripts/test/run_all_tests.sh --module bsplines --emit-report
```

全量回归：

```bash
./scripts/test/run_all_tests.sh --emit-report
```

## 报告口径

- `gpu_e2e_perf`：host 输入到 CUDA 调用完成，不包含显式 `get()`
- `gpu_kernel_perf`：由 `bsplines_test_hooks` 输出的 kernel 总时长
- 报告文件保持统一格式：
  - `latest_summary.md`
  - `latest_metrics.json`
  - `latest_cases.csv`

## 说明

- `cubic` 与 `quadratic` 的 accuracy case 覆盖分段边界输入和二维输入。
- `gauss_spline` 的 accuracy case 覆盖不同 `n`、二维输入，并校验 `n < 0` 的异常路径。
- `bsplines` 的单输出 sample 命名继续遵守当前 canonical schema：
  - reference：`expected/<case_id>.csv`
  - generated sample：`<case_id>__{cpu|gpu}__signal.csv`
