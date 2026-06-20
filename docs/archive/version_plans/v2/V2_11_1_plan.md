# V2.11.1 `bsplines` / `radartools` / `spectral` / `filter_design` / `filtering` 单算子单入口测试重构

## Summary

- 当前这 5 个模块虽然已经按算子拆成多个 target，但 target 仍共用一个 `*_test_main.cpp`，再通过 `argv[0]` 反推算子名分发到 `run_*_target_tests()`。
- `V2.11.1` 的目标是把它们统一改成真正的“单算子单入口”模式，和仓库里更清晰的做法对齐：每个算子都有独立 `test_<op>.cpp`，`main()` 只调用该算子的 `run_<op>_tests()`，不再依赖可执行名分发。
- 本轮只改测试入口组织和版本文档，不改实现、不改数据 schema、不改 CLI 行为、不改报告字段。

## Key Changes

- `tests/unit/bsplines` 重构为每算子一个入口文件：
  - 新增 `test_cubic.cpp`、`test_quadratic.cpp`、`test_gauss_spline.cpp`
  - 每个文件只保留几行 `main()`，分别调用 `run_cubic_tests()`、`run_quadratic_tests()`、`run_gauss_spline_tests()`
  - `bsplines_test_support.hpp/.cu` 新增上述 3 个公开测试入口
  - 保留内部共享逻辑 `run_bsplines_operator_tests(op, ...)`，但不再通过 `argv[0]` 做公开分发
  - `bsplines_test_main.cpp` 和 `run_bsplines_target_tests()` 退出主路径；默认做法是直接删除，避免后续继续误用

- `tests/unit/radartools` 按同样模式重构：
  - 新增 `test_pulse_compression.cpp`、`test_pulse_doppler.cpp`、`test_ambgfun.cpp`、`test_cfar_alpha.cpp`、`test_ca_cfar.cpp`、`test_mvdr.cpp`
  - `radartools_test_support.hpp/.cu` 新增对应 `run_<op>_tests()` 声明与定义
  - 共享实现仍收敛到内部 `run_radartools_operator_tests(op, ...)`
  - 移除基于 `argv[0]` 的 `run_radartools_target_tests()` 主路径和共享 `radartools_test_main.cpp`

- `tests/unit/spectral` 按同样模式重构：
  - 新增 `test_lombscargle.cpp`、`test_periodogram.cpp`、`test_welch.cpp`、`test_csd.cpp`、`test_spectrogram.cpp`、`test_stft.cpp`、`test_istft.cpp`、`test_coherence.cpp`、`test_vectorstrength.cpp`
  - `spectral_test_support.hpp/.cu` 新增对应 `run_<op>_tests()` 声明与定义
  - 内部仍复用 `run_spectral_operator_tests(op, ...)`
  - 移除 `run_spectral_target_tests()` 的主路径和共享 `spectral_test_main.cpp`

- `tests/unit/filter_design` 按同样模式重构：
  - 复用现有 `test_kaiser_beta.cpp`、`test_kaiser_atten.cpp`、`test_cmplx_sort.cpp`、`test_firwin.cpp`、`test_firwin2.cpp`
  - `filter_design_test_support.hpp/.cu` 新增对应 `run_<op>_tests()` 声明与定义
  - 内部仍复用 `run_filter_design_operator_tests(op, ...)`
  - 移除 `run_filter_design_target_tests()` 的主路径和共享 `filter_design_test_main.cpp`

- `tests/unit/filtering` 按同样模式重构：
  - 复用现有各个 `test_<op>.cpp`
  - `filtering_test_support.hpp/.cu` 新增对应 `run_<op>_tests()` 声明与定义
  - 内部仍复用 `run_filtering_operator_tests(op, ...)`
  - 移除 `run_filtering_target_tests()` 的主路径和共享 `filtering_test_main.cpp`

