# CETC ZQ500 信号处理算子库

这是面向中科芯 ZQ500 平台的 C++17 信号处理代码库。它包含 CPU reference 和 ZQ500
GPU 实现，覆盖 12 个模块、81 个公开算子，以及 Task1 雷达处理和 Task2 特征提取两个
可执行 demo。

## 代码结构

```text
CETC/
├── CMakeLists.txt          顶层构建入口；选择 ZQ500 平台并组织库、demo 和测试目标
├── DELIVERY_FILES.txt      容器同步与最终交付的审核文件清单
├── include/cusignal/       公开 API：聚合头、核心类型、各模块声明与 ZQ500 兼容层
├── src/
│   ├── common/             两后端共用的参数、shape、axis 和数值语义
│   ├── cpu/                CPU reference，实现正确性对照
│   └── zhongkexin/         ZQ500 GPU 后端、kernel、workspace 与平台库调用
├── demo/
│   ├── common/             Task 分步计时、误差与结构化报告的公共代码
│   ├── task1_radar/        雷达处理 demo：6 个正式计算步骤
│   └── task2_features/     特征提取 demo：8 个正式计算步骤
├── tests/
│   ├── unit/               核心类型及 12 个模块、81 个注册算子的独立测试
│   ├── contracts/          all81、dtype 和 14 个任务计算步骤的机器可读契约
│   ├── tools/              契约、接口、dtype 与任务步骤审计工具
│   └── platform/           ZQ500 SDK/API 兼容性夹具、编译与运行检查
├── data/
│   ├── reference/          固定输入、期望输出与单算子 manifest
│   ├── generated/          可再生的任务/测试输入及规模 manifest
│   ├── .reports_staging/   运行期暂存，已忽略；完整门禁通过前不发布
│   └── reports/            当前发布报告：units、benchmark、demo 和 validation
├── scripts/
│   ├── build.sh、test_operators.sh、demo.sh、validate.sh  容器内构建与运行入口
│   ├── finalize_reports.py、clean.sh                       报告发布与运行产物清理
│   └── sync_to_container.sh、pull_results.sh               宿主机容器同步与结果取回
├── third_party/fftw/       固定版本的离线 FFTW 构建依赖
└── docs/                   架构、构建运行、接口兼容、类型支持、验证与交付说明
```

结构图只列出稳定边界，不逐项展开 81 个算子、参考 CSV 或各模块的单测文件；这些条目分别
由 `tests/contracts/operator_sets.json`、各算子 manifest 和 `tests/unit/` 管理。

## 容器

本队容器是 `gpu_04`。在服务器宿主机执行：

```bash
sudo docker start gpu_04
sudo docker exec -it gpu_04 bash
```

进入容器后：

```bash
cd /CETC
source /zq500/sdk/env.sh ""
```

## 构建与运行

先在容器中构建：

```bash
scripts/build.sh --build-dir build-zx
```

构建并运行两个任务 demo，使用默认 L3 数据规模：

```bash
scripts/demo.sh --build-dir build-zx --build --repeat 5
```

构建并运行全部算子，使用每个算子 manifest 中定义的默认 full case：

```bash
scripts/test_operators.sh --build-dir build-zx --case-set full
```

构建并运行指定算子，使用该算子 manifest 中定义的默认 full case：

```bash
scripts/test_operators.sh \
  --build-dir build-zx \
  --module filtering \
  --operator wiener \
  --case-set full
```

查看可运行的模块和算子：

```bash
scripts/test_operators.sh --list
```

执行完整验证，包括构建、81 个算子、Task1/Task2 的 L1-L6、接口/dtype/任务步骤审计
及报告发布：

```bash
scripts/validate.sh --build-dir build-zx
```

完整验证成功后，当前报告发布到 `data/reports/`：

- `units/<module>/<operator>/`：逐算子测试数据；
- `units/benchmarks/summary.json` 和 `summary.csv`：全部算子的运行时间、加速比和误差汇总；
- `demo/`：两个任务的最终场景和 L1-L6 数据；
- `validation/`：接口、dtype、算子集合和任务步骤审计。

运行期数据写在 `data/.reports_staging/`，只有完整验证通过才会替换已发布报告。
构建目录、缓存、日志和历史过程文件不属于交付内容。详细容器工作流和结果取回见
[docs/BUILD_AND_RUN.md](docs/BUILD_AND_RUN.md)。
