# V7.0 深度优化计划

## 基线与边界

- 固定基线：V6-0138 硬门与 V6-0141 性能终测。
- Task1 L6：`3.91998 ms`。
- Task2 L6：`25.2926 ms`。
- correctness、接口、类型、dtype、14 步 timing/accuracy 和报告 schema
  仍为硬门。
- V7 不改写 V6 台账和最终报告。

## 显存判断

`gpu_mem_changes.log` 默认每秒采样，并且只记录容器从 0 MiB 变为非零的
第一次快照。它不记录后续增长、持续时间、完整参数和逐阶段利用率，因此
10 GiB 事件不能直接作为性能结论。

当前 L6 单任务逻辑数据只有几十 MiB。合理增加显存的条件是能够减少重复
计算、传输或 plan/setup；单纯扩大 allocator cache 不进入产品候选。

## 当前收缩范围

竞赛剩余时间内只优化 Task1/Task2。公共算子专项、其余 all81 性能和非任务
热点全部暂缓；all81 只作为 correctness 回归门。

V6 最终 warm 逐步骤基线：

| 任务 | L6 主要步骤 |
| --- | --- |
| Task2 | filter `5.36074 ms`；correlate `4.37071 ms`；spectrogram `5.07822 ms`；cwt `9.57086 ms`；total `25.2926 ms` |
| Task1 | pulse compression `0.879487 ms`；pulse Doppler `1.23025 ms`；CA-CFAR `0.733306 ms`；ambgfun `0.726965 ms`；total `3.88839 ms` |

当前优先级：

1. Task2 AOT correlate 已通过并保留。
2. Task2 spectrogram AOT FFT 已通过并保留。
3. Task2 Morlet2 CWT 对称成对卷积已验证，大尺寸收益不足并默认关闭。
4. 建立 5 分钟演示负载：Task1、Task2 和附件中效果最好的 30 个算子。
5. Task1 固定 buffer、同步缩减和可捕获段 Graph；不重写已有 dlFFT。
6. fCWT 暂缓：`N=4096, batch=1440` 的 AOT 单次 inverse 已约
   `7.70 ms`，接近当前完整 CWT `9.57 ms`，短期大收益概率低。

紧急时间盒：

- V7.1 已按分支独立判定：保留 correlate，AOT filter 默认关闭。
- V7.2 已按三档稳定正收益保留，原挑战门失败不再解释为代码失败。
- V7.3 CWT 已按门禁停止，实验路径默认关闭。
- Task1 只接受跨步骤总时延收益；单算子低于 `0.15 ms` 的优化不再展开。
- 每个候选最多“实现一次、容器验证一次、针对明确原因修正一次”；第二次仍
  不达门则记录并关闭。

## 执行顺序

| 阶段 | 目标 | 进入产品的最低条件 |
| --- | --- | --- |
| V7.0-01 | 固定尺寸 AOT FFT 探针 | Task 实际尺寸精度通过；首次和稳态均可测；无异常资源占用 |
| V7.1 | Task2 AOT correlate | L3/L6 correlate 至少下降 30%；L3/L6 total 至少下降 15%/8%；精度通过；AOT filter 独立失败不影响 correlate 保留 |
| V7.2 | Task2 spectrogram AOT FFT | 三档精度通过且保持稳定正收益；已保留 |
| V7.3 | Task2 Morlet2 CWT 对称成对卷积 | 已关闭；大数据默认关闭 |
| V7.4 | 5 分钟演示负载与显存换性能 | 已关闭；双任务和 30 算子 wall=`101.971 s`，扩大缓存未通过收益门，保持默认缓存 |
| V7.5 | Task1 固定 buffer 与 Graph | 已关闭；设备分配减少，但两轮合并 L6 退化 `2.38%`，产品默认关闭，不展开 Graph |
| V7.6 | 全量回归与交付 | 已关闭；all81、dtype、14 步、Task L1-L6、演示 wall 和报告目录均通过 |

每个完成的小版本生成对应 `docs/submission/READMEV7_X.md`。

## 第一轮探针

`tests/platform/zx_fixed_fft_probe.cu` 比较以下实际尺寸：

- Task2 spectrogram：`N=512, batch=2784`。
- Task2 correlate：`N=4096, batch=97`。
- Task2 fCWT 候选：`N=4096, batch=1440`。
- Task1 pulse compression：`N=2048, batch=192`。
- Task1 pulse Doppler：`N=256, batch=2048`。

