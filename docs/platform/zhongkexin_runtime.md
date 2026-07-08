# 中科芯 ZQ500 平台与容器操作

本文集中保存 `AGENT.md` 中原本过长的服务器、docker、SDK、同步和阶段验证命令。后续代理需要平台操作细节时先读本文。

## 参赛者服务器使用要点

中科芯参赛环境的实际开发链路是：

```text
Windows VPN -> SSH 登录服务器 -> 进入本队 docker -> 在 docker 内开发和调试
```

协作时注意：

- 当前项目记录的用户 ID 为 `usr_04`，UID 为 `1006`，当前主机名为 `supervisor-X7850H0`，项目路径为 `/home/usr_04/CETC`。
- VPN、服务器账号和 docker 均按参赛队分配；不要把账号密码写入仓库或文档。
- VPN 客户端当前仅支持 Windows，且每天 `1:00-8:00` 关闭。
- 服务器宿主机只做文件中转和 docker 入口；项目代码应放在个人用户目录 `/home/usr_04`。
- 严禁修改公共路径和其他参赛者用户目录。
- 构建、运行、调试 `CETC` 项目应在本队 docker 内完成。

常用容器命令：

```bash
sudo docker ps -a
sudo docker ps
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
exit
```

每次进入 docker 后先初始化 SDK 环境：

```bash
source /zq500/sdk/env.sh
```

若 SDK 脚本报 `line 4: $1: unbound variable`，说明当前 shell/脚本环境触发了 nounset 或 SDK 需要占位参数，改用：

```bash
set +u
source /zq500/sdk/env.sh ""
set -u
```

检查 GPU：

```bash
dlsmi
```

SDK 示例和头文件路径：

```bash
/zq500/sdk/samples/
/zq500/cuda11/include
```

复赛说明文件位于 `复赛说明文件/`，迁移摘要位于 `docs/migration/zhongkexin/platform_notes.md`。迁移时必须把这些说明作为平台约束来源：

- `CUDA 11.7 runtime API.xlsx`：runtime API 部分覆盖，不要引入未确认支持的 memory pool、stream ordered allocator、external memory、IPC event、NvSci、graph capture 等高级 API。
- `CUDA 11.7 driver api.xlsx`：driver API 部分覆盖，第一阶段和第二阶段不要主动切到 driver API 实现 runtime 功能。
- `科学计算库实现列表.xlsx`：cuFFT 仅支持 2 的整数次幂点数，不足需要补 0；cuSOLVER `getrf` 的 pivot 参数不能传入 `nullptr`；当前主路径优先关注 cuFFT、cuBLAS、cuSOLVER。
- 任何因复赛说明引发的不兼容、待修改、fallback 或测试阈值调整，都必须记录到 `docs/migration/zhongkexin/change_log.md`。

## 文件传输

本地到服务器个人目录：

```bash
scp -r C:\Users\27412\Desktop\project usr_04@10.110.12.10:/home/usr_04
```

服务器宿主机到容器：

```bash
sudo docker cp /home/usr_04/CETC gpu_04:/root/CETC
```

容器到服务器宿主机：

```bash
sudo docker cp gpu_04:/root/CETC /home/usr_04/CETC_from_container
```

## 宿主机同步入口

如果当前只在服务器宿主机上，而用户可以在终端输入 sudo 密码，则使用宿主机同步入口。该流程用于把宿主机项目完全替换到容器 `/CETC`，包括删除容器中已经不存在于宿主机项目里的旧文件：

```bash
cd /home/usr_04/CETC
./copy_to_container.sh gpu_04
```

第一步在宿主机执行 `copy_to_container.sh`。该脚本会把项目复制到容器中的全新 incoming 目录，并在终端打印容器端替换脚本命令，例如：

```bash
/CETC.incoming.20260615124530/replace_container_project.sh /CETC
```

第二步进入容器后，先执行脚本打印的 `replace_container_project.sh` 命令。该命令会删除旧 `/CETC` 并将 incoming 目录替换为新的 `/CETC`，因此宿主机已删除的文件也会从容器项目中消失。

