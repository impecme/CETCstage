# CETC 中科芯 ZQ500 信号处理加速库

本项目面向第十届集创赛“中科芯”企业命题，围绕 ZQ500 GPU 上的信号处理加速库及算法开发展开。仓库当前只保留 CPU reference + 中科芯 ZQ500 GPU 双链路，覆盖赛题任务 1“雷达目标检测与多普勒分析”和任务 2“多域特征提取定位”，同时保留任务级 demo、单算子测试以及 Python 可视化链路，便于验证精度、性能和工程可交付性。

## 项目简介

- 面向比赛任务构建可运行、可验证的中科芯 ZQ500 信号处理工程。
- 将公共算子沉淀为按模块组织的信号处理库接口，支持后续扩展和复用。

仓库目前具备以下能力：

- `src/cpu/` 与 `src/zhongkexin/` 双实现路径，可做 CPU/GPU 结果对照。
- `demo/task1_radar/` 与 `demo/task2_features/` 提供任务级演示入口。
- `tests/smoke/` 提供最小编译与链接验证，`tests/unit/` 提供单算子测试链路。
- `demo/*/visualize_*.py` 可将任务输出转换为图表和报告文件。
- `scripts/test/benchmark_all_ops_scales.py` 可执行全量多规模性能采集，并在 CSV 中记录 CPU/GPU median 耗时与加速比。
- `scripts/test/plot_all_ops_benchmark.py` 可生成论文风格图件，默认输出 PNG，可通过 `--figure-set all --formats png,pdf,svg` 同时导出耗时、加速比与误差图。

## 项目特色

- 中科芯 ZQ500 GPU 主线实现，核心算子提供 CPU 与 ZQ500 GPU 两套可对照路径。
- 项目实数类型标准为 FP32、FP16、INT32、INT16、INT8；逐算子按照原始语义确定适用类型并提供 CPU/GPU 对应实现。
- 覆盖 waveforms、filtering、spectral、radartools、estimation、windows、wavelets、correlate 等模块。
- 支持 GPU 相对 CPU 的误差、耗时、e2e speedup、kernel speedup 统一报告。
- 支持 `default` 与 `large-gpu` 两套规模 profile，便于区分小规模开销和大规模吞吐。

## 代码目录结构

```text
CETC/
├── CMakeLists.txt              顶层构建入口，按 CUSIGNAL_PLATFORM 选择 CPU/ZQ500 目标
├── include/
│   └── cusignal/
│       ├── core/               公共类型、device storage、误差和平台工具
│       ├── <module>/           公开算子声明、参数语义和结果结构
│       └── zhongkexin/         ZQ500 兼容层与平台封装
├── src/
│   ├── common/                 CPU/GPU 共用校验、形状推导和算法辅助逻辑
│   ├── cpu/                    按模块组织的 CPU reference 实现
│   └── zhongkexin/             与 CPU 接口对应的 ZQ500 GPU 实现
├── demo/
│   ├── common/                 任务报告、计时和数据生成公共工具
│   ├── task1_radar/            任务一：雷达目标检测与多普勒分析流程
│   └── task2_features/         任务二：多域特征提取定位流程
├── tests/
│   ├── smoke/                  最小编译、链接和基础调用验证
│   ├── platform/               ZQ500 SDK、库和兼容 API 探针
│   └── unit/<module>/          单算子正确性、性能和报告测试
├── scripts/
│   ├── build/                  依赖安装和构建辅助脚本
│   ├── data/                   测试输入和参考数据生成脚本
│   ├── figures/                技术图和报告图生成脚本
│   ├── platform/               中科芯环境检查、阶段入口和 gate 汇总
│   └── test/                   单算子、全算子、任务和绘图测试入口
├── docs/
│   ├── migration/              V4 中科芯迁移依据、限制和历史台账
│   ├── performance/v5_0/       V5 性能优化计划、契约矩阵和独立台账
│   └── submission/             各版本交付说明和最终技术文档
├── data/
│   ├── reference/              受版本管理的静态参考输入、输出和 manifest
│   ├── generated/              运行生成的任务及中间数据
│   └── reports/                终测报告、任务 smoke、模块回归和组合图件
├── third_party/
│   ├── fftw/                   FFTW 离线包与本地安装目录
│   └── python_wheels/          容器 Python 依赖离线 wheel 缓存
└── 复赛说明文件/                CUDA 11.7 与中科芯科学计算库差异源表
```

算子模块遵循统一边界：声明位于 `include/cusignal/<module>/`，CPU 与 GPU 实现分别位于 `src/cpu/<module>.cpp` 和 `src/zhongkexin/<module>.cu`，对应测试位于 `tests/unit/<module>/`。任务 Demo 负责流程编排，不应维护与公共算子重复的算法实现。

## 项目环境

工程环境如下：

- 当前迁移验证 GPU：本服务器容器内中科芯 ZQ500
- 构建系统：`CMake >= 3.18`，当前验证版本为 `3.22.1`
- 语言标准：`C++17`
- 本地依赖：`FFTW` 通过 `./scripts/build/install_fftw.sh` 安装到 `third_party/fftw/install`

绘图与分析辅助环境如下：

- `python3`
- `numpy`
- `matplotlib`
- `scipy`：部分数据生成脚本会使用

