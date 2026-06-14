# V2.11.1 `bsplines` / `radartools` / `spectral` / `filter_design` / `filtering` 单算子单入口测试重构

## 版本信息

- 版本名称：`V2.11.1 bsplines / radartools / spectral / filter_design / filtering 单算子单入口测试重构`
- 完成时间：`2026-04-14`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.11.1` 不改库实现与数据 schema，只对 `bsplines`、`radartools`、`spectral`、`filter_design`、`filtering` 的 unit test 入口组织做重构。

本轮目标是把这 5 个模块从“共享 `*_test_main.cpp` + 通过 `argv[0]` 分发”的方式，统一改成真正的“单算子单入口”模式。

## 本轮内容

- `tests/unit/bsplines`
  - 新增 `test_cubic.cpp`
  - 新增 `test_quadratic.cpp`
  - 新增 `test_gauss_spline.cpp`
  - support 公开入口改为 `run_<op>_tests()`
- `tests/unit/radartools`
  - 新增每算子独立 `test_<op>.cpp`
  - support 公开入口改为 `run_<op>_tests()`
- `tests/unit/spectral`
  - 新增每算子独立 `test_<op>.cpp`
  - support 公开入口改为 `run_<op>_tests()`
- `tests/unit/filter_design`
  - 切换到已有 `test_<op>.cpp`
  - support 公开入口改为 `run_<op>_tests()`
- `tests/unit/filtering`
  - 切换到已有 `test_<op>.cpp`
  - support 公开入口改为 `run_<op>_tests()`
- 删除 3 个模块中不再使用的共享 `*_test_main.cpp`
- 删除 `filter_design` 与 `filtering` 中不再使用的共享 `*_test_main.cpp`
- `CMakeLists.txt`
  - 改为 target 和 `test_<op>.cpp` 一一绑定
  - target 名保持不变

## 保持不变的部分

- 公开 API、返回类型、`include/` 注释不变
- test support 内部 case 加载、accuracy/perf、`emit-report`、报告写盘逻辑不变
- `run_all_tests.sh` 注册项不变
- `data/reference`、`data/generated`、`data/reports` schema 不变

## 一键测试

模块级：

```bash
./scripts/test/run_all_tests.sh --module bsplines
./scripts/test/run_all_tests.sh --module radartools
./scripts/test/run_all_tests.sh --module spectral
./scripts/test/run_all_tests.sh --module filter_design
./scripts/test/run_all_tests.sh --module filtering
```

全量：

```bash
./scripts/test/run_all_tests.sh --emit-report
```

## 验证结论

`V2.11.1` 将 `bsplines`、`radartools`、`spectral`、`filter_design`、`filtering` 的 unit test 入口统一为真正的单算子单入口模式，测试二进制名称保持不变，现有一键测试链路无需改注册即可继续工作。
