# V2.12 `wavelets` 模块完整接入

## 版本信息

- 版本名称：`V2.12 wavelets 模块完整接入`
- 完成时间：`2026-04-14`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.12` 将 `wavelets` 从占位实现接入当前主线，补齐 CPU/CUDA 双实现、单算子单入口 unit test、reference/generated/report 数据链路和一键测试注册。

## 本轮内容

- 实现 `qmf`
- 实现 `morlet`
- 实现 `ricker`
- 实现 `morlet2`
- 实现 `cwt`
- 新增 `tests/unit/wavelets`
- 新增 `scripts/data/generate_wavelets_data.py`
- 新增 `data/reference/unit/wavelets`
- 新增 `data/generated/unit/wavelets`
- 新增 `data/reports/unit/wavelets`
- `run_all_tests.sh` 新增 `wavelets` 模块注册

## 行为约束

- `qmf` 按 SciPy/test 语义实现，不照搬当前 Python `_qmf_kernel`
- `cwt` 只支持 `"ricker"` 与 `"morlet2"`
- `cwt` 只覆盖当前 C++ 头文件可表达的实输入子集
- `zx_gpu_backend::*` 保持 host/device 双输入、device 输出
- `gpu_e2e_perf` 不包含 `get()`

## 一键测试

模块级：

```bash
./scripts/test/run_all_tests.sh --module wavelets
./scripts/test/run_all_tests.sh --module wavelets --emit-report
```

全量：

```bash
./scripts/test/run_all_tests.sh --emit-report
```

## 验证结论

`V2.12` 将 `wavelets` 模块接入到当前 unit 主线，保持现有公开接口模式不变，并与 `bsplines`、`radartools`、`spectral` 等模块对齐到同一套测试、数据和报告组织。