中科芯统一验收脚本会自动检查基础依赖、FFTW 和 Python 可视化依赖；已安装项会跳过，缺失项优先使用随项目同步的 `third_party/python_wheels/`。

中科芯迁移各阶段都以该阶段范围内的全部功能闭环为完成标准。核心 demo 或 correctness 通过只是阶段证据的一部分；属于该阶段的报告、图件、数据生成、benchmark、边界输入和文档复现都必须可运行，或作为明确平台限制记录到迁移台账。

每个中科芯迁移版本或阶段关闭时，必须同步产出交付文档，统一放在 `docs/submission/`。交付文档命名采用 `READMEV<major>_<minor>.md` 风格，并按版本交付口径组织：版本目标、核心改动、解决的问题、验证结果、交付产物、完成判定和遗留风险。不要把交付文档写成“第几轮容器验证”的流水账；容器日志轮次只作为证据摘要或进入迁移台账。

当前中科芯构建入口固定使用 ZQ500 对应的 `dlcc --cuda-gpu-arch=dlgput64` 参数，不再提供 NVIDIA/A100 构建路径。

## 参赛者服务器与 Docker 环境

参赛者服务器的使用链路为：

```text
Windows VPN -> SSH 登录服务器 -> 进入本队 docker -> 在 docker 内开发和调试
```

注意事项：

- 当前项目记录的用户 ID 为 `usr_04`，UID 为 `1006`，当前主机名为 `supervisor-X7850H0`，项目路径为 `/home/usr_04/CETC`。
- VPN 账号、服务器账号和 docker 均按参赛队分配；账号密码以赛方通知为准，不应写入仓库。
- VPN 客户端当前仅支持 Windows；每天 `1:00-8:00` VPN 关闭，需提前保存代码。
- 服务器宿主机只作为文件中转和容器入口；参赛文件应放在本队个人用户目录 `/home/usr_04`。
- 严禁修改公共路径和其他参赛者用户目录。
- 代码编译、运行和调试应在本队 docker 容器内完成。
- docker 创建时使用 host network，容器与宿主机共用本机 IP、网卡和端口。

服务器上进入本队 docker：

```bash
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
```

每次新进入容器或新开容器 shell，都必须先初始化中科芯 SDK 环境：

```bash
cd /CETC
source /zq500/sdk/env.sh
```

初始化会设置 `PATH`、`LD_LIBRARY_PATH` 和 SDK 相关变量。未执行时，即使项目已经编译完成，运行二进制也可能报 `libLLVM-15.so` 等动态库缺失。后续所有容器命令均以已完成该初始化为前提；看到 shell 前缀包含 `(sdk)` 可作为环境已激活的提示。

退出容器：

```bash
exit
```

查看绑定 GPU 设备状态：

```bash
dlsmi
```

中科芯 SDK 示例位于：

```bash
/zq500/sdk/samples/
```

支持函数头文件可参考：

```bash
/zq500/cuda11/include
```

复赛说明文件已整理到：

```bash
复赛说明文件/
```

其中 `CUDA 11.7 runtime API.xlsx`、`CUDA 11.7 driver api.xlsx` 和 `科学计算库实现列表.xlsx` 说明了中科芯平台的 CUDA runtime、driver API 和科学计算库支持范围。迁移摘要见 `docs/migration/zhongkexin/platform_notes.md`。当前迁移必须特别注意：

- 不要假设中科芯平台完整支持 CUDA 11.7 全量 runtime/driver API。
- cuFFT 点数仅支持 2 的整数次幂，不足需要补 0。
- cuSOLVER LU 分解的 pivot 参数不能传入 `nullptr`。
- event timing 和性能 gate 需要先在中科芯 docker 内实测稳定性。

当前推荐同步与验证流程如下。先在服务器宿主机执行：

```bash
cd /home/usr_04/CETC
./copy_to_container.sh gpu_04
```

脚本会打印一条容器内替换命令。进入容器后执行打印出来的命令，例如：

```bash
/CETC.incoming.20260615124530/replace_container_project.sh /CETC
```

同步脚本只更新代码、脚本和文档；`data/reports/` 与 `data/generated/` 属于容器运行产物，不随宿主机同步覆盖。容器替换项目时也会保留已有 `build-zx`、`data/reports` 和 `data/generated`，避免覆盖刚跑出的 benchmark/report。脚本会刷新临时副本中的源码时间戳，防止保留的 `build-zx` 复用旧对象；若仍怀疑旧二进制参与运行，使用 `cmake --build build-zx --clean-first --target ...` 强制重编译目标。

然后在容器内执行当前阶段统一入口：

```bash
cd /CETC
source /zq500/sdk/env.sh
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

### V5.2-01 当前阶段验证

当前性能优化工作包为 `V5.2-01`，用于校验任务 27、核心 53、扩展 28 和全库 81 四个机器可读算子集合。完成宿主机同步并执行同步脚本打印的项目替换命令后，在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/test/run_all_tests.sh --list > /tmp/v5_2_all81.tsv

python3 scripts/test/validate_operator_sets.py \
  --registry /tmp/v5_2_all81.tsv \
  --sets scripts/test/operator_sets.json \
  --summary-json /tmp/v5_2_operator_sets_summary.json

for name in task27 core53 extended28 all81; do
  printf '%s=' "$name"
  python3 scripts/test/validate_operator_sets.py \
    --registry /tmp/v5_2_all81.tsv \
    --sets scripts/test/operator_sets.json \
    --list-set "$name" | wc -l
done

cat /tmp/v5_2_operator_sets_summary.json
```

