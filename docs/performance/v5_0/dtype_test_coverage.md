# Dtype 测试覆盖审计

- status: `passed`
- operators: `81`
- dtypes: `complex64,float16,float32,int16,int32,int8`
- operator dtype missing edges: `0`

结论：`cusignal_type_contract_tests` 已覆盖 5 种实数和 complex64 的公共容器、shape、空输入和 H2D/D2H roundtrip。逐算子 dtype 测试仍需按 `compatibility_types` 补齐；当前表中的 missing 表示该算子声明兼容该 dtype，但现有 accuracy/perf manifest 没有可识别的该 dtype 用例。

| dtype | core roundtrip | 声明兼容算子数 | 已有逐算子 dtype 用例 | 缺口 |
| --- | --- | ---: | ---: | ---: |
| `complex64` | `true` | 21 | 21 | 0 |
| `float16` | `true` | 69 | 69 | 0 |
| `float32` | `true` | 78 | 78 | 0 |
| `int16` | `true` | 5 | 5 | 0 |
| `int32` | `true` | 7 | 7 | 0 |
| `int8` | `true` | 5 | 5 | 0 |

| 算子 | 兼容类型 | 已有 dtype 用例 | 缺少 dtype 用例 |
| --- | --- | --- | --- |
