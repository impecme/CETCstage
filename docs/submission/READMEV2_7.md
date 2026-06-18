# V2.7 `bsplines` 模块完整实现

## 版本信息

- 版本名称：`V2.7 bsplines 模块完整实现`
- 完成时间：`2026-04-05`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.7` 在 `V2.4` 的 host/device 双输入、device 输出语义和 `V2.5` 的内部显存复用基础上，补齐了 `bsplines` 模块的实现、数据与单测链路。

## 本轮内容

- `bsplines`
  - CPU 实现：`cubic`、`quadratic`、`gauss_spline`
  - ZQ500 GPU 实现：逐元素 device kernel、host/device 双输入归一化、device 输出
  - 公共实现：`src/common/bsplines_detail.hpp` 收敛共享公式与 order 校验
- 单测与报告
  - 新增 `tests/unit/bsplines`
  - 新增 `data/reference/unit/bsplines`
  - 新增 `data/generated/unit/bsplines`
  - 新增 `data/reports/unit/bsplines`
- 数据脚本
  - 新增 `scripts/data/generate_bsplines_data.py`

## 测试链路

- 新增单测目录：
  - `tests/unit/bsplines`
- 新增参考数据与 perf manifest：
  - `data/reference/unit/bsplines`
  - `data/generated/unit/bsplines`
- 数据生成脚本：
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
- 报告文件保持现有统一格式：
  - `latest_summary.md`
  - `latest_metrics.json`
  - `latest_cases.csv`

## 说明

- `cubic` 与 `quadratic` 的 accuracy case 覆盖分段边界输入和二维输入。
- `gauss_spline` 的 accuracy case 覆盖不同 order 和二维输入，并额外校验 `n < 0` 的异常路径。
- `bsplines` 的 reference 数据由 Python 脚本生成并提交到仓库。
