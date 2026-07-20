# 构建与运行

## 1. 环境边界

GPU 构建和执行必须在本队中科芯 ZQ500 容器 `gpu_04` 中完成。服务器宿主机只
负责仓库同步、结果取回和静态检查；宿主机没有 `dlcc` 与 ZQ500 运行库时，不能
替代容器验证。

容器内要求：

- CMake 3.18 或更高版本、C++17、Python 3；
- `/zq500/sdk/env.sh`、`dlcc` 和 ZQ500 runtime/FFT/BLAS/solver 库；
- 仓库内固定 SHA256 的 FFTW 3.3.10 离线源包。

最终构建不依赖临时联网。`scripts/build.sh` 会检查 SDK，并在缺失 FFTW 时从
`third_party/fftw/dist/` 的固定源包安装到 `third_party/fftw/install/`。

竞赛环境链路为：

```text
本地电脑/VPN -> SSH 登录服务器宿主机 -> gpu_04 容器 -> ZQ500 GPU
```

容器内通常没有宿主机 Docker socket，因此 `docker ps`、`docker exec` 和
`docker cp` 都必须在服务器宿主机执行。手册未声明 `/home/usr_04` 会挂载进容器；
容器看不到宿主机路径是正常现象。

## 2. 进入与退出容器

在服务器宿主机执行以下可直接复制的命令：

```bash
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
```

看到容器的 `root@supervisor-X7850H0` 提示符后，最终版命令可以从任意容器目录直接
执行。`/CETC/scripts/` 下的入口自行定位仓库并初始化 SDK：

```bash
/CETC/scripts/validate.sh --build-dir build-zx
```

需要确认设备时运行 `dlsmi`。退出当前容器 shell：

```bash
exit
```

`exit` 不会停止容器。只有明确需要时，回到宿主机再执行：

```bash
sudo docker stop gpu_04
sudo docker restart gpu_04
```

不要把 `exit` 后的宿主机命令与容器命令一次性跨 shell 粘贴；先等待宿主机提示符
重新出现。

## 3. 同步最终仓库

同步脚本只能在服务器宿主机的正式仓库中运行：

```bash
cd /home/usr_04/CETC
scripts/sync_to_container.sh --dry-run
scripts/sync_to_container.sh --container gpu_04
```

脚本只复制根 `DELIVERY_FILES.txt` 中已审核、排序且无重复的普通文件，并校验
staging 与回读 SHA256。当前账户不能执行非交互 `docker exec`，所以第一次运行只
生成唯一的 `/CETC.incoming.<timestamp>.<pid>.<random>` 路径并打印交互建目录指令。
按提示使用 `sudo docker exec -it gpu_04 bash` 建好目录后，再用脚本打印的
`--destination ... --destination-ready` 命令调用获准的 `docker cp` 完成传输。
脚本不会复制 `.git`、IDE/PPT/复赛资料、build/cache、日志、图件或运行样本，也不会
覆盖 `/CETC`。

进入容器后，可在任意目录使用脚本实际打印的 incoming 路径验证：

```bash
sudo docker exec -it gpu_04 bash
/CETC.incoming.20260717220000.12345.6789/scripts/validate.sh \
  --build-dir build-zx
```

上面的时间戳只是格式示例，不能原样照抄。验证与结果取回完成后，确需切换正式
`/CETC` 时可在容器内做可回退的目录改名：

```bash
incoming=/CETC.incoming.20260717220000.12345.6789
previous=/CETC.previous.20260717_220000
if [[ ! -d "${incoming}" || ! -d /CETC || -e "${previous}" ]]; then
  echo "invalid activation paths" >&2
  exit 1
fi
cd /
mv /CETC "${previous}"
if ! mv "${incoming}" /CETC; then
  mv "${previous}" /CETC
  echo "activation failed; previous /CETC restored" >&2
  exit 1
fi
```

确认新 `/CETC` 完整通过后再单独处置旧目录。不要把 incoming 内容覆盖复制到旧
`/CETC`，否则已经从主仓库清理的过程文件仍会残留。

## 4. 构建

以下命令可在 ZQ500 容器的任意目录执行。相对 `build-zx` 始终表示
`/CETC/build-zx`。

```bash
/CETC/scripts/build.sh --build-dir build-zx
```

构建入口固定 `CUSIGNAL_PLATFORM=ZHONGKEXIN`，使用 `dlcc`、C++17 和
`-x cuda --cuda-gpu-arch=dlgput64`。只构建指定目标时可重复传入 `--target`：

```bash
/CETC/scripts/build.sh --build-dir build-zx --target cusignal_zx_gpu
/CETC/scripts/build.sh --build-dir build-zx \
  --target task1_radar_demo --target task2_features_demo
```

