# V2.3 `windows` 模块实现计划

## Summary

- 本轮只实现 `windows` 模块，先把 `filter_design` / `filtering` 的前置基础做实；交付标准继续对齐 `V2.2 waveforms`：真实 CPU/ZQ500 GPU 实现、unit runner、accuracy/perf、`data/reference` / `data/generated` / `data/reports`、一键脚本接入。
- 迁移性策略现在明确为：
  - `FFTW` 放到 `third_party`，因为它不是 CUDA 环境的天然组成部分。
  - `cuFFT` 不放到 `third_party`，直接使用系统 CUDA Toolkit 提供的库和头文件即可。
- 本地已确认在 `2026-04-04` 的当前环境中，CUDA `11.7` 和 `12.4` 都自带 `cuFFT` 静态/动态库，因此本轮不复制 NVIDIA 库，避免额外维护和潜在分发负担。

## Key Changes

- 第三方依赖与构建：
  - 新增 `third_party/fftw/` 目录约定：
    - `dist/`
    - `src/`
    - `build/`
    - `install/`
    - `README.md`
  - 新增 `scripts/build/install_fftw.sh`：
    - 下载 FFTW `3.3.10`
    - 静态安装到 `third_party/fftw/install`
    - 固定参数：
      - `--disable-shared`
      - `--enable-static`
      - `--with-pic`
      - 不开 MPI
      - 不开 threads
      - 只构建双精度 `libfftw3.a`
  - CMake 依赖策略固定为：
    - `FFTW` 只从 `third_party/fftw/install` 查找
    - `cuFFT` 通过 `find_package(CUDAToolkit REQUIRED)` 获取
    - ZQ500 GPU 侧优先链接 `CUDA::cufft_static`；若该 target 在目标环境不可用，则配置阶段失败，不做 `third_party` fallback
  - 不引入 `third_party/cuda/`，也不复制 `libcufft*`、`libculibos`、`libcudart_static`

- 公开接口与类型：
  - 保持 [windows.hpp](/home/ziheng/CETC/include/cusignal/windows/windows.hpp) 中全部 CPU/CUDA 窗函数签名不变。
  - 扩展 [types.hpp](/home/ziheng/CETC/include/cusignal/core/types.hpp) 的 `core::WindowSpec`，新增：
    - `NamedDoublePairParameter`
    - `NamedTaylorParameter`
  - `get_window` 本轮完整支持：
    - 字符串名与别名
    - `double` 形式 Kaiser beta
    - 单参数命名窗
    - 双参数命名窗
    - Taylor 参数窗
    - 显式数组窗

- `windows` 数值实现：
  - 新增 `src/common/windows_detail.hpp`
  - CPU/CUDA 全部替换占位实现
  - 直接公式实现：
    - `boxcar`、`triang`、`bartlett`、`barthann`
    - `blackman`、`blackmanharris`、`bohman`
    - `cosine`、`flattop`
    - `hamming`、`hann`、`nuttall`
    - `parzen`
    - `gaussian`、`general_gaussian`
    - `general_hamming`、`general_cosine`
    - `kaiser`、`tukey`
    - `exponential` 两个重载
    - `taylor`
  - FFT 路径实现：
    - CPU `chebwin` 用 FFTW
    - CUDA `chebwin` 用 `cuFFT`
  - ZQ500 GPU 侧除 `chebwin` 外，优先用 pointwise kernel + host wrapper；必要时复用 device buffer，避免 perf 被重复分配污染

- 测试与报告链路：
  - 新增 `tests/unit/windows/`
  - 每个公开 API 一个 runner，`get_window` 单独一个 runner
  - 新增：
    - `data/reference/unit/windows/<op>/`
    - `data/generated/unit/windows/<op>/`
    - `data/reports/unit/windows/`
  - `accuracy` case 以参数规格为输入，黄金输出为 `expected/<case>__window.csv`
  - `perf` case 记录 `size/sym/params`，继续输出：
    - `cpu_perf`
    - `gpu_e2e_perf`
    - `gpu_kernel_perf`
    - `gpu_e2e_speedup`
    - `gpu_kernel_speedup`
  - 报告格式继续复用 `waveforms`：
    - `latest_summary.md`
    - `latest_metrics.json`
    - `latest_cases.csv`

- 脚本接入：
  - `tests/unit/CMakeLists.txt` 新增 `add_subdirectory(windows)`
  - `scripts/test/run_all_tests.sh` 扩展到 `--module windows|waveforms|all`
  - `scripts/clean_data.sh` 扩展到清理 `windows` 生成数据
  - 新增或更新忽略规则，排除 `third_party/fftw/dist/src/build/install`

## Test Plan

- 依赖安装：
  - 运行 `scripts/build/install_fftw.sh`
  - 确认：
    - `third_party/fftw/install/include/fftw3.h`
    - `third_party/fftw/install/lib/libfftw3.a`
- 构建：
  - `cmake -S . -B build`
  - `cmake --build build --target cusignal_cpu cusignal_zx_gpu --parallel`
  - `cmake --build build --target` 全部 `windows_*` runner
- accuracy：
  - 每个窗覆盖 `sym=true/false`、奇偶长度、长度 `0/1`、非法参数
  - `get_window` 覆盖字符串、别名、Kaiser `double`、多参数规格、显式数组
  - `chebwin`、`taylor`、`general_gaussian`、显式中心 `exponential` 单独高精度比对
- perf：
  - 每个 runner 至少 1 个大尺寸 perf case
  - 核对终端摘要、JSON、CSV 的 perf 字段一致
- 一键链路：
  - `./scripts/test/run_all_tests.sh --module windows`
  - `./scripts/test/run_all_tests.sh --module windows --emit-report --case-set full`
- 回归：
  - `waveforms` runner、脚本参数、报告 schema 保持不变

## Assumptions

- 本轮只实现 `windows` 模块，不同时推进 `filter_design` / `filtering`。
- `FFTW` 进入 `third_party`，`cuFFT` 不进入 `third_party`。
- 目标迁移场景定义为“安装了 CUDA Toolkit 的构建环境”，而不是“完全脱离系统 CUDA 的离线构建环境”。
- `cuFFT` 采用系统 Toolkit 提供版本，不额外冻结副本；若未来需要完全离线或工具链封版，再单独规划 `third_party/cuda`。
