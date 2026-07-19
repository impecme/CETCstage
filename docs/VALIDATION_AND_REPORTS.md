# 验证与报告

## 验证层级

最终交付采用相互独立的验证层，不能用其中一层替代其他层：

1. 构建与链接：ZQ500 SDK、FFTW、公开头文件和目标库可解析；
2. 平台兼容：三份外部 XLSX 身份、派生 API 集合和源码禁止 API 扫描；
3. 契约静态审计：81 算子注册、公开接口、CPU/GPU 实现、类型和任务步骤；
4. 单算子正确性：all81 accuracy/full case；
5. 任务正确性：Task1/Task2 全规模、逐步误差和无效输入；
6. 当前代码运行记录：算子 full case、任务 L1-L6/最终场景、逐步结果和资源审计。

## 冻结结果

| 门禁 | 结果 | 主要执行 |
| --- | ---: | --- |
| all81 correctness | `81/81` | V6-0138 / V7 终门 |
| 公开接口 | `81/81` | V6-0138 |
| dtype 缺口 | `0` | V6-0138 / V7 终门 |
| Task 用例 | `24/24` | V6-0138 |
| Task 分步检查 | `168/168` | V6-0138 |
| 计算步骤 | `14/14`，public 6、mixed 8 | V6-0138 / V7 终门 |
| all81 L1-L6 runner | `486/486` | V6-0141 |
| 最终 Top30 | `30/30` | V7-0008 |
| 最终演示 wall | `101.971/240 s` | V7 最终口径 |

`486/486` 表示每个 perf runner 返回成功且 `status/pass=passed/true`，不等于全局
精度诊断为零。V6-0141 中 `spectral/coherence` L1-L5 共 5 行
`mixed_error > 0.01`，perf runner 并不以该诊断阈值判失败；独立 accuracy case 按其
校准容差通过。最终报告保留这一边界，不能把 runner gate 写成“全局无异常”。

## 当前代码报告目录

`scripts/validate.sh` 每次从干净的运行期目录开始。它完成静态审计、81 个算子 full
case、两个任务的 L1-L6 与最终场景后，才调用 `scripts/finalize_reports.py` 原子发布
`data/reports/`。目录只保留当前代码运行所需的精简数据：

- `units/<module>/<operator>/metrics.json`、`cases.csv`、`summary.md`：81 个算子；
- `units/benchmarks/summary.json`：所有算子的性能 case、运行时间、加速比、误差和
  无性能 case 标记；
- `demo/<task>/final/` 与 `demo/<task>/scales/L1` 至 `L6`：两个任务的 metrics、阶段、步骤
  和场景数据；
- `validation/`：接口、dtype、任务步骤和平台审计；
- `summary.md/json`：运行编号、源码指纹、数量和门禁结果；
- `FILES.sha256`：除清单自身外的当前报告文件校验。

首次当前代码验证前只有 `README.md`。任一检查失败时 finalizer 不会发布新报告，也不
会删除已经发布的报告。以下内容不进入主仓库：`history/<timestamp>`、console/log、
候选探针、图件、外层 tar、before/after、diff、CMakeCache、compile_commands、生成
样本和 Git 工作树指纹。

## 报告语义边界

- V6-0141 的 81 份 L6 metrics 是聚合统计，不含 30 次 timing 原始序列；部分算子
  没有 case-level 明细。L1-L5 的终版事实以冻结 benchmark CSV 为准。
- V7-0011 只有 Task1 源码与 runner 的字节回读，没有独立执行 manifest；最终编号
  来自冻结交付口径和精确回读目录，不能外推为一次新的完整 benchmark。
- V7-0009 的 Task2 L1 smoke 使用 `--skip-timing-validation`，原始 stability
  `0.506849 > 0.35`；它不是最终演示门。
- 本轮当前代码报告只能由 `gpu_04` 容器的完整验证生成；它不替代或重算下节的
  历史性能结论，也不生成图件。

## 兼容夹具信任模型

`tests/platform/config/zx_compat_fixture_manifest.json` 固定三表文件名、大小和 SHA256，
并冻结 source rows/API rows/unique APIs/forbidden APIs 计数
`900/816/830/315` 以及 unique、forbidden 集合摘要。生成器和扫描器从表格重新
计算这些值；源文件、行数或集合被
联合篡改时也会失败。夹具缺失时默认禁用依赖它的 CMake 测试，交付强门使用
`ZX_COMPAT_REQUIRE_FIXTURES=ON` 实现 fail-closed。