- 5 个模块的 `CMakeLists.txt` 全部改成显式 source 绑定：
  - 从 `add_executable(${target} *_test_main.cpp)` 改为 `add_executable(${target} test_<op>.cpp)`
  - target 名保持不变，例如 `bsplines_test_cubic`、`radartools_test_mvdr`、`spectral_test_stft`
  - `add_test(NAME ... COMMAND ...)` 保持不变，因此 `ctest` 名称和 `run_all_tests.sh` 注册项都不需要调整

- 保持不变的行为：
  - test support 内部 case 加载、accuracy/perf、`emit-report`、`gpu_e2e_perf`、`gpu_kernel_perf`、报告写盘、`generated/input` 运行时生成逻辑全部不改
  - `scripts/test/run_all_tests.sh` 不改 target 注册表
  - `data/reference` / `data/generated` / `data/reports` schema 不改
  - 公开库接口、实现、include 注释不改

- 版本文档更新到 `V2.11.1`：
  - 新增 `docs/archive/version_plans/v2/V2_11_1_plan.md`
  - 新增 `docs/submission/READMEV2_11_1.md`
  - 更新 `README.md` 中当前版本说明与入口链接
  - 文档内容只说明测试入口组织从“共享 main + 可执行名分发”改为“单算子单入口”，不把本轮误写成实现层变更

## Public Interfaces

- 库的公开 API、类型、返回值、include 注释全部不变。
- 测试二进制名称保持不变。
- 变化只发生在测试入口层：
  - 旧的 `run_<module>_target_tests()` 不再作为主入口
  - 新的 `run_<op>_tests()` 成为每个 test 可执行文件的直接入口
- 版本文件命名默认采用仓库现有补丁版本规则：
  - `V2_11_1_plan.md`
  - `READMEV2_11_1.md`

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
  - 单独确认 `bsplines_test_*`、`radartools_test_*`、`spectral_test_*`、`filter_design_test_*`、`filtering_test_*` 全部 target 编译通过

- 入口组织验证：
  - `ctest --test-dir build -N -R 'bsplines_test_|radartools_test_|spectral_test_|filter_design_test_|filtering_test_'`
  - 确认 target 名称数量不变，只是 source 从共享 `*_test_main.cpp` 切到各自 `test_<op>.cpp`
  - 静态检查 5 个 support 头中存在对应的 `run_<op>_tests()` 声明，且不再依赖 `argv[0]` 反推算子名

- 模块回归：
  - `./scripts/test/run_all_tests.sh --module bsplines`
  - `./scripts/test/run_all_tests.sh --module radartools`
  - `./scripts/test/run_all_tests.sh --module spectral`
  - `./scripts/test/run_all_tests.sh --module filter_design`
  - `./scripts/test/run_all_tests.sh --module filtering`
  - `./scripts/test/run_all_tests.sh --emit-report`
  - 预期结果与重构前一致，accuracy/perf/report 都不发生语义变化

- 报告与数据回归：
  - 抽查 `data/reports/unit/bsplines`、`data/reports/unit/radartools`、`data/reports/unit/spectral`、`data/reports/unit/filter_design`、`data/reports/unit/filtering`
  - 确认 `latest_summary.md`、`latest_metrics.json`、`latest_cases.csv` 继续正常生成
  - 抽查 `--emit-report` 后 `generated/input` 与 `output_samples` 的写盘内容不变

## Assumptions

- “参考其他模块的实现”在本轮中的具体落地是：统一到真正的单算子单入口模式，而不是继续保留共享 `*_test_main.cpp` 再按可执行名分发。
- 由于 `run_all_tests.sh` 和 `ctest` 当前都是按 target 名称工作，target 名保持不变即可，不需要改脚本注册表。
- 补丁版本号采用仓库现有命名习惯，使用下划线文件名 `V2_11_1`，而不是新引入其他命名方式。
- 本轮不顺手重构 `windows` 的测试入口；`filter_design` 与 `filtering` 也纳入同一轮 `V2.11.1`。