当前服务器 sudoers 可能允许 `docker ps -a` / `docker cp`，但禁止 `docker inspect` 或 `docker exec`。因此宿主机脚本不承担容器内命令执行、构建验证或报告拷回职责。

## 依赖准备

中科芯容器内优先使用统一依赖准备脚本：

```bash
scripts/platform/prepare_zhongkexin_deps.sh --ensure-fftw
```

该脚本会检查 `python3`、`cmake >= 3.18`、`make`、`dlcc`、中科芯 SDK 头文件/库和 FFTW；缺少 FFTW 且启用 `--ensure-fftw` 时才要求 `tar`、`gcc`、`wget/curl`。

Python 可视化/数据生成依赖来自 `scripts/platform/zhongkexin_python_requirements.txt`；完整迁移验收必须安装并验证 `numpy/matplotlib/scipy`。

需要预下载 wheel 缓存时设置：

```bash
DOWNLOAD_PYTHON_WHEELS=1
```

需要在容器内用户态安装时设置：

```bash
INSTALL_PYTHON_DEPS=1
```

`scripts/platform/run_zhongkexin_stage1.sh` 默认会启用用户态 Python 依赖安装，并要求 demo 可视化依赖可用。

如果缺少 FFTW：

```bash
./scripts/build/install_fftw.sh
```

## 阶段验证入口

V4.1 第一阶段统一验收入口：

```bash
scripts/platform/run_zhongkexin_stage1.sh
```

该脚本必须在本队 docker 内执行；它会自动 `source /zq500/sdk/env.sh`、运行 `scripts/platform/probe_zhongkexin.sh`、配置 `build-zx`、构建 `cusignal_cpu` / `cusignal_zx_gpu` / `task1_radar_demo` / `task2_features_demo`，最后运行：

```bash
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3 --require-visualization-deps
```

V4.2 第二阶段统一验收入口：

```bash
scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2.log
```

该脚本必须在本队 docker 内执行；它会按 `docs/migration/zhongkexin/task_dependency_matrix.md` 批量运行 Task1/Task2 依赖算子 `accuracy`，写出 `data/reports/zhongkexin/stage2/latest_dependency_operator_report.*` 和逐算子日志。

当前调试默认只跑 Task1/Task2 `L3` 一个规模的 scale 报告链路，避免中科芯 GPU 调试耗时过长；单规模通过后用 `STAGE2_SCALES=1,2,3,4,5,6` 打开全规模 sweep。

取回日志后优先查看：

```bash
stage2.log
data/reports/zhongkexin/stage2/operators/*.log
```

## Stage4 全量 benchmark

如需把完整日志取回宿主机供 Codex 分析，容器内运行：

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

运行结束后回到宿主机终端执行：

```bash
cd /home/usr_04/CETC
sudo docker cp gpu_04:/CETC/stage4_full.log ./stage4_full.log
sudo docker cp gpu_04:/CETC/data/reports/zhongkexin/stage4 ./data/reports/zhongkexin/stage4_full_final
sudo docker cp gpu_04:/CETC/data/reports/unit/benchmarks/zhongkexin_stage4_full ./data/reports/unit/benchmarks/zhongkexin_stage4_full
```

常用日志查看命令：

```bash
tail -n 200 stage4_full.log
grep -nEi "error|failed|fatal|not found|undefined|file format" stage4_full.log
```

运行该统一脚本前不要再手动 source SDK；脚本内部已经用 `source /zq500/sdk/env.sh ""` 兼容当前容器环境。

如需覆盖默认值，使用 `BUILD_DIR`、`TASK_SCALES`、`RUN_TASK_SWEEP`、`BENCH_MODULES`、`BENCH_OPERATORS`、`BENCH_SCALE_LEVELS`、`BENCH_WARMUP`、`BENCH_REPEAT` 环境变量。

当前中科芯路径固定由 `dlcc --cuda-gpu-arch=dlgput64` 编译 ZQ500 GPU 源码，不再提供 NVIDIA 架构参数入口。
