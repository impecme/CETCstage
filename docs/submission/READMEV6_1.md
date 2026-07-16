# V6.1 基线与平台探针交付文档

## 版本信息

- 当前状态：已关闭。
- 对应计划：`docs/performance/v6_0/plans/V6_1_plan.md`。
- 对应台账：V6-0025、V6-0035、V6-0036、V6-0098。

## 基线结果

| 项目 | 结果 |
| --- | --- |
| Task2 L6 GPU total | `76.0695 ms` |
| Task2 L6 主要热点 | CWT `34.0065 ms`、spectrogram `25.4401 ms`、correlate `9.75641 ms` |
| Task1 L6 GPU total | `7.19016 ms` |
| Task1 L6 主要热点 | pulse compression `3.27254 ms`、pulse Doppler `1.56758 ms`、CA-CFAR `0.997072 ms` |
| all81 correctness | `81/81` |
| dtype / Task 步骤 | dtype 缺口 0；14 步 timing/accuracy 缺口 0 |

## 平台结论

- Release flags 为 `-O3 -DNDEBUG`。
- `concurrentKernels=1`，async engine 数量为 2。
- 非默认 stream 和 `cufftSetStream` 通过。
- 单 plan 首建约 `40.7092 ms`，batch8 plan 约 `0.270273 ms`。
- V6-0036 曾记录 CUDA Graph `unsupported`，但 capture 位于 stream/device buffer 销毁之后，该结论无效。
- V6-0098 有效生命周期探针中 capture begin/work/end、instantiate、launch、sync 状态均为 0，平台结论修正为 `graph=supported`。

## 证据

- Task2 与全量基线：`/home/usr_04/CETC_garbage/cetc_v6_0208r_pull_20260711/`。
- Task1 与平台探针：`/home/usr_04/CETC_garbage/cetc_v6_0035_pull_20260712_083150/`。
- Graph 原始失败证据：`/home/usr_04/CETC_garbage/cetc_v6_0036_pull_20260712_084054/`。
- Graph 勘误与当前源码关闭证据：`/home/usr_04/CETC_garbage/cetc_v6_0098_pull_20260714_165704/`，归档 SHA256=`0a2367f2...`。

## 完成判定

V6.1 已提供两个任务、全量 correctness、类型/步骤审计和平台能力的固定分母。后续性能百分比不得改用 V5.5 L3 或旧部署数据。
