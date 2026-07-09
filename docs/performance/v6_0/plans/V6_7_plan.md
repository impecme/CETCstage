# V6.7 赛题算子库轻度优化计划

## 状态与目标

- 状态：待开始；进入条件：任务主链路和 P1 算子深化已关闭。
- 目标：对赛题明确提到但不在任务热点链路中的算子做低风险轻度优化。

## 工作包

| ID | 工作包 | 允许措施 | 关闭条件 |
| --- | --- | --- | --- |
| V6.7-01 | double 字面量清理 | GPU 端 float 常量、避免隐式 double | 单算子 full 通过，无精度退化 |
| V6.7-02 | copy 清理 | 消除多余 H2D/D2H 和 D2D | cache/copy 指标下降或解释保留 |
| V6.7-03 | workspace/cache 复用 | 复用已有 `DeviceStorageCache` 和模块 workspace | allocation、miss 或峰值下降 |
| V6.7-04 | 小数组 fast path | fusion 或固定配置 | 小规模不被 launch 数量拖垮 |
| V6.7-05 | 暂缓列表 | 非赛题、非任务、低收益项 | 不再重复深挖 |

## 执行规则

- 只做低风险、容易验证的改动。
- 不重写原 cuSignal 全库非任务算子。
- 任一改动必须通过单算子 full；跨模块 helper 需跑受影响模块 full。

## 回传与关闭条件

回传扩展算子 benchmark、模块 full 和暂缓列表。关闭条件：赛题相关非主链路算子均有轻度处理结论，all81 quick correctness 通过。
