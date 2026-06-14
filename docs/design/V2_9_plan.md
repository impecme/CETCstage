# V2.9 `bsplines` 模块完整接入

## Summary

- 本轮版本定为 `V2.9`。目标是把 `bsplines` 按当前仓库主线模式完整接入，而不是只补占位实现。
- 实现基准固定为仓内 Python 版：
  - `cusignal/python/cusignal/bsplines/bsplines.py`
  - `cusignal/python/cusignal/test/test_bsplines.py`
- 约束固定：
  - 不改变已有接口模式。
  - CUDA 路径继续保持 host/device 双输入、device 输出。
  - 显存复用做法对齐现有 `waveforms` / `windows` / `filter_design`。
  - 测试、数据、报告组织对齐当前 canonical unit schema，也就是 `V2.8` 之后这套格式。

## Key Changes

### 1. 实现层

- 复用现有 `src/common/bsplines_detail.hpp` 作为唯一公共数学层，并直接按 Python 版语义对齐：
  - `cubic`
  - `quadratic`
  - `gauss_spline`
- 重写 `src/cpu/bsplines.cpp`：
  - 按展平 `values` 逐点计算。
  - 输出 shape 与输入完全一致。
  - `gauss_spline` 仅保留 `n < 0` 异常。
- 重写 `src/cuda/bsplines.cu`：
  - 使用真实逐元素 CUDA kernel，不再返回零张量。
  - 输入继续走 `as_device_array(...)` 归一化。
  - 引入 `thread_local` workspace，至少复用输入 scratch、输出 scratch 和必要临时缓冲，避免跨调用重复 `cudaMalloc/cudaFree`。
  - 返回值保持独立 `CudaRealArray`，workspace 不对外暴露别名。
  - 增加 `g_last_kernel_ms` 和 `bsplines_test_hooks::consume_last_kernel_ms()`，口径对齐现有模块。
- `include/cusignal/bsplines/bsplines.hpp` 只做最小修正：
  - 保留原注释块结构和风格。
  - 删除“占位实现返回零张量”这类失真描述。
  - 不改签名。

### 2. 测试与数据链路

- 新增 `tests/unit/bsplines/`，结构与其他模块一致：
  - `CMakeLists.txt`
  - `bsplines_test_support.hpp/.cu`
  - `test_cubic.cpp`
  - `test_quadratic.cpp`
  - `test_gauss_spline.cpp`
- `tests/unit/CMakeLists.txt` 接入 `add_subdirectory(bsplines)`。
- `scripts/test/run_all_tests.sh` 注册：
  - `bsplines:cubic`
  - `bsplines:quadratic`
  - `bsplines:gauss_spline`
- 测试流程保持和其他模块一致：
  - host 输入组织 case
  - accuracy 时显式 `get()` 做 CPU/reference 对比
  - `gpu_e2e_perf` 不包含 `get()`
  - `gpu_kernel_perf` 来自 `bsplines_test_hooks`
- 数据组织对齐当前 canonical schema：
  - reference manifest 使用 `expected_signal_file`
  - 单输出 generated sample 命名使用 `__cpu__signal.csv` / `__gpu__signal.csv`
  - reports/artifacts 语义与现有模块一致
- perf 输入改为运行时生成，行为对齐 `waveforms` / 修正后的 `filtering`：
  - `generated/manifest.json` 不再依赖预先存在的 `input/*.csv`
  - runner 在内存中生成 perf 输入
  - 仅 `--emit-report` 时把 `generated/input/*.csv` 和 `output_samples/*.csv` 落盘
- 现有 `scripts/data/generate_bsplines_data.py` 需要同步更新到 `V2.9` schema：
  - 保留 accuracy 数据生成
  - perf manifest 改成参数化描述，而不是写死 `x_file`

### 3. 文档与版本

- 新增：
  - `docs/design/V2_9_plan.md`
  - `docs/submission/READMEV2_9.md`
- 文档内容明确：
  - 这轮实现以仓内 Python `cusignal` 的 `bsplines.py` 与 `test_bsplines.py` 为行为基准
  - CUDA 路径遵守 `V2.4` host/device 双输入与 `V2.5` 显存复用原则
  - 测试数据与样本命名遵守 `V2.8` canonical schema
- 更新 `README.md`：
  - 当前版本改为 `V2.9`
  - 入口指向 `READMEV2_9.md`
  - 当前状态说明里把 `bsplines` 从未接入改为已接入 unit 链路
- 保留旧 `V2.7` bsplines 文档作为历史记录，不复用为当前版本文档。

## Test Plan

- 构建验证：
  - `./scripts/build/build_v1.sh`
  - 单独确认 `bsplines_test_support` 和 3 个 test target 编译通过
- 模块验证：
  - `./scripts/test/run_all_tests.sh --module bsplines`
  - `./scripts/test/run_all_tests.sh --module bsplines --emit-report`
- accuracy 重点：
  - `cubic`：覆盖 `|x| = 1, 2` 边界和二维输入
  - `quadratic`：覆盖 `|x| = 0.5, 1.5` 边界和二维输入
  - `gauss_spline`：覆盖不同 `n`、二维输入和 `n < 0` 异常
  - 所有 case 验证 shape 保持不变
  - 数值语义以仓内 Python `cusignal` 行为和 reference 数据为准
- perf 重点：
  - `gpu_e2e_perf` 仍是 host 输入 + H2D + CUDA 计算，不包含 `get()`
  - `gpu_kernel_perf` 不应系统性为 `0.000`
  - `--emit-report` 后确认 `generated/input` 与 `generated/output_samples` 都落盘，且同时有 `cpu/gpu` 两份样本
- 全量回归：
  - `./scripts/test/run_all_tests.sh --emit-report`

## Assumptions

- 本轮版本固定为 `V2.9`。
- `bsplines` 只实现现有公开的 3 个函数，不扩展为通用 `bspline(order)`。
- 行为基准优先级固定为：
  1. 仓内 Python `cusignal/bsplines/bsplines.py`
  2. 仓内 Python `cusignal/test/test_bsplines.py`
  3. 已提交的 reference 数据
- perf 输入采用运行时生成，不再要求仓库里预置 `data/generated/unit/bsplines/*/input/*.csv`。
