**Plan**
建议把这轮定为独立子版本 V2.7，按“完整模块”交付，而不是只补实现。核心做法是：数学公式直接对齐仓内 Python 版 bsplines.py 与其行为基准 test_bsplines.py，工程流程则严格复用 waveforms_detail.hpp、waveforms.cu、waveform_test_support.cu、filter_design_test_support.cu 和 V2_6_1_plan.md 这套现成模式。

1. 先固化版本边界与实现基准。版本命名采用 V2.7，接口/输入输出语义继续遵守 V2_4_plan.md，CUDA 内部复用遵守 V2_5_plan.md，测试数据与报告组织遵守 V2_6_1_plan.md。
2. 新增公共数学层 src/common/bsplines_detail.hpp，把 cubic、quadratic、gauss_spline 的逐点公式和最小参数校验沉进去，风格对齐 waveforms_detail.hpp，同时提供 host/device 都能复用的函数。
3. 重写 CPU 占位实现 bsplines.cpp，按展平 values 遍历计算，输出继续用 RealArray 保持任意 shape 透传；只保留 n < 0 的异常，不额外增加和上游不一致的限制。这个步骤依赖第 2 步。
4. 重写 CUDA 占位实现 bsplines.cu，采用 waveforms.cu 的 thread_local workspace + as_device_array 归一化方式，输入支持 host/device 双态，输出继续为 device array。这个步骤依赖第 2 步。
5. 在 bsplines.cu 增加 g_last_kernel_ms 和 bsplines_test_hooks::consume_last_kernel_ms()，统计方式对齐 filter_design.cu 与 filtering.cu，保证后续 gpu_kernel_perf 能进入统一报告链。这个步骤依赖第 4 步。
6. 最小修正公开头 bsplines.hpp。签名结构和注释块布局不动，只删除“占位实现返回零张量”这类已经失真的描述，其余中文风格保持原样。这个步骤可以和第 4 步并行，但以第 2 步的数学语义为准。
7. 新建单测子目录 bsplines，补齐 tests/unit/bsplines/CMakeLists.txt、tests/unit/bsplines/bsplines_test_support.hpp、tests/unit/bsplines/bsplines_test_support.cu、tests/unit/bsplines/test_cubic.cpp、tests/unit/bsplines/test_quadratic.cpp、tests/unit/bsplines/test_gauss_spline.cpp。组织方式直接照搬 CMakeLists.txt 和 CMakeLists.txt。
8. 在 CMakeLists.txt 接入 bsplines 子目录，在 run_all_tests.sh 注册 cubic、quadratic、gauss_spline 三个 operator，命名风格与现有 waveforms/filter_design/filtering 一致。这个步骤依赖第 7 步。
9. 新增数据脚本 scripts/data/generate_bsplines_data.py，生成 data/reference/unit/bsplines 和 data/generated/unit/bsplines 下的 manifest、输入样本和期望结果。reference 以 SciPy 为准，仓内 Python 版只用于公式交叉校验。这个步骤依赖第 7 步，且可与第 8 步并行。
10. 补齐版本文档与入口：新增 docs/archive/version_plans/v2/V2_6_2_plan.md 和 docs/submission/READMEV2_6_2.md，然后更新 README.md 当前版本说明和入口链接。这个步骤依赖第 4、7、8、9 步。
11. 最后做分层验证：先定向构建 bsplines 相关 target，再跑模块级测试与报告，再视时间补一轮全量回归。这个步骤依赖前面全部完成。

**Relevant files**

- bsplines.hpp ：当前公开 API，需做最小注释修正
- bsplines.cpp ：当前 CPU 占位实现
- bsplines.cu ：当前 CUDA 占位实现
- waveforms_detail.hpp ：公共 detail 头模板
- waveforms.cu ：CUDA 输入归一化和 workspace 模板
- filter_design.cu ：kernel 计时 hook 模板
- waveform_test_support.cu ：manifest、report、artifacts 模板
- filter_design_test_support.cu ：简单算子的 GPU kernel perf 模板
- generate_filter_design_data.py ：SciPy 数据生成模板
- bsplines.py ：公式参考
- test_bsplines.py ：行为与 benchmark 参考
- V2_6_1_plan.md ：最新数据组织与全 GPU 规范
- README.md ：当前版本入口需要切到 V2.7

**Verification**

1. 运行 python3 scripts/data/generate_bsplines_data.py，确认三类算子的 manifest 和 expected/input CSV 都落盘到 bsplines 目录。
2. 定向构建 bsplines 相关 target，确认 test_support 和三个 test 可执行文件都能编过。
3. 运行 run_all_tests.sh --module bsplines --emit-report，确认报告目录、generated/output_samples、CPU/GPU 双样本和三类 perf 指标都完整。
4. 抽查边界行为是否正确：cubic 在 |x| >= 2 为 0，quadratic 在 |x| >= 1.5 为 0，gauss_spline 对 n < 0 抛 std::invalid_argument，N 维 shape 原样保留。
5. 条件允许时再跑一次 run_all_tests.sh --emit-report，确认新模块接入没有破坏现有流程。

**Decisions**

- 版本建议定为 V2.7，因为现有增量计划已经到 V2_6_1_plan.md，继续顺延最自然。
- 交付范围按完整模块执行，不拆成“先实现后补测试/文档”。
- 公开 API 只实现现有三个函数，不扩展为通用 bspline(order)。
- 单测主流程继续用 host 输入组织 case，保持与 V2.4 以来的 runner 习惯一致。
- 优先让 bsplines runner 产物完全适配现有 clean/report schema，而不是去扩展 clean_data.sh 的特判逻辑。

这份计划已经同步到会话计划里。如果你认可，我就保持这版作为后续执行基线。
