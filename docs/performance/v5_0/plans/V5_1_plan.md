# V5.1 可观测性与基线计划

## 状态

- 状态：已完成。
- 对应台账：V5-0001、V5-0002。
- 对应交付：`docs/submission/READMEV5_1.md`。

## 目标

- 为公共 `DeviceStorageCache` 增加 allocation、hit/miss、recycle、eviction 和驻留显存指标。
- 为 Stage5 benchmark 增加整卡显存、GPU 利用率时间序列和汇总字段。
- 固化单算子、模块和全模块 schema smoke 基线。

## 范围

- `include/cusignal/core/types.hpp`
- `tests/unit/common/report.hpp`
- `scripts/test/benchmark_all_ops_scales.py`
- `scripts/platform/sample_gpu_memory.py`
- `scripts/platform/run_zhongkexin_stage4.sh`

## 关闭证据

- `filtering/wiener` L1 指标 probe 通过。
- filtering 17 算子 L2 schema smoke 通过。
- 全模块 12 模块、81 算子行 schema smoke 通过，缺失 cache 字段为 0。
- GPU memory probe 写出 76 个采样点，Stage4 summary 可读取峰值、平均显存和利用率。

## 遗留边界

- 模块内部 `DeviceBuffer` 不属于公共 cache 统计范围，后续按热点需要在 V5.2/V5.4 处理。
- 整卡显存采样包含运行时和其他进程影响，只用于同环境前后对比。