预期结果：`task27=27`、`core53=53`、`extended28=28`、`all81=81`，summary 中 `status=passed`、`registry_count=81`、`source_path_check=passed`。该命令不运行 GPU 算子，只验证阶段范围、测试注册和代码路径。

### V5.2-02 当前阶段验证

`V5.2-02` 对 81 个算子的公共声明、CPU/ZQ500 GPU 定义、独立测试 target 和 Doxygen 输入输出说明执行静态审计。同步并替换项目后，在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/test/run_all_tests.sh --list > /tmp/v5_2_all81.tsv

python3 scripts/test/audit_operator_interfaces.py \
  --registry /tmp/v5_2_all81.tsv \
  --sets scripts/test/operator_sets.json \
  --output-dir data/reports/zhongkexin/v5_2_interface_audit \
  --contract-markdown /tmp/v5_2_operator_contract_inventory.md

python3 - <<'PY'
import json
from pathlib import Path

path = Path("data/reports/zhongkexin/v5_2_interface_audit/latest_interface_audit.json")
payload = json.loads(path.read_text())
print(json.dumps(payload["summary"], indent=2))
PY
```

预期结果：`operator_count=81`、`passed_count=81`、`failed_count=0`、`status=passed`。详细报告位于同目录的 `latest_interface_audit.json` 和 `latest_interface_audit.md`。

### V5.2-03 当前阶段验证

`V5.2-03` 建立 FP32、FP16、INT32、INT16、INT8 和 complex64 的公共 host/device 类型基础。同步并替换项目后，在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh

cmake -S . -B build-zx \
  -DCMAKE_BUILD_TYPE=Release \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCMAKE_CXX_COMPILER="$(command -v dlcc)"

cmake --build build-zx --target cusignal_type_contract_tests --parallel
ctest --test-dir build-zx -R '^cusignal_type_contract$' --output-on-failure
./build-zx/tests/unit/core_types/cusignal_type_contract_tests
```

预期 CTest 为 1/1 通过，直接执行输出 `[core/types] PASS real_types=5 complex_types=1`。该测试验证类型大小、累加类型、空输入、shape 和 H2D/D2H roundtrip；逐算子适用类型由 V5.2-04 确定。

### V5.2-04 当前阶段验证

`V5.2-04` 冻结 81 个算子的目标输入/输出类型、complex64 规则、累加类型、整数转换策略和当前实现类型。同步并替换项目后，在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/test/run_all_tests.sh --list > /tmp/v5_2_all81.tsv

python3 scripts/test/validate_operator_type_contracts.py \
  --registry /tmp/v5_2_all81.tsv \
  --contracts scripts/test/operator_type_contracts.json \
  --output-dir data/reports/zhongkexin/v5_2_type_contracts \
  --contract-markdown /tmp/v5_2_operator_type_contracts.md

python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path(
    "data/reports/zhongkexin/v5_2_type_contracts/latest_type_contracts.json"
).read_text())
print(json.dumps(payload["summary"], indent=2))
PY
```

预期：`status=passed`、`operator_count=81`、`policy_count=14`，实数类型恰好为五种，复数类型只有 complex64，且 `compatibility_gap_count=0`。该契约区分 `current_types` 原生直达类型和 `compatibility_types` 兼容路径；兼容路径允许 FP16 经 FP32 中间计算、整数经扩展累加/受控转换覆盖，但不会把兼容路径误写成每个 dtype 都有独立原生 kernel。原 cuSignal complex64 对齐清单当前应显示 21 个公共契约已支持项；另有 8 个 filtering/resampling dtype-preserving 复数扩展路径不属于当前赛题强制项。

当前类型契约通过：81 个算子唯一归入 14 个策略，整数相关算子 8 个，complex64 相关算子 21 个。

### V5.2-05 当前阶段验证

`V5.2-05` 逐行解析 CUDA 11.7 Driver、Runtime 和六类科学计算库兼容表。同步并替换项目后，在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh
python3 scripts/platform/generate_zx_compat_matrix.py \
  --driver "复赛说明文件/CUDA 11.7 driver api.xlsx" \
  --runtime "复赛说明文件/CUDA 11.7 runtime API.xlsx" \
  --libraries "复赛说明文件/科学计算库实现列表.xlsx" \
  --output data/reports/zhongkexin/v5_2_compatibility \
  --summary-markdown /tmp/v5_2_platform_compatibility.md

python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path(
    "data/reports/zhongkexin/v5_2_compatibility/summary.json"
).read_text())
print(json.dumps(payload, ensure_ascii=False, indent=2))
PY
```

预期：`status=passed`、`source_row_count=900`、`api_row_count=816`、`unique_api_count=830`、`forbidden_api_count=315`。完整 CSV/JSON/Markdown、禁止 API 清单均写入同一报告目录；本工作包只关闭源表覆盖和分类，实际编译、运行及禁止引用扫描由 V5.2-06 完成。

