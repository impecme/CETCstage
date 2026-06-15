# CETC CUDA 信号处理加速库

本项目面向第十届集创赛“中科芯”企业命题，围绕 GPU 芯片上的信号处理加速库及算法开发展开。仓库以 CUDA C++ 为主线，覆盖赛题任务 1“雷达目标检测与多普勒分析”和任务 2“多域特征提取定位”，同时保留 CPU 对照实现、任务级 demo、单算子测试以及 Python 可视化链路，便于验证精度、性能和工程可交付性。

## 项目简介

- 面向比赛任务构建可运行、可验证的 CUDA 信号处理工程。
- 将公共算子沉淀为按模块组织的信号处理库接口，支持后续扩展和复用。

仓库目前具备以下能力：

- `src/cpu/` 与 `src/cuda/` 双实现路径，可做 CPU/GPU 结果对照。
- `demo/task1_radar/` 与 `demo/task2_features/` 提供任务级演示入口。
- `tests/smoke/` 提供最小编译与链接验证，`tests/unit/` 提供单算子测试链路。
- `demo/*/visualize_*.py` 可将任务输出转换为图表和报告文件。
- `scripts/test/benchmark_all_ops_scales.py` 可执行全量多规模性能采集，并在 CSV 中记录 CPU/GPU median 耗时与加速比。
- `scripts/test/plot_all_ops_benchmark.py` 可生成论文风格图件，默认输出 PNG，可通过 `--figure-set all --formats png,pdf,svg` 同时导出耗时、加速比与误差图。

## 项目特色

- CUDA C++ 主线实现，核心算子提供 CPU 与 CUDA 两套可对照路径。
- 当前代码线采用统一单精度口径，实数数据为 `float32`，复数数据为 `complex64` 语义。
- 覆盖 waveforms、filtering、spectral、radartools、estimation、windows、wavelets、correlate 等模块。
- 支持 GPU 相对 CPU 的误差、耗时、e2e speedup、kernel speedup 统一报告。
- 支持 `default` 与 `large-gpu` 两套规模 profile，便于区分小规模开销和大规模吞吐。

## 项目环境

工程环境如下：

- 当前验证 GPU：`2 x NVIDIA A100-SXM4-40GB`
- CUDA：`11.7`
- 构建系统：`CMake >= 3.18`，当前验证版本为 `3.22.1`
- 语言标准：`C++17` / `CUDA17`
- 本地依赖：`FFTW` 通过 `./scripts/build/install_fftw.sh` 安装到 `third_party/fftw/install`

绘图与分析辅助环境如下：

- `python3`
- `numpy`
- `matplotlib`
- `scipy`：部分数据生成脚本会使用

默认 CUDA 架构为 `80`，适配 `sm80` GPU；当前验证设备为 A100-SXM4-40GB。可在构建前通过环境变量覆盖，例如 `CUDA_ARCH=86`。

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

服务器上查看和进入本队 docker：

```bash
sudo docker ps -a
sudo docker ps
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
```

退出容器：

```bash
exit
```

每次进入容器后，先初始化中科芯开发环境：

```bash
source /zq500/sdk/env.sh
```

若当前 shell 因 SDK 脚本读取 `$1` 出现 `line 4: $1: unbound variable`，使用：

```bash
set +u
source /zq500/sdk/env.sh ""
set -u
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

其中 `CUDA 11.7 runtime API.xlsx`、`CUDA 11.7 driver api.xlsx` 和 `科学计算库实现列表.xlsx` 说明了中科芯平台的 CUDA runtime、driver API 和科学计算库支持范围。迁移摘要见 `docs/design/zhongkexin_rematch_notes.md`。当前迁移必须特别注意：

- 不要假设中科芯平台完整支持 CUDA 11.7 全量 runtime/driver API。
- cuFFT 点数仅支持 2 的整数次幂，不足需要补 0。
- cuSOLVER LU 分解的 pivot 参数不能传入 `nullptr`。
- event timing 和性能 gate 需要先在中科芯 docker 内实测稳定性。

SDK 示例通常使用 CMake 构建：

```bash
mkdir build
cd build
cmake ..
make
./可执行测试用例名
```

文件传输：

```bash
# 本地 -> 服务器个人目录
scp -r C:\Users\27412\Desktop\project usr_04@10.110.12.10:/home/usr_04

# 服务器宿主机 -> 容器
sudo docker cp /home/usr_04/CETC gpu_04:/root/CETC