完整参数使用 `/CETC/scripts/build.sh --help` 查看。

## 5. 最终验证与演示

最终统一入口：

```bash
/CETC/scripts/validate.sh --build-dir build-zx
```

该入口从干净的运行期目录开始，执行构建、静态契约审计、81 个算子 full case、
Task1/Task2 的 L1-L6 和最终场景。全部通过后才原子发布
`data/reports/`；输出只有 JSON、Markdown 和 CSV，不作图、不选择性能候选。
复用已验证构建可加 `--no-build`。

三份竞赛 XLSX 是仓库外兼容夹具。需要 fail-closed 平台强门时，先在宿主机将
它们复制到容器已有的 `/tmp/`，再在容器中指定目录：

```bash
sudo docker cp \
  '/home/usr_04/CETC/复赛说明文件/CUDA 11.7 runtime API.xlsx' \
  gpu_04:/tmp/
sudo docker cp \
  '/home/usr_04/CETC/复赛说明文件/CUDA 11.7 driver api.xlsx' \
  gpu_04:/tmp/
sudo docker cp \
  '/home/usr_04/CETC/复赛说明文件/科学计算库实现列表.xlsx' \
  gpu_04:/tmp/
```

```bash
/CETC/scripts/validate.sh --build-dir build-zx --fixtures /tmp
```

分项检查和演示：

```bash
/CETC/scripts/test_operators.sh --list
/CETC/scripts/test_operators.sh --build-dir build-zx --module spectral
/CETC/scripts/test_operators.sh --build-dir build-zx \
  --module radartools --operator ambgfun
/CETC/scripts/demo.sh --build-dir build-zx --no-build --repeat 5
```

运行过程中会写入 `data/.reports_staging/unit/`、`data/.reports_staging/demo/` 和
`data/.reports_staging/runtime/`，随后由 finalizer 只抽取必要的当前数据发布到
`data/reports/`。任何门禁失败都会停止，且不会发布或替换既有报告。V5.5、
V6、V7 已关闭。

需要保留完整控制台日志时，在容器 `/tmp` 写入并保留真实退出码：

```bash
set -o pipefail
/CETC/scripts/validate.sh --build-dir build-zx \
  2>&1 | tee /tmp/cetc_delivery_validation_latest.log
```

## 6. 文件复制与结果取回

宿主机向容器复制单个文件：

```bash
sudo docker cp \
  /home/usr_04/CETC/README.md \
  gpu_04:/tmp/
```

容器向宿主机复制单个文件时，先创建仓库外目标目录：

```bash
mkdir -p /home/usr_04/CETC_garbage/manual_pull
sudo docker cp \
  gpu_04:/tmp/README.md \
  /home/usr_04/CETC_garbage/manual_pull/
```

最终验证结果使用宿主机脚本统一取回。若项目仍在 incoming 目录：

```bash
cd /home/usr_04/CETC
scripts/pull_results.sh \
  --container gpu_04 \
  --container-root /CETC.incoming.20260717220000.12345.6789 \
  --promote-reports
```

若已切换为 `/CETC`，可省略 `--container-root`。脚本默认把容器中的
`data/reports/` 复制到仓库外唯一的
`/home/usr_04/CETC_garbage/container_pull_<timestamp>/`，并生成传输清单。
`--promote-reports` 会额外验证 `FILES.sha256` 和摘要门禁，然后原子更新主仓库的
`data/reports/`；此前的主仓库 reports 会移动到 `CETC_garbage/`。不带该选项时
主仓库不会被修改。需要诊断原始运行期数据时，可显式取回容器内
`data/.reports_staging/`；它不属于发布报告。

本地电脑与服务器之间仍使用 `scp`，且目标只能是本队个人目录。服务器地址以赛方
当前通知为准。

## 7. 报告与清理

当前代码完整验证成功后，仓库内报告布局为：

```text
data/reports/units/<module>/<operator>/{metrics.json,cases.csv,summary.md}
data/reports/units/benchmarks/summary.json
data/reports/units/benchmarks/summary.csv
data/reports/demo/<task>/final/...
data/reports/demo/<task>/scales/{L1,L2,L3,L4,L5,L6}/...
data/reports/validation/...
data/reports/summary.md
data/reports/summary.json
data/reports/FILES.sha256
```

运行结束后可预览并清理可再生成的数据：

```bash
scripts/clean.sh --dry-run
scripts/clean.sh
```

`scripts/clean.sh` 只处理 generated sample 与 `data/.reports_staging/`，明确保留
`data/reference/`、generated manifest 和已发布的 `data/reports/`。构建目录、
日志、trace 和其他中间文件也不进入主仓库；需要保留时统一取回到
`CETC_garbage/`。