2026-06-21 容器实测计数全部符合预期，V5.2-05 已关闭。

### V5.2-06 当前阶段验证

`V5.2-06` 验证 Runtime/Driver 声明、六类科学计算库链接、安全运行调用，以及项目不存在禁止 API 引用。同步并替换项目后，在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh

cmake -S . -B build-zx \
  -DCMAKE_BUILD_TYPE=Release \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCMAKE_CXX_COMPILER="$(command -v dlcc)"

cmake --build build-zx --target \
  zx_compat_compile_probes \
  zx_compat_runtime_probes \
  zx_forbidden_api_scan --parallel

ctest --test-dir build-zx \
  -R '^(zx_compat_runtime_safe|zx_forbidden_api_scan_test)$' \
  --output-on-failure

./build-zx/tests/platform/zx_compat_runtime_probes
cat build-zx/reports/zx_compatibility/api_usage.json
```

预期两个 CTest 均通过；运行探针输出 `[zx/compat] PASS`，并显示 Runtime、FFT、BLAS、DNN、SOLVER、SPARSE、RAND 全部 passed；API 使用报告应为 `status=passed`、`violation_count=0`、`unresolved_count=0`。

2026-06-21 容器实测两个 CTest 2/2 通过，七项平台类别均为 passed，315 个禁止 API 零命中、零未解析，V5.2-06 已关闭。

### V5.2-07 当前阶段验证

`V5.2-07` 执行 V5.2 最终阶段门禁：四集合、81 项接口、81 项类型契约、兼容矩阵、类型/平台 CTest 和全库 81 算子 accuracy 回归。同步并替换项目后，在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/platform/run_v5_2_gate.sh 2>&1 | tee /tmp/v5_2_gate.log

cat data/reports/zhongkexin/v5_2_gate_latest/summary.json
```

预期最后输出 `[v5.2-gate] PASS`；summary 为 `status=passed`、`operator_count=81`、`operator_accuracy_passed_count=81`，且所有 `checks` 均为 `true`。任一算子 accuracy、契约、CTest 或 API 门禁失败时脚本立即停止，不生成通过结论。

2026-06-21 容器实测 81/81 accuracy、3/3 CTest 以及全部 8 项 checks 通过，V5.2 阶段已关闭。

### V5.3-01 当前阶段验证

`V5.3-01` 审计 Task1/Task2 每个步骤的 CPU/GPU 来源、公共算子映射、任务私有计算及当前计时/精度缺口。同步并替换项目后，在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh
python3 scripts/test/audit_task_steps.py \
  --contracts scripts/test/task_step_contracts.json \
  --output-dir data/reports/zhongkexin/v5_3_task_step_audit \
  --summary-markdown /tmp/v5_3_task_step_audit.md

python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path(
    "data/reports/zhongkexin/v5_3_task_step_audit/latest_task_step_audit.json"
).read_text())
print(json.dumps(payload["summary"], ensure_ascii=False, indent=2))
PY
```

预期 `status=passed`、`task_count=2`、`step_count=16`、`calculation_step_count=14`、`migration_step_count=11`、`timing_gap_count=2`、`accuracy_gap_count=5`。这里的 passed 表示审计映射完整；11 个 mixed/private 步骤尚未公共化，将由 V5.3-03/04 处理。

2026-06-21 容器审计结果与预期一致，V5.3-01 已关闭。

### V5.3-02 当前阶段验证

`V5.3-02` 为两任务生成统一的 `latest_step_metrics.csv/json/md`，保留原有报告并明确不可用字段。同步后在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/test/run_task_demos.sh \
  --build-dir build-zx --build --repeat 1 --skip-timing-validation

python3 scripts/test/validate_task_step_reports.py \
  --report-root data/reports/demo \
  --output data/reports/zhongkexin/v5_3_step_reports_summary.json

cat data/reports/zhongkexin/v5_3_step_reports_summary.json
```

预期两个任务均 PASS，schema 验证为 `status=passed`、`task_count=2`、`step_count=14`。本轮 `--skip-timing-validation` 只跳过既有硬阈值判定，仍完整记录耗时；已确认 Task2 `spectrogram` 为约 3.5 秒热点，后续单独优化。`gpu_kernel_ms=null` 不用 E2E 时间伪造；Task1 power-map 误差已补齐。

2026-06-22 容器两任务均 PASS，步骤报告 14/14、已有误差 11 项、schema 零失败，V5.3-02 已关闭。

### V5.3-03 当前阶段验证

`V5.3-03` 将 Task1 的行维 FFT shift、功率图和最终检测迁入公共 `radartools` CPU/GPU 接口，并删除任务私有 CUDA 文件。同步后在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh

cmake -S . -B build-zx \
  -DCMAKE_BUILD_TYPE=Release \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCMAKE_CXX_COMPILER="$(command -v dlcc)"

cmake --build build-zx --target \
  task1_radar_demo \
  radartools_task_test_fftshift_rows \
  radartools_task_test_power_map \
  radartools_task_test_detect_peak --parallel

ctest --test-dir build-zx -R '^radartools_task_test_' --output-on-failure
./build-zx/demo/task1_radar/task1_radar_demo --repeat 1 --invalid-input-checks