# 容器 -> 服务器宿主机
sudo docker cp gpu_04:/root/CETC /home/usr_04/CETC_from_container
```

本项目迁移到中科芯平台时，建议在 docker 内执行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

也可以使用 V4.1 第一阶段统一验收入口：

```bash
scripts/platform/run_zhongkexin_stage1.sh
```

该脚本会自动初始化 SDK、运行平台 probe、配置 `build-zx`、构建 `cusignal_cpu` / `cusignal_cuda` / 两个任务 demo，并执行 Task1/Task2 默认 correctness 验收。

如果当前是在服务器宿主机上操作，而不是已经进入 docker，使用以下完整同步流程。该流程用于把宿主机项目完全替换到容器 `/CETC`，包括删除容器中已经不存在于宿主机项目里的旧文件。

第一步在宿主机执行：

```bash
cd /home/usr_04/CETC
./copy_to_container.sh gpu_04
```

`copy_to_container.sh` 会把当前项目复制到容器中的全新临时目录，并在终端打印一条容器端替换命令，例如：

```bash
/CETC.incoming.20260615124530/replace_container_project.sh /CETC
```

第二步进入容器，执行脚本打印的 `replace_container_project.sh` 命令。该命令会删除旧 `/CETC` 并将 incoming 目录替换为新的 `/CETC`：

```bash
/CETC.incoming.20260615124530/replace_container_project.sh /CETC
```

第三步在容器内执行第一阶段验证：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

如果需要把完整日志取回宿主机供 Codex 分析，容器内运行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh 2>&1 | tee stage1.log
```

运行结束后回到宿主机终端执行：

```bash
cd /home/usr_04/CETC
sudo docker cp gpu_04:/CETC/stage1.log ./stage1.log
```

查看日志尾部或关键错误：

```bash
tail -n 200 stage1.log
grep -nEi "error|failed|fatal|not found|undefined|file format" stage1.log
```

此统一脚本会用兼容方式初始化 SDK，不需要在执行前手动 `source /zq500/sdk/env.sh`。如需覆盖默认值，使用 `BUILD_DIR`、`CUDA_ARCH`、`REPEAT` 环境变量；当前中科芯路径默认使用 `CUDA_ARCH=OFF`，不要手动设置 `CUDA_ARCH=80`，否则 CMake 可能生成 NVIDIA 专用的 `sm_80` 参数。

## 精度约定

当前主干采用统一单精度实现，面向当前 A100-SXM4-40GB 验证环境的吞吐特性做算子验证与性能对比。

- 公共接口保留 `dtype` 参数以降低接口破坏面，但默认值和校验口径已收敛到 `float32`。
- CPU 与 CUDA 对照均按单精度实现；单算子 metrics 保留 `max_abs_error`、`max_rel_error`、`rmse`，全量 benchmark 主表使用 `mixed_error` 展示近零保护后的主误差。
- `waveforms`、`filtering/detrend`、`spectral/vectorstrength`、`correlate`、`windows`、`estimation` 等路径中的中间量、workspace、scratch buffer、测试统计与数据生成脚本已同步为单精度口径。
- `data/reference` 与 `data/generated` 的活动 manifest 已同步到 `float32` / `complex64` 描述；窗口参数中的命名实数参数统一为 `named_float` 语义。

大规模结果中少数算子的原始相对误差可能较大，通常来自参考值接近零时 ratio 被放大；全量报告默认使用 `mixed_error`，在近零区域用绝对误差判断。

## 快速开始

```bash
./scripts/build/build_v1.sh
```

显式指定 CUDA 架构

```bash
CUDA_ARCH=80 ./scripts/build/build_v1.sh
```

完成构建后，可以直接运行两个任务级 demo：

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
scripts/test/run_task_demos.sh --no-build --repeat 5
```

6 档任务规模扫测：

```bash
scripts/test/run_task_demos.sh --no-build --scale-sweep --repeat 3
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
- 资源与稳定性：repeat 内检查业务一致性、GPU total 相对中位数抖动、CUDA free memory 漂移和当前 RSS 增长；报告记录 RSS peak、CUDA free/total 与 device name。
- 异常输入：`--invalid-input-checks` 会跑固定非法配置矩阵，要求返回明确 `std::invalid_argument` 和字段名。
- `--leak-check` 为可选深度检查项，会在可用时运行 `compute-sanitizer --tool memcheck`；深检时跳过性能 gate，避免 sanitizer 放大耗时误触发失败。未执行 `--leak-check` 时，提交文档中应将 compute-sanitizer / ASAN / LSAN 标记为预留检查项。

