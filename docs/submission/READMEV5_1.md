# V5.1 可观测性与基线阶段交付文档

## 版本信息

- 当前状态：已完成。
- 对应计划：`docs/performance/v5_0/plans/V5_1_plan.md`
- 对应台账：V5-0001、V5-0002。

## 核心交付

- `DeviceStorageCache` allocation、hit/miss、recycle、eviction、驻留和峰值指标。
- all-ops benchmark CSV 的 `device_cache_*` 字段。
- `scripts/platform/sample_gpu_memory.py` 整卡显存和利用率采样。
- Stage5 summary 的显存峰值、平均值、free memory 和利用率字段。

## 验证结果

- `filtering/wiener` L1 指标 probe：1/1 PASS。
- filtering L2 schema smoke：17/17 PASS。
- 全模块 schema smoke：12 模块、81/81 PASS，cache 字段缺失 0。
- GPU memory probe：76 个采样点，`gpu_memory_available=true`。

## 完成判定

V5.1 已关闭；后续阶段可使用统一 timing、误差、cache 和整卡显存证据评估收益。

