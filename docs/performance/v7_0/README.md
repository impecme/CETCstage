# V7 深度性能优化

## 状态

- V6.8 与 V6 最终交付保持关闭，不修改其结论和报告。
- V7.1 A/B 已完成：保留 AOT correlate，AOT filter 默认关闭。
- V7.2 A/B 已完成：保留 AOT spectrogram。
- V7.3 Morlet2 CWT 对称成对卷积已验证，大数据收益不足，产品默认关闭。
- V7.4 已关闭：Task1 L6、Task2 L6 与固定 Top30 的现场 wall 为
  `101.971 s / 240 s`；扩大 DeviceStorage cache 收益仅 `0.096%`，
  产品保持默认缓存。
- V7.5 已关闭：预热 buffer 复用可减少设备分配，但两轮合并后 L6 退化
  `2.38%`，产品默认关闭，仅保留显式实验路径。
- V7.6 与 V7 已关闭；最终汇报使用 V7-0008 冻结的双任务和 Top30 演示。
- 中间日志和 probe 归档继续只放 `/tmp` 与
  `/home/usr_04/CETC_garbage/`。

## 目标

V7 只处理需要算法重写或跨算子生命周期设计的剩余方向：

1. Task2 固定尺寸 AOT correlate 已通过独立 A/B。
2. Task2 spectrogram batched AOT FFT 已通过并保留。
3. V7-0008 已使用 `large-gpu` L6 放大线性和 FFT 类数据；二次复杂度
   算子保持安全尺度，Top30 全部通过。
4. CPU 对照、构建、all81 和六档任务回归在演示前完成；现场只复用已校验
   CPU baseline 并重新采集 GPU timing。
5. DeviceStorage 扩大缓存四算子 A/B 未达到 `2%` 收益门，产品使用默认
   `512/256 MiB` 缓存；后续只优化有真实复用关系的固定 buffer。

Top30 选择口径见 `demo_top30_selection.md`。当前采用紧急时间盒：每个候选
最多一次实现、一次正式验证和一次针对性修正；只保留精度通过且有稳定
端到端收益的分支。

当前不再展开 Graph、batch 放大或公共算子优化。V7-0011 已完成默认路径
回退和最终冻结，后续工作转入汇报材料。

详细计划见 `plans/V7_0_plan.md`，执行记录见
`optimization_change_log.md`。