python3 scripts/test/audit_task_steps.py \
  --contracts scripts/test/task_step_contracts.json \
  --output-dir data/reports/zhongkexin/v5_3_task_step_audit \
  --summary-markdown /tmp/v5_3_task_step_audit.md
```

预期 3/3 CTest 和 Task1 均 PASS；审计应为 `public_calculation_step_count=6`、`migration_step_count=8`、`timing_gap_count=1`、`failure_count=0`。

### V5.4 已关闭验证

V5.4 核心 53 算子优化已关闭。`v5_4_core53_batch_close_probe` 已完成，核心 53/53 全部通过，失败 0，显存峰值 2453 MiB。复现命令：

```bash
cd /CETC
source /zq500/sdk/env.sh

OPERATOR_SET=core53 \
RUN_TASK_SWEEP=0 \
BENCH_SCALE_LEVELS=6 \
BENCH_WARMUP=1 \
BENCH_REPEAT=3 \
BENCH_REPORT_MODE=concise \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/v5_4_core53_batch_close_probe \
STAGE4_REPORT_ROOT=data/reports/zhongkexin/v5_4_core53_batch_close_probe_latest \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage5_4_core53_batch_close_probe.log
```

任务侧 smoke 已通过：Task1/Task2 均 PASS，`status=passed`、`task_count=2`、`step_count=14`、`failure_count=0`。核心 53 契约/类型复核也已通过：interface 81/81 passed，type contracts 81/81 passed。受影响模块 full 回归已通过：`filter_design` 5/5、`filtering` 17/17、`radartools` 6/6、`spectral` 9/9、`bsplines` 3/3、`wavelets` 5/5、`windows` 23/23。关闭汇总命令：

```bash
cd /CETC
source /zq500/sdk/env.sh

python3 scripts/platform/summarize_v5_4_gate.py
cat data/reports/zhongkexin/v5_4_gate_latest/summary.json
cat data/reports/zhongkexin/v5_4_gate_latest/summary.md
```

实测结果为 `status=passed`、core53 `53/53`、模块回归 `passed`、任务 smoke `passed`、contracts `passed`、组合图件 `12` 个模块图覆盖 `53` 个算子。

### V5.5 已关闭验证

V5.5 已完成扩展 28、全库 81、任务步骤、类型覆盖和平台项目使用范围验收。若需要复跑全库性能终测，同步后在容器运行：

```bash
cd /CETC
source /zq500/sdk/env.sh

OPERATOR_SET=extended28 \
RUN_TASK_SWEEP=0 \
BENCH_SCALE_LEVELS=6 \
BENCH_WARMUP=1 \
BENCH_REPEAT=3 \
BENCH_REPORT_MODE=concise \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/v5_5_extended28_probe \
STAGE4_REPORT_ROOT=data/reports/zhongkexin/v5_5_extended28_probe_latest \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage5_5_extended28_probe.log
```

V5.5 最终交付结论见 `docs/submission/READMEV5_5.md`。中间 probe、完整日志和大体积图件不进入仓库，只保留 `data/reports/` 下的精简交付证据。

### V6.0 当前阶段验证

第六版进入任务优先的深度性能优化：深度优化 Task1/Task2 和任务相关算子，轻度优化赛题提到的算子库；原 cuSignal 中赛题未提到的算子暂不做进一步性能优化。计划见 `docs/performance/v5_0/plans/V6_0_plan.md`。

`run_zhongkexin_stage4.sh` 会自动检查依赖、配置中科芯 `build-zx`、运行 Task1/Task2 L1-L6 scale sweep、执行全量算子多规模 benchmark，并生成报告和图件。当前交付验收只面向 CPU reference + 容器内 ZQ500 GPU。

## 精度与数据类型约定

项目以 FP32、FP16、INT32、INT16、INT8 五种实数类型作为正式支持范围，并按逐算子适用性矩阵确定具体组合。所有适用组合均以 CPU reference 与容器内 ZQ500 GPU 的数值一致性和任务闭环为验收口径。

- 公共接口保留 `dtype` 参数并逐步模板化；FP32、FP16、INT32、INT16、INT8 是统一类型集合，不适用类型必须由算子契约明确拒绝。
- CPU reference 与 ZQ500 GPU 对照使用相同输入和输出类型；单算子 metrics 保留 `max_abs_error`、`max_rel_error`、`rmse`，全量 benchmark 主表使用 `mixed_error` 展示近零保护后的主误差。
- `waveforms`、`filtering/detrend`、`spectral/vectorstrength`、`correlate`、`windows`、`estimation` 等路径中的中间量、workspace、scratch buffer、测试统计与数据生成脚本已同步为单精度口径。
- `data/reference` 与 `data/generated` 的活动 manifest 已同步到 `float32` / `complex64` 描述；窗口参数中的命名实数参数统一为 `named_float` 语义。
- 正式实数类型为 FP32、FP16、INT32、INT16、INT8，但只为原始算子语义允许的类型提供实现；纯浮点算子无需实现整数路径。
- 默认返回或处理复数的算子只支持 `complex64`。CPU 使用 `std::complex<float>`，GPU 使用 `cuFloatComplex`/`cuComplex`，不实现平台不支持的 `complex128`。

大规模结果中少数算子的原始相对误差可能较大，通常来自参考值接近零时 ratio 被放大；全量报告默认使用 `mixed_error`，在近零区域用绝对误差判断。

## 快速开始

中科芯当前推荐入口是上文的 `scripts/platform/run_zhongkexin_stage4.sh` 全量命令；它会覆盖依赖检查、构建配置、任务 demo、benchmark、报告和图件生成。

完成构建后，也可以直接运行两个任务级 demo：

```bash
./build/demo/task1_radar/task1_radar_demo
python3 demo/task1_radar/visualize_task1.py

