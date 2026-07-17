# V7.5 Task1 固定 buffer 交付

## 状态

- 当前状态：已关闭；V7-0010 未复现关键 L6 收益，候选默认关闭。
- 修改只影响 Task1 demo 的预热输出生命周期，公共算子接口、算法、类型、
  精度阈值和报告 schema 不变。
- 默认路径保留预热输出；buffer 复用实验仅由
  `CUSIGNAL_TASK1_RELEASE_WARMUP_BUFFERS=1` 启用。

## 候选

- 在测量轮开始前释放不再使用的预热输出，使 DeviceStorage 可复用已分配
  的设备块，减少重复分配和设备空闲时间。
- A/B 覆盖 L3/L5/L6，各运行 5 次；同时记录缓存命中、分配次数和 50 ms
  dlsmi 时间序列。
- L5/L6 total 均下降至少 `5%`、所有精度验证通过且六步 timing 完整时
  才选择候选；否则关闭该方向。

## V7-0009 结果

| 规模 | baseline | 候选 | total 下降 |
| --- | ---: | ---: | ---: |
| L3 | `1.40482 ms` | `1.38284 ms` | `1.56%` |
| L5 | `2.33539 ms` | `2.03471 ms` | `12.87%` |
| L6 | `4.89437 ms` | `3.90229 ms` | `20.27%` |

- 精度逐项一致，六步 timing 完整。
- 五轮累计设备分配从 `42` 次降至 `14` 次，cache hit 从 `72` 增至
  `100`；候选首轮后无新增分配。
- Task1 六档、Task2 L1/L6、dtype 和 14 步门均通过，目录恢复无差异。

## V7-0010 复核

| 规模 | baseline | 候选 | total 变化 |
| --- | ---: | ---: | ---: |
| L3 | `1.39832 ms` | `1.36010 ms` | 下降 `2.73%` |
| L5 | `2.09354 ms` | `1.96992 ms` | 下降 `5.90%` |
| L6 | `4.02336 ms` | `4.53870 ms` | 退化 `12.81%` |

- 第二轮精度、六步 timing、静态门和目录恢复均通过，但 L6 性能门失败。
- 两轮 10 次合并后 L3/L5/L6 变化为
  `+2.15%/+12.69%/-2.38%`；关键 L6 不登记收益。
- 设备分配减少可复现，但两轮进程 wall 均未下降，因此只保留实验开关。

## 回归边界

- 候选通过后补 Task1 L1/L2/L4 和 Task2 L1/L6 smoke。
- dtype 缺口必须为 `0`，任务 timing/accuracy 缺口必须为 `0`。
- all81 沿用 V7-0008 的 `81/81` 证据；本轮未修改公共算子库。
- `data/reports/` 与 generated manifest 必须恢复无差异。

## 执行

- Runner：`scripts/platform/run_v7_5_task1_buffer_reuse.sh`
- V7-0009 证据：
  `/home/usr_04/CETC_garbage/cetc_v7_0009_pull_YiZwJVyu/`
- V7-0010 证据：
  `/home/usr_04/CETC_garbage/cetc_v7_0010_pull_bR3cnvq7/`
