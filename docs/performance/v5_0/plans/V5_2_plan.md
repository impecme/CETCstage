# V5.2 工程规范与平台兼容计划

## 状态与目标

- 状态：进行中；对应交付：`docs/submission/READMEV5_2.md`。
- 目标：在任务和算子优化前关闭目录、算子契约、五种实数类型、`complex64` 和中科芯完整 API 兼容基础。

## 工作包

| ID | 工作包 | 允许修改 | 交付物 | 通过条件 |
| --- | --- | --- | --- | --- |
| V5.2-01 | 注册表与集合固化 | `scripts/test/`、算子矩阵 | `operator_sets.json`、81 条契约骨架 | task27=27、core53=53、extended28=28、all81=81，集合关系正确 |
| V5.2-02 | 目录与接口审计 | README、模块头文件、矩阵 | 81 条声明/CPU/GPU/测试/Doxygen 状态 | 81/81 有真实路径，无未登记公开算子 |
| V5.2-03 | 类型基础设施 | `core/types.hpp`、兼容层、类型测试 | 五种实数和 complex64 公共类型 | host/device copy、shape、零长度、边界值测试通过 |
| V5.2-04 | 逐算子类型契约 | 算子矩阵、manifest、测试支持 | 每算子适用/拒绝类型及数值策略 | 81/81 无“默认全部支持”或空白类型状态 |
| V5.2-05 | 复赛表解析与兼容矩阵 | `scripts/platform/`、平台文档 | Runtime/Driver/六库完整 CSV/JSON/Markdown | 源表非空行全覆盖，可追溯到 sheet/row |
| V5.2-06 | CMake 平台探针 | CMake、`tests/platform/`、平台脚本 | compile/runtime probe targets、禁止 API 扫描 | 项目使用 API 全通过，unsupported 引用为零 |
| V5.2-07 | 阶段回归与交付 | 报告和 V5.2 文档 | V5.2 summary、交付说明 | 所有前述门禁通过，无未解释失败 |

## V5.2-01 注册表与集合

1. 从 `run_all_tests.sh --list` 读取 81 个实际注册项，不手写第二份测试注册表。
2. 新增 `scripts/test/operator_sets.json`，每项使用 `module/operator` 唯一键。
3. 新增集合校验脚本，检查重复项、未知项、遗漏项及集合包含关系。
4. 将算子矩阵展开为 81 条记录，字段固定为：集合、声明、CPU、GPU、测试、输入域、输出域、类型、数值策略、平台库、任务步骤、工程状态、性能状态。

宿主机检查：

```bash
cd /home/usr_04/CETC
scripts/test/run_all_tests.sh --list > /tmp/v5_2_all81.tsv
python3 scripts/test/validate_operator_sets.py \
  --registry /tmp/v5_2_all81.tsv \
  --sets scripts/test/operator_sets.json
```

## V5.2-02 目录与接口审计

- 目录职责以根 README 为准。
- 模块声明固定在 `include/cusignal/<module>/<module>.hpp`，CPU/GPU 实现固定在对应模块 `.cpp`/`.cu`。
- 审计脚本只检查登记和签名，不用正则推断 C++ 类型等价；复杂重载由矩阵明确登记。
- Doxygen 至少包含 `@brief`、输入参数、返回值、支持类型、异常和平台限制。
- 缺失项标为 `待修改`，不能仅凭文件存在标为通过。

## V5.2-03 类型基础设施

- 复用现有 `Tensor<T>`、`DeviceSignal<T>`、`DeviceArray<T>` 和 `DeviceValueTraits<T>`，不另建平行容器。
- 增加 `Signal<T>`、`Array<T>` 便捷别名；保留 `RealSignal`、`RealArray` 等 FP32 兼容别名。
- 正式实数类型固定为 FP32、FP16、INT32、INT16、INT8。
- CPU FP16 使用明确的 IEEE binary16 存储/转换类型；GPU 优先映射 SDK `__half`。若 `cuda_fp16.h` 探针失败，则设备端使用 16 位存储加 FP32 计算 fallback，不能删除 FP16 支持要求。
- FP16 默认 FP32 累加；整数默认使用更宽中间类型，最终转换和饱和/截断规则由逐算子契约决定。
- complex 只允许 `std::complex<float>` 与 `cuFloatComplex`/`cuComplex` 映射，禁止 double 和其他复数模板实例化。

类型基础验证目标固定为 `cusignal_type_contract_tests`，覆盖五种实数与 complex64 的构造、H2D/D2H、边界值、空输入和缓存复用。

## V5.2-04 逐算子类型契约

- 先依据原 cuSignal/SciPy 行为判定适用类型，再实施模板实例化。
- 仅浮点算子把整数标为 `not_applicable`，测试必须验证明确异常或编译期不提供重载。
- complex 输出算子仅登记 `complex64`；精度字段固定包含 real、imag、magnitude/overall。
- 每个适用组合必须有 CPU/GPU 对应；不允许 CPU 支持但 GPU 静默回退 CPU。

## V5.2-05/06 平台兼容

新增脚本接口：

```bash
python3 scripts/platform/generate_zx_compat_matrix.py \
  --driver "复赛说明文件/CUDA 11.7 driver api.xlsx" \
  --runtime "复赛说明文件/CUDA 11.7 runtime API.xlsx" \
  --libraries "复赛说明文件/科学计算库实现列表.xlsx" \
  --output data/reports/zhongkexin/v5_2_compatibility
```

- 脚本使用 Python 标准库读取 XLSX ZIP/XML，不新增容器 Python 依赖。
- 输出 `compatibility.csv`、`compatibility.json`、`compatibility.md` 和 `forbidden_apis.txt`。
- 每行保留 source、sheet、row、module、API、support、restriction、probe_mode、probe_status。
- CMake 固定目标：`zx_compat_compile_probes`、`zx_compat_runtime_probes`、`zx_forbidden_api_scan`。
- supported 运行安全最小用例；partial 验证限制边界；unsupported 只做声明/禁止引用检查。
- `cudaDeviceReset`、跨设备、IPC、外部资源等不得在共享容器运行。

容器验证：

```bash
cd /CETC
source /zq500/sdk/env.sh
cmake -S . -B build-zx -DCMAKE_BUILD_TYPE=Release -DCUSIGNAL_PLATFORM=ZHONGKEXIN
cmake --build build-zx --target \
  cusignal_type_contract_tests \
  zx_compat_compile_probes \
  zx_forbidden_api_scan --parallel
ctest --test-dir build-zx -R '^(cusignal_type_contract|zx_compat_runtime_)' --output-on-failure
```

## 阶段关闭与回传

用户回传：构建日志、CTest 输出、四个集合计数、81 条契约状态汇总、兼容矩阵 summary、禁止 API 扫描结果。

关闭条件：V5.2-01 至 V5.2-07 全部关闭；五种实数和 complex64 基础测试通过；81 条契约完整；三个 Excel 全量覆盖；项目实际使用 API 全通过。任一数量不符、API 无来源行或类型语义未定义时不得进入 V5.3。