./build/demo/task2_features/task2_features_demo
python3 demo/task2_features/visualize_task2.py
```

运行结果会输出到 `data/generated/demo/` 与 `data/reports/demo/` 下对应任务目录。
任务级 demo 的 `latest_summary.md` 与 `latest_metrics.json` 也会输出 `mixed_error`，近零参考值使用绝对误差，其他区域使用相对误差。

## 任务级 Demo 验收

Task1/Task2 demo 已升级为任务级自验收入口。C++ demo 会在 `latest_metrics.json` 中写出 `validation`、`resource_usage` 和 `repeat_runs`；`validation.pass=false` 时可执行程序返回非零。

统一验收入口：

```bash
scripts/test/run_task_demos.sh --no-build --repeat 5 --require-visualization-deps
```

6 档任务规模扫测：

```bash
scripts/test/run_task_demos.sh --no-build --scale-sweep --repeat 3 --require-visualization-deps
```

任务级 6 档规模：

| task | level | primary size | template | FFT / filter / spectrogram |
| --- | ---: | --- | ---: | --- |
| Task1 | L1 | `32 pulses x 128 samples` | 32 | pulse FFT `128`, doppler FFT `32` |
| Task1 | L2 | `48 pulses x 256 samples` | 64 | pulse FFT `256`, doppler FFT `64` |
| Task1 | L3 | `64 pulses x 256 samples` | 64 | pulse FFT `256`, doppler FFT `64` |
| Task1 | L4 | `96 pulses x 512 samples` | 128 | pulse FFT `512`, doppler FFT `128` |
| Task1 | L5 | `128 pulses x 1024 samples` | 256 | pulse FFT `1024`, doppler FFT `128` |
| Task1 | L6 | `192 pulses x 1536 samples` | 384 | pulse FFT `2048`, doppler FFT `256` |
| Task2 | L1 | `16 frames x 512 samples` | 128 | filter `65`, spectrogram `64/48/128` |
| Task2 | L2 | `32 frames x 768 samples` | 192 | filter `97`, spectrogram `96/72/128` |
| Task2 | L3 | `48 frames x 1024 samples` | 256 | filter `129`, spectrogram `128/96/256` |
| Task2 | L4 | `64 frames x 1536 samples` | 384 | filter `161`, spectrogram `192/144/256` |
| Task2 | L5 | `80 frames x 2048 samples` | 512 | filter `193`, spectrogram `256/192/512` |
| Task2 | L6 | `96 frames x 3072 samples` | 768 | filter `257`, spectrogram `384/288/512` |

深度内存/显存检查：

```bash
scripts/test/run_task_demos.sh --no-build --repeat 2 --leak-check
```

验收口径：

- Task1：CPU/GPU 检测一致、GPU 命中注入目标；默认 L3 下 `pulse_compression`、`pulse_doppler`、`ambgfun_surface` 的 `mixed_error <= 1e-4`，`cfar_threshold` 的任务级中间阈值 `mixed_error <= 5e-3`；L4-L6 大规模扫测对 `pulse_doppler` 和 `cfar_threshold` 使用规模化阈值，完整口径见本文“任务级 Demo 验收”和“全量 Benchmark 与作图”两节。
- Task2：CPU/GPU track 一致、GPU Kalman track 在 truth 容差内；`filtered`、`correlate`、`spectrogram`、`cwt`、`feature_score` 的 `mixed_error <= 1e-4`，`kalman_track` 以 RMSE/业务容差作为正式 gate。
- 资源与稳定性：repeat 内检查业务一致性、GPU total 相对中位数抖动、ZQ500 GPU free memory 漂移和当前 RSS 增长；报告记录 RSS peak、GPU free/total 与 device name。
- 异常输入：`--invalid-input-checks` 会跑固定非法配置矩阵，要求返回明确 `std::invalid_argument` 和字段名。
- `--leak-check` 为可选深度检查项，会在可用时运行 `compute-sanitizer --tool memcheck`；深检时跳过性能 gate，避免 sanitizer 放大耗时误触发失败。未执行 `--leak-check` 时，提交文档中应将 compute-sanitizer / ASAN / LSAN 标记为预留检查项。

汇总报告会写到 `data/reports/demo/latest_task_demo_report.md` 和 `data/reports/demo/latest_task_demo_report.json`。
规模扫测会额外写出 `data/reports/demo/latest_task_demo_scale_benchmark.csv`、`latest_task_demo_scale_report.json` 和 `latest_task_demo_scale_report.md`，并将每档产物归档到 `data/reports/demo/<task>/scales/L<N>/`。扫测结束后 latest 与可视化默认恢复为 L3 兼容场景。
在中科芯容器内如需避开被占用的设备，可按平台环境支持设置设备可见性变量；当前迁移复测以容器内 ZQ500 为准。

## 编译

仅构建核心库：

```bash
cmake --build build --target cusignal_cpu cusignal_zx_gpu --parallel
```

构建 smoke 示例：

```bash
cmake --build build --target smoke_demo1 --parallel
```

## 短小验证示例

最小验证入口为 `smoke_demo1`，用于确认核心库已经完成编译、链接和基础调用。

```bash
cmake --build build --target smoke_demo1 --parallel
./build/tests/smoke/smoke_demo1
```

```cpp
#include "cusignal/cusignal.hpp"
#include <iostream>