汇总报告会写到 `data/reports/demo/latest_task_demo_report.md` 和 `data/reports/demo/latest_task_demo_report.json`。
规模扫测会额外写出 `data/reports/demo/latest_task_demo_scale_benchmark.csv`、`latest_task_demo_scale_report.json` 和 `latest_task_demo_scale_report.md`，并将每档产物归档到 `data/reports/demo/<task>/scales/L<N>/`。扫测结束后 latest 与可视化默认恢复为 L3 兼容场景。
多卡机器上如需避开被占用的 GPU，可在命令前临时指定 `CUDA_VISIBLE_DEVICES=<id>`；本轮最终复测使用空闲的 A100 GPU。

## 编译

仅构建核心库：

```bash
cmake --build build --target cusignal_cpu cusignal_cuda --parallel
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
    const auto duty = cusignal::cuda_backend::windows::hann(static_cast<int>(t.size()));
    const auto saw = cusignal::cuda_backend::waveforms::sawtooth(t, duty);
    const auto square = cusignal::cuda_backend::waveforms::square(saw, duty);

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

全量 53 个算子 × 6 个规模点复测：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops
```

大规模 GPU profile：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

论文风格作图：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
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
- `figures/operator_figures/<module>__<operator>.png`

默认只保留全量 benchmark CSV。CSV 追加包含 `cpu_median_ms`、`gpu_e2e_median_ms`、`gpu_kernel_median_ms`、`gpu_e2e_min_ms`、`gpu_e2e_max_ms`，用于直接绘制 CPU/GPU 耗时与加速比图。`figure_1` 到 `figure_5` 是全局总览图，行/点代表算子、列代表 L1-L6 或最大规模；每个算子的独立性能图在 `figures/operator_figures/` 下，上半部分是 CPU/GPU e2e median 耗时，下半部分是 e2e/kernel speedup。需要 Markdown 简表时，在 benchmark 命令中增加 `--report-mode concise`；需要时间戳归档、分模块 CSV 或候选细表时增加 `--report-mode full`；需要图件时再单独运行 plot 脚本。

测试脚本、规模策略、性能图生成方式和任务级验收口径已在本文档中统一说明。提交技术文档如需引用工程说明，统一引用本文件。

## 提交文档证据索引

本文档作为工程说明的统一入口，提交技术文档中的附录、图件、报告和验证数据均可从以下路径追溯。

| 证据类型 | 工程路径 | 用途 |
|---|---|---|
| 任务级汇总报告 | `data/reports/demo/latest_task_demo_report.md` | Task1/Task2 默认任务验证汇总 |
| 任务级规模报告 | `data/reports/demo/latest_task_demo_scale_report.md` | Task1/Task2 L1-L6 六档规模性能 |
| 任务级规模 CSV | `data/reports/demo/latest_task_demo_scale_benchmark.csv` | 六档 CPU/GPU 耗时、加速比与误差 |
| Task1 metrics | `data/reports/demo/task1_radar/latest_metrics.json` | Task1 检测结果、误差、资源与稳定性 |
| Task1 阶段耗时 | `data/reports/demo/task1_radar/latest_stage_timings.csv` | Task1 分阶段 CPU/GPU 耗时 |
| Task2 metrics | `data/reports/demo/task2_features/latest_metrics.json` | Task2 轨迹、误差、资源与稳定性 |
| Task2 阶段耗时 | `data/reports/demo/task2_features/latest_stage_timings.csv` | Task2 分阶段 CPU/GPU 耗时 |
| 53 算子 benchmark | `data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv` | 53 个核心算子 L1-L6 性能与精度 |
| 全量算子图件 | `data/reports/unit/benchmarks/all_ops_large/figures/` | benchmark 总览图与算子图 |
| 单元测试入口 | `tests/unit/` | 81 个已迁移算子的测试覆盖 |
| 公开接口 | `include/cusignal/` | 库函数头文件与公开 API |
| CUDA 实现 | `src/cuda/` | GPU 加速实现源码 |
| CPU 基线 | `src/cpu/` | CPU 参考实现源码 |

## 项目结构

```text
CETC/
├─ data/          生成数据、参考数据和报告输出
├─ deliverables/  比赛交付物整理目录
├─ demo/          任务级演示入口与可视化脚本
├─ docs/          设计、验证、性能与提交文档
├─ include/       公共头文件与模块接口
├─ scripts/       构建、测试、数据和打包脚本
├─ src/           CPU、CUDA 与公共实现
├─ tests/         smoke 验证与单算子测试
└─ third_party/   FFTW 与辅助 Python 依赖
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