探针同时输出 dlFFT plan/首次/稳态、固定 radix-2 首次/稳态、正变换误差、
往返误差、工作区变化和 dlsmi 时间序列。探针通过前不修改任务产品代码。

## V7-0004 结论

- 五组 probe 均返回 0；正变换 relative RMSE 为
  `2.55e-7` 至 `3.11e-7`，往返 relative RMSE 为
  `1.79e-7` 至 `2.15e-7`。
- dlFFT 首次 forward 为 `3452-3758 ms`；AOT 首次 forward 为
  `3.26-10.71 ms`，冷启动下降约 `341-1109` 倍。
- AOT 稳态比 dlFFT 慢约 `1.94-5.81` 倍，因此不替换已有 Task1 FFT。
- Task2 当前 filter/correlate 仍为直接卷积，AOT 即使慢于 dlFFT，
  预计仍可显著快于当前路径；V7-0005 共用 FFT 工作区，并在 combined
  路径复用 filter 输出频谱，correlate 只新增模板正 FFT、频域乘法和逆 FFT。

## V7-0005 结论

- AOT correlate 独立精度通过。L3 `6.33735 -> 0.668634 ms`，
  下降 `89.45%`；L6 `4.45944 -> 1.70953 ms`，下降 `61.66%`。
- 对应 Task2 total median：L3 `12.7366 -> 7.67928 ms`，下降
  `39.71%`；L6 `25.2763 -> 22.8060 ms`，下降 `9.77%`。
- AOT filter 的 filtered mixed error 仍小于 `1.1e-5`，但 FM demod
  对相位扰动敏感，demod mixed error 放大到 `1.10/2.03`，因此产品默认
  回到公共 FIR。
- combined 频谱复用依赖已否决的 AOT filter，且 correlate mixed error
  为 `3.72/3.08`，不再修正。
- V7-0006 以“公共 FIR + AOT correlate”为共同基线，只验证 AOT
  spectrogram，并在通过后执行 Task2 L1-L6、Task1 smoke 和 all81。

## V7-0006 结论

- L3/L5/L6 spectrogram 分别下降 `47.49%/20.86%/43.37%`，Task2
  total median 分别下降 `25.08%/3.79%/7.78%`。
- 三档数值和业务验证全部通过，spectrogram mixed error 与基线一致。
- 原 runner 因 L5 未达到挑战门而在全量门前止损；该结果不否定稳定正收益，
  因此保留 AOT spectrogram，并将完整回归并入 V7-0007。

## V7-0007 候选

- Task2 的 15 个 Morlet2 核实部偶对称、虚部奇对称；六档共 `1350`
  对系数已在宿主探针中全部位级满足契约。
- 每对输入使用 `(left + right) * real` 和
  `(left - right) * imag`，将每尺度系数读取与 FMA 主循环约减半。
- 建表时逐对验证契约；不满足时自动走旧内核。环境变量
  `CUSIGNAL_TASK2_ENABLE_CWT_SYMMETRY=1` 用于显式实验。

## V7-0007 结论

- 三档精度与业务验证全部通过，CWT mixed error 与基线一致。
- L3 CWT/total 下降 `10.14%/6.48%`；L5 分别退化
  `1.28%/1.73%`；L6 CWT下降 `3.13%`，但 total 退化 `1.29%`。
- 大尺寸下第二侧 shared load、和差与寄存器成本抵消 FMA 减半，因此产品
  默认回到原内核；对称版本只保留为显式实验路径。

## V7-0008 方案

- `demo_top30` 固定取 V6-0141 最终 L6 `gpu_e2e_speedup` 前 30 项，
  不在现场临时改榜单。
- 演示算子使用 `large-gpu` L6：线性类 `16777216` 点、FFT 类
  `1048576` 点；`ambgfun/lombscargle` 等二次复杂度类保持 `8192`。
- 准备阶段执行 all81、dtype、14 步、Task1/Task2 L1-L6，生成
  large-gpu CPU baseline；这些时间不计入现场 wall。
- 现场阶段执行 Task1 L6、Task2 L6 和 top30 GPU-only，baseline 必须
  逐项复用，wall 硬门 `240 s`。