int main()
{
    const cusignal::core::RealSignal t{-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 4.0};
    const auto duty = cusignal::zx_gpu_backend::windows::hann(static_cast<int>(t.size()));
    const auto saw = cusignal::zx_gpu_backend::waveforms::sawtooth(t, duty);
    const auto square = cusignal::zx_gpu_backend::waveforms::square(saw, duty);

    std::cout << "demo1:";
    for (float value : saw.get())
    {
        std::cout << ' ' << value;
    }
    std::cout << '\n';
    return 0;
}
```

输出片段如下：

```text
demo1: -0.0450704 -0.215739 -0.181175 -1 -0.665108 0.0414869 0.287437 -0.27324
```

## 测试

统一测试入口为 `./scripts/test/run_all_tests.sh`。脚本会根据筛选条件自动配置并构建对应测试目标，再逐个执行 runner。

常用参数：

- `--module NAME`：按模块筛选，例如 `waveforms`、`radartools`、`spectral`
- `--operator NAME`：按单个算子筛选
- `--case-set NAME`：切换测试集合，可选 `smoke`、`accuracy`、`perf`、`full`
- `--no-build`：跳过重新配置和编译，直接复用已有二进制
- `--emit-report`：输出报告和生成样本
- `--verbose`：打印更详细的 runner 日志
- `--warmup N` / `--repeat N`：调整性能测试的预热与重复次数
- `--list`：只列出当前筛选条件下可运行的测试项

常见用法：

全量运行：

```bash
./scripts/test/run_all_tests.sh --emit-report
```

仅运行单个模块：

```bash
./scripts/test/run_all_tests.sh --module spectral
```

仅运行单个算子：

```bash
./scripts/test/run_all_tests.sh --module radartools --operator ambgfun
```

只查看已注册测试项，不执行：

```bash
./scripts/test/run_all_tests.sh --list --module radartools
```

复用现有构建结果：

```bash
./scripts/test/run_all_tests.sh --module windows --no-build
```

切换测试集合：

```bash
./scripts/test/run_all_tests.sh --module filtering --case-set smoke
./scripts/test/run_all_tests.sh --module filtering --case-set perf --warmup 10 --repeat 50
```

输出报告与样本：

```bash
./scripts/test/run_all_tests.sh --module radartools --emit-report --verbose
```

最小 CTest 验证：

```bash
ctest --test-dir build -R '^smoke_demo1$' --output-on-failure
```

## 全量 Benchmark 与作图

当前中科芯全量 benchmark 与作图由统一 Stage4 入口执行：

```bash
cd /CETC
source /zq500/sdk/env.sh
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

该入口会生成 `data/reports/unit/benchmarks/zhongkexin_stage4_full/latest_all_ops_scale_benchmark.csv` 和 `figures/` 下的 benchmark 图件。

如需单独重生成论文风格图件：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/zhongkexin_stage4_full/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/zhongkexin_stage4_full/figures \
  --figure-set all \
  --dpi 450
