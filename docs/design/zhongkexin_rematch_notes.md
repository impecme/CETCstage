# 中科芯复赛说明文件解读

## 文档来源

复赛说明文件位于 `复赛说明文件/`：

- `参赛者服务器使用说明.pdf`
- `CUDA 11.7 runtime API.xlsx`
- `CUDA 11.7 driver api.xlsx`
- `科学计算库实现列表.xlsx`

本文档用于把复赛说明中与 CETC 迁移相关的约束转成工程执行规则。原始表格仍是最终依据；本文档负责给迁移计划、AGENT 和状态文档提供可读摘要。

## 服务器和 Docker 约束

- 实际开发链路为：`Windows VPN -> SSH 登录服务器 -> 进入本队 docker -> 初始化 SDK 环境 -> 构建和验证`。
- 当前项目记录的用户 ID 为 `usr_04`，UID 为 `1006`，项目路径为 `/home/usr_04/CETC`。
- VPN 客户端仅支持 Windows，且每天 `1:00-8:00` 关闭。
- 宿主机只作为文件中转和 docker 入口，不应在宿主机直接构建或运行本项目。
- 每次进入 docker 后必须执行 `source /zq500/sdk/env.sh`。
- 使用 `dlsmi` 确认 GPU 绑定和设备状态。
- SDK 示例位于 `/zq500/sdk/samples/`。
- 兼容头文件可参考 `/zq500/cuda11/include`。

## CUDA Runtime API 约束

`CUDA 11.7 runtime API.xlsx` 显示中科芯 runtime API 是部分覆盖，不应假设完整 CUDA 11.7 runtime 全量可用。

对当前 CETC 迁移直接相关的结论：

- 当前项目主路径依赖的 `cudaMalloc`、`cudaFree`、`cudaMemcpy`、`cudaMemset`、`cudaGetDevice`、`cudaGetDeviceProperties`、`cudaMemGetInfo`、`cudaDeviceSynchronize`、kernel launch error check、基础 event API 需要作为 V4.1 probe 的强制探测项。
- 不应在迁移中引入 stream ordered memory allocator、memory pool、external memory、IPC event、NvSci、graph capture、stream attribute 等高级 runtime API，除非复赛说明明确支持并且 probe 通过。
- event timing 初期只能作为记录项；必须通过中科芯平台实测后再恢复为性能 gate。
- 资源采样应优先使用当前已有的 `cudaMemGetInfo` 和 `cudaGetDeviceProperties` 路径，避免引入未确认支持的 driver/runtime 查询。

## CUDA Driver API 约束

`CUDA 11.7 driver api.xlsx` 显示 driver API 也是部分覆盖。

对当前 CETC 迁移直接相关的结论：

- CETC 第一阶段和第二阶段不应主动切换到 driver API 实现 runtime 功能。
- 不应依赖 virtual memory management、stream ordered allocator、graphics interoperability、external resource、IPC event、NvSci、部分 array/texture/surface 查询等 driver 能力。
- 如果后续必须使用 driver API，需要先在 `scripts/platform/probe_zhongkexin.sh` 中新增最小探测，并把差异记录到 `docs/design/zhongkexin_migration_change_log.md`。

## 科学计算库约束

`科学计算库实现列表.xlsx` 对 cuBLAS、cuFFT、cuDNN、cuSOLVER、cuSPARSE、cuRAND 的支持范围做了说明。当前 CETC 主路径直接相关的是 cuFFT、cuBLAS、cuSOLVER。

### cuFFT

- `cufftPlan1d`、`cufftPlan2d`、`cufftPlanMany`、`cufftCreate`、`cufftMakePlan*`、`cufftGetSize*`、`cufftSetWorkArea`、`cufftSetAutoAllocation`、`cufftExec*` 等在表格中列为实现范围。
- 关键限制：FFT 点数仅支持 2 的整数次幂，不足需要补 0。
- 支持单精度实数/复数执行路径：`cufftExecC2C`、`cufftExecR2C`、`cufftExecC2R`、`cufftExecR2R`。
- 不支持双精度相关执行路径：`cufftExecZ2Z`、`cufftExecD2Z`、`cufftExecZ2D`。
- 迁移规则：中科芯路径下所有 FFT-heavy 算子必须确认 FFT 长度是 2 的整数次幂；非 2 的整数次幂输入必须显式 pad 到 next power-of-two，且记录对输出裁剪、误差和性能的影响。

### cuBLAS

- 表格列出了 helper function 和 BLAS 常用接口，当前 CETC 已知主路径使用 `cublasCreate`、`cublasDestroy`、`cublasCgemm`。
- 迁移规则：V4.1 probe 继续保留 `cublasCreate` 和 `cublasCgemm` 最小验证；后续如引入更多 BLAS 接口，必须先对照复赛说明并新增 probe 或单元测试。

### cuSOLVER

- 表格明确支持单精度实数和单精度复数路径。
- `cusolverDnSgetrf`、`cusolverDnCgetrf` 的 `devIpiv` 参数不支持 `nullptr` 输入。
- `cusolverDnSgesvd` 和 `cusolverDnCgesvd` 的 `VT` 输出 buffer 内容无效，不应依赖该输出。
- 迁移规则：所有 LU 分解路径必须分配 pivot buffer，不得传入 `nullptr`；如后续使用 SVD，不得依赖 `VT` 输出，必须设计替代验证路径。

### cuDNN、cuSPARSE、cuRAND

- 当前 CETC 主迁移路径不依赖 cuDNN、cuSPARSE、cuRAND。
- 如后续引入：
  - cuSPARSE 说明中多处限制为只支持 `float`，且稀疏矩阵描述符不支持整型矩阵。
  - cuRAND 不支持 double，生成器和分布有范围限制，部分生成接口有规模限制。
  - cuDNN Ex 版本部分行为与非 Ex 版本一致，不应假设扩展功能完整。

## 对当前 Task1/Task2 的影响

- Task1 L1-L6 的 pulse FFT 和 doppler FFT 当前均为 2 的整数次幂；L6 primary samples 为 `1536`，pulse FFT 为 `2048`，符合补 0 到 2 的整数次幂的约束。
- Task2 L1-L6 的 spectrogram `nfft` 当前为 `128`、`256`、`512`，均为 2 的整数次幂。
- Task2 filter tap 长度不是 FFT 点数，不受 cuFFT 2 的整数次幂限制；但如果后续把某些 FIR 路径改为 FFT convolution，必须重新检查 padding。
- 当前 probe 中 cuSOLVER 复数 LU 已分配 pivot buffer，符合 `devIpiv` 不能为 `nullptr` 的约束。

## 文档和台账要求

- 复赛说明中的平台限制属于迁移依据，发现与代码现状不一致时必须记录到 `docs/design/zhongkexin_migration_change_log.md`。
- 若后续代码修改是为了满足复赛说明约束，必须在台账中引用对应说明文件和约束。
- 若某条复赛约束暂时不影响当前路径，也应在 V4.2 或 V4.3 的依赖矩阵中标记为“不涉及”或“待覆盖”。