- `ambgfun/cwt/gausspulse/wiener` 比较默认 DeviceStorage cache
  `512/256 MiB` 与扩大 cache `4096/3072 MiB`。扩大模式只有在四项
  GPU E2E 总时延至少下降 `2%`、且任一算子退化不超过 `5%` 时启用。
- runner：
  `scripts/platform/run_v7_4_demo_budget.sh`；准备缓存放
  `/tmp/cetc_v7_demo_cache/`，日志和归档放 `/tmp`。

## V7-0008 结论

- 准备阶段通过 all81 `81/81`、dtype 缺口 `0`、任务步骤 `14/14` 和
  Task1/Task2 L1-L6；报告与 generated manifest 恢复 diff 均为 `0`。
- 现场阶段状态为 `passed`，wall=`101.971 s / 240 s`；Task1 L6
  `3.88566 ms`，Task2 L6 `20.1547 ms`。
- 固定 Top30 全部通过，中位加速 `109.919x`，几何平均 `105.455x`。
- dlsmi 共 `1869` 个样本，进程显存峰值 `2453 MiB`，GPU 利用率峰值
  `99%`。低平均利用率来自 102 秒现场流程中大量 CPU/进程启动间隔，不能
  推导为单个 kernel 没有并行工作。
- 扩大缓存四算子总时延仅下降 `0.096%`；`ambgfun` 额外保留约
  `1 GiB` 只下降 `0.146%`。未达到 `2%` 门，产品保持默认缓存。
- 证据：
  `/home/usr_04/CETC_garbage/cetc_v7_0008_pull_ze3a63s8/`。

## V7-0009 候选

- Task1 当前每次 `run_once` 先保留整套预热输出，再启动测量轮；这些输出
  在测量结束前仍占有设备块，使 DeviceStorage 无法复用对应 buffer。
- 首轮候选由显式环境变量启用，于测量前释放不再使用的预热输出；公共
  接口、算法、精度阈值和六步 timing 字段不变。
- 先在 L3/L5/L6 做进程隔离的 A/B。只有 L5/L6 total 均至少下降 `5%`
  且数值验证通过，才将该生命周期策略改为默认；因汇报时限不继续 Graph。

## V7-0009 结论

- 容器完整运行 rc=`0`；L3/L5/L6 baseline total 中位数为
  `1.40482/2.33539/4.89437 ms`，候选为
  `1.38284/2.03471/3.90229 ms`，分别下降
  `1.56%/12.87%/20.27%`。
- 三档精度逐项完全一致，六步 timing 完整；Task1 L1/L2/L4 与 Task2
  L1/L6 smoke 全部通过。
- 五轮后 baseline 累计分配/cache hit=`42/72`，候选=`14/100`；候选
  首轮完成 14 次分配后不再新增，证明收益来自设备块复用。
- dtype 缺口 `0`、任务步骤 `14/14`，报告与 generated manifest 恢复
  diff 均为 `0`。dlsmi 3393 样本，显存峰值 `453 MiB`。
- 候选曾临时改为默认，V7-0010 使用独立流水号重复同一 A/B；是否保留以
  第二轮复核和两轮合并结果为准。
- 证据：
  `/home/usr_04/CETC_garbage/cetc_v7_0009_pull_YiZwJVyu/`。

## V7-0010/V7-0011 结论

- V7-0010 完整运行并正常归档，静态门、三档精度和六步 timing 全部通过，
  报告与 manifest 恢复 diff 为 `0`。
- 第二轮 L3/L5/L6 total 变化为 `+2.73%/+5.90%/-12.81%`；关键 L6
  未达到 `5%` 门，因此候选被拒绝。
- 两轮各 5 次合并后，L3/L5/L6 变化为
  `+2.15%/+12.69%/-2.38%`。两轮进程 wall 均未下降，不能将减少分配
  直接登记为稳定端到端收益。
- 缓存证据可复现：baseline allocation/cache hit=`42/72`，候选
  `14/100`。该路径保留为
  `CUSIGNAL_TASK1_RELEASE_WARMUP_BUFFERS=1` 实验开关，产品默认使用原
  生命周期。
- V7-0011 依据硬门完成默认回退和最终冻结；不再展开 Graph。
- V7-0010 证据：
  `/home/usr_04/CETC_garbage/cetc_v7_0010_pull_bR3cnvq7/`。