```

主要输出：

- `latest_all_ops_scale_benchmark.csv`
- `figures/figure_1_accuracy_performance_overview.png`
- `figures/figure_2_cpu_gpu_e2e_time_heatmaps.png`
- `figures/figure_3_e2e_speedup_heatmap.png`
- `figures/figure_4_largest_scale_cpu_vs_gpu_scatter.png`
- `figures/figure_5_largest_scale_speedup_rank.png`
- `figures/operator_figures/module_operator_curves_<module>.png`
- `figures/operator_figures/latest_operator_curve_manifest.csv`

默认保留全量 benchmark CSV 和图件。CSV 追加包含 `cpu_median_ms`、`gpu_e2e_median_ms`、`gpu_kernel_median_ms`、`gpu_e2e_min_ms`、`gpu_e2e_max_ms`，用于直接绘制 CPU/GPU 耗时与加速比图。`figure_1` 到 `figure_5` 是全局总览图，行/点代表算子、列代表 L1-L6 或最大规模；`figures/operator_figures/` 下按模块生成组合压缩曲线图，每个算子保留 CPU/GPU e2e median 耗时和 e2e/kernel speedup 的 L1-L6 趋势，不再生成一算子一图。

测试脚本、规模策略、性能图生成方式和任务级验收口径已在本文档中统一说明。提交技术文档如需引用工程说明，统一引用本文件。

## 提交文档证据索引

本文档作为工程说明的统一入口，提交技术文档中的附录、图件、报告和验证数据均可从以下路径追溯。

| 证据类型 | 工程路径 | 用途 |
|---|---|---|
| 报告目录说明 | `data/reports/README.md` | 当前保留报告、仓库外垃圾目录和不保留项 |
| V5.5 交付文档 | `docs/submission/READMEV5_5.md` | 全库 81、任务步骤、类型兼容、平台适配和关键优化汇总 |
| dtype 兼容最终摘要 | `data/reports/zhongkexin/v5_5_dtype_compat_final/README.md` | dtype 覆盖与精简证据索引 |
| dtype 覆盖审计 | `data/reports/zhongkexin/v5_5_dtype_compat_final/dtype_test_coverage.json` | 五种实数和 complex64 的逐算子覆盖结论 |
| 类型契约 | `data/reports/zhongkexin/v5_5_type_contracts/latest_type_contracts.json` | 81 算子的类型策略、兼容路径和禁止类型 |
| 任务步骤审计 | `data/reports/zhongkexin/v5_3_task_step_audit/latest_task_step_audit.json` | Task1/Task2 14 个计算步骤公共算子链路、计时和精度覆盖 |
| filtering dtype 复跑 | `data/reports/unit/filtering/latest_metrics.json` | filtering 模块 dtype 兼容最终复跑 |
| coherence FP16 复跑 | `data/reports/unit/spectral/coherence/latest_metrics.json` | `spectral/coherence` FP16 兼容修正用例 |
| 单元测试入口 | `tests/unit/` | 81 个已迁移算子的测试覆盖 |
| 公开接口 | `include/cusignal/` | 库函数头文件与公开 API |
| ZQ500 GPU 实现 | `src/zhongkexin/` | GPU 加速实现源码 |
| CPU 基线 | `src/cpu/` | CPU 参考实现源码 |

## 项目结构

```text
CETC/
├─ include/       公共头文件、模块接口和 ZQ500 兼容层
├─ src/           CPU reference、ZQ500 GPU 和共用实现
├─ demo/          Task1/Task2 任务级流程与可视化脚本
├─ tests/         smoke、platform 和按模块组织的单算子测试
├─ scripts/       构建、数据、测试、平台 gate 和图件脚本
├─ docs/          迁移、性能优化、交付说明和最终技术文档
├─ data/          参考数据、运行生成数据和终测报告
├─ third_party/   FFTW 离线依赖和 Python wheel 缓存
└─ 复赛说明文件/  CUDA 11.7 与中科芯科学计算库差异源表
```

## data 目录详细说明

`data/` 是项目中所有测试基准、运行生成数据和结果报告的统一落盘位置。按职责可以分成三层：

```text
data/
├─ reference/   仓库内维护的静态基准数据
├─ generated/   运行期生成的输入、样本和用例清单
└─ reports/     demo 与测试产生的报告、指标和图表
```

### `data/reference/`

`reference/` 保存受版本管理的对照数据，当前主要服务于单算子测试链路。目录通常按 `unit/<module>/<operator>/` 组织：

```text
data/reference/unit/<module>/<operator>/
├─ manifest.json
├─ input/
└─ expected/
```

- `manifest.json`：定义 accuracy 用例、输入形状、算法参数、误差阈值，以及输入文件和期望输出文件的映射关系。
- `input/`：静态输入数据，通常为 CSV 文件，例如信号、窗口参数、滤波器输入或雷达算子输入。
- `expected/`：期望输出结果，通常也是 CSV 文件，用于和 CPU/GPU 实际结果进行对照。

### `data/generated/`

`generated/` 用来存放运行期间生成或更新的数据，不是人工维护的固定基准仓。它当前主要分成两类：

```text
data/generated/
├─ unit/<module>/<operator>/...
└─ demo/<task>/...
```

- `data/generated/unit/<module>/<operator>/manifest.json`
  主要由 `scripts/data/generate_*.py` 维护，用于描述运行时生成用例或性能用例，例如生成器类型、长度、频率、随机参数和容差。
- `data/generated/demo/task1_radar/`、`data/generated/demo/task2_features/`
  在执行任务 demo 后生成，通常包含：
  - `input/`：本次任务运行实际使用的输入场景、模板、真值等
  - `output_samples/`：CPU/GPU 输出样本，供 Python 可视化脚本二次读取

`generated/` 不应替代 `reference/` 中的固定对照数据。

### `data/reports/`

`reports/` 用来保存所有运行结果的汇总文件。

典型落盘路径包括：

- `data/reports/demo/task1_radar/`
- `data/reports/demo/task2_features/`
- `data/reports/unit/<module>/<operator>/`

常见文件类型包括：

- `latest_summary.md`：本次运行的文字摘要
- `latest_metrics.json`：关键数值指标，任务级 demo 与单算子 benchmark 均包含 `mixed_error`
- `latest_stage_timings.csv`：分阶段耗时
- `figures/`：由 `visualize_task1.py`、`visualize_task2.py` 生成的图表

其中 `latest_*` 文件始终代表最近一次运行结果，便于快速查看当前状态；如果需要长期归档，建议另行复制保存。

### 清理策略

清理运行产物

```bash
./scripts/clean_data.sh
```

## 作者信息

- `CICC1001212非诚勿扰`
