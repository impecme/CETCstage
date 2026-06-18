# V2.13 `correlate` / `demod` / `estimation` / `peak_finding` 完整接入

## 版本信息

- 版本名称：`V2.13 correlate / demod / estimation / peak_finding 完整接入`
- 完成时间：`2026-04-14`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.13` 将以下 4 个模块接入当前 unit 主线：

- `correlate`
- `demod`
- `estimation`
- `peak_finding`

交付内容包括真实 CPU/ZQ500 GPU 实现、单算子单入口 unit test、generated/reference/report 数据链路，以及一键测试注册。

## 本轮内容

- `correlate`
  - `correlate`
  - `correlate2d`
  - `correlation_lags`
- `demod`
  - `fm_demod`
- `estimation`
  - `KalmanFilter`
- `peak_finding`
  - `argrelextrema`
  - `argrelmin`
  - `argrelmax`

## 行为约束

- `cpu::*` 继续保持 host 输入输出。
- `zx_gpu_backend::*` 继续保持 host/device 双输入、device 输出。
- `KalmanFilter(dtype)` 当前只支持 `"float32"`；`"float64"` 显式报不支持。
- `correlate(method="direct")` 当前只支持 1D。
- `peak_finding` 继续只支持字符串 comparator，不扩展到 Python callable。
- `gpu_e2e_perf` 不包含 `get()`。

## 一键测试

模块级：

```bash
./scripts/test/run_all_tests.sh --module correlate --emit-report
./scripts/test/run_all_tests.sh --module demod --emit-report
./scripts/test/run_all_tests.sh --module estimation --emit-report
./scripts/test/run_all_tests.sh --module peak_finding --emit-report
```

全量：

```bash
./scripts/test/run_all_tests.sh --emit-report
```

## 数据与报告

- 新增 `data/reference/unit/correlate`
- 新增 `data/reference/unit/demod`
- 新增 `data/reference/unit/estimation`
- 新增 `data/reference/unit/peak_finding`
- 新增对应 `data/generated/unit/...`
- `output_samples` 保持 CPU/GPU 双样本落盘
- `latest_summary.md`、`latest_metrics.json`、`latest_cases.csv` 继续沿用现有 schema

## 验证结论

`V2.13` 已将这 4 个模块接入当前主线，保持公开接口模式不变，并对齐到仓库现有的 unit test、报告和一键测试组织方式。
