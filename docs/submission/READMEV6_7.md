# V6.7 赛题算子库轻度优化交付文档

## 版本信息

- 当前状态：已关闭。
- 对应计划：`docs/performance/v6_0/plans/V6_7_plan.md`。
- 进入条件已满足：V6-0098 已关闭 V6.6 七个工作包。
- 已保留：V6-0099 `windows/taylor` 固定系数 kernel 低阶余弦递推。
- 已保留：V6-0100 `windows/general_cosine` 固定系数 kernel 低阶余弦递推。
- 已保留：V6-0101/V6-0103 `waveforms/gausspulse` envelope 复用和四输出变体。
- 已完成测量修正：V6-0102 产品/benchmark 共用 component helper。
- 已保留：V6-0104 `windows/kaiser` Bessel float32 精确停机。
- 已保留：V6-0105 `waveforms/chirp` 线性斜率宿主预计算和 complex kernel 测量对齐。
- 已回退：V6-0106 `wavelets/morlet2` 联合 sin/cos 无实质收益。
- 已保留：V6-0107 `wavelets/ricker` 偶对称成对输出。
- 已保留：V6-0108 `wavelets/morlet2` 共轭对称成对输出。
- V6-0109 `wavelets/morlet` 性能通过但严格精度门禁失败。
- 已回退：V6-0110 `wavelets/morlet` 精确 Gaussian 与相位旋转修正仍未通过严格精度门禁。
- 已保留：V6-0111 `windows/general_gaussian` 对称成对计算。
- 已保留：V6-0112 `windows/parzen` 位级对称成对计算。
- 已保留：V6-0113 `windows/hamming` 精确混合成对计算。
- 已回退：V6-0114 `waveforms/sawtooth,square` 精确周期取模快路径稳定退化。
- 已保留：V6-0115 `windows/triang` 位级对称成对输出。
- 已回退：V6-0116 `wavelets/qmf` 偶数大数组 `float2` 成对反序读写稳定退化。
- 中间保留：V6-0117 `spectral/lombscargle` 双频 block 稳定下降约 `3.3%`，但未完成专用 5%和完整回归门禁。
- 已保留：V6-0118 `spectral/lombscargle` 双频 block 归约同步优化，并关闭 V6-0117/0118 组合门禁。
- 已保留：V6-0119 `spectral/vectorstrength` partial 归约同步优化。
- 已保留：V6-0120 `spectral/vectorstrength` 双 period block。
- 已保留：V6-0121 `filtering/channelize_poly` 8 通道 point kernel。
- 已保留：V6-0122 `filtering/firfilter2` 反向直写。
- 已保留：V6-0123 `filtering/resample` 频谱重排融合。
- 已保留：V6-0124 `filtering/resample` 窗乘融合；首轮设备 A/B SIGSEGV 经 V6-0125 至 V6-0128 完成平台归因和正式重验。
- 已完成诊断：V6-0125 将崩溃定位到 `1048576 -> 1572863` 首次 generic 调用。
- 已关闭验证工具链：V6-0126 的 `-x cuda` 链接污染由 V6-0127 修复，V6-0128 完成阶段 marker 判定和正式验收。
- 已回退：V6-0129 `spectral/stft` 无 detrend 分段准备收益不足。
- 已暂缓：V6-0130 packed-C2C CSD 被 host 精度 probe 否决。
- 已回退：V6-0131 `spectral/csd` 连续双 batch 收益不足。
- 已保留：V6-0132 `spectral/periodogram` 命名窗口、scale 和频率轴缓存。
- 已保留：V6-0133 `spectral/welch` setup 缓存和 spectral cache key 精度加固。
- 已保留：V6-0134 `spectral/istft` 窗口、窗口和、时间轴缓存；增采样确认按原门限完整通过。
- 已收束：V6-0135 完成 all81 剩余热点处置审计，V6.7 不再新增产品候选。

## 交付范围完成情况

- GPU float 字面量、局部数学路径和 build flags 已按候选完成审计；无全局 fast-math。
- 冗余计算、同步、copy 和 setup 固定开销已在保留项中小步消除，失败项已回退。
- V6.6 runtime/cache/workspace 基础设施已推广到 periodogram、Welch 和 ISTFT。
- 对称成对计算、固定系数递推、归约同步和专用小路径均已完成专项验收。
- 非赛题、非任务、低收益和需深度重写的剩余项已形成暂缓清单。

## 关闭门禁

- 每个改动通过单算子 full；跨模块 helper 通过受影响模块 full。
- 默认要求单算子 E2E 收益至少 5%或绝对节省至少 `0.05 ms`。
- correctness、dtype、API、类型和报告 schema 不允许降低；高噪声辅助性能批次门最多可在 `repeat>=100` 时由 `4/5` 调整为 `3/5`，但 V6.7 最终确认未使用该放宽。
- 禁止全局 fast-math，不深度重写非任务 cuSignal 算子。
- all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0。

## V6-0099 门禁

- 基线来自 V6-0098：Taylor E2E/kernel=`7.69851/7.59305 ms`，GPU/CPU max abs=`1.78814e-7`。
- 候选只把每点最多 8 次独立 `cosf(n*angle)` 改为一次 `cosf(angle)` 加低阶递推；系数、angle、归一化、shape、dtype、API 和报告 schema 不变。
- 先跑 5 批 Taylor full、每批 warmup 2/repeat 10；批次中位 E2E 至少下降 5%，所有数值用例通过。
- 通过后运行 windows full、Task1/Task2 L1 smoke、all81 full、dtype/步骤审计和 manifest 检查；完整结果回传后再写保留或回退结论。

## V6-0099 交付结论

- 五批 Taylor E2E 中位数由 `7.69851 ms` 降至 `4.21346 ms`，下降 `45.27%`；kernel 由 `7.59305 ms` 降至 `4.12130 ms`，下降 `45.72%`，五批全部满足门禁。
- max abs 从 `1.78814e-7` 变为 `2.38419e-7`，只增加一个 float32 量级；RMSE 保持 `2.43335e-8`，全部 accuracy/reference 用例通过。
- windows `23/23`、Task1/Task2 L1 smoke、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过。
- dlsmi：进程/全卡显存峰值=`80/373 MiB`，GPU P95/active median=`99%/99%`，memory util P95=`2%`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0099_pull_2nP1MNCF/`；归档/console SHA256=`8a0577d5.../9ee7a794...`。

## V6-0100 门禁

- V6-0099 all81 基线：general cosine E2E/kernel=`5.70083/5.61463 ms`。
- 候选只在最多 5 个固定系数路径中用一次 `cosf(angle)` 加二阶递推生成后续谐波；通用系数 fallback、公共 API、系数、shape/dtype 和 schema 不变。
- 五批 general cosine full 的 E2E 中位数至少下降 5%、kernel 不退化且所有数值用例通过；随后执行 windows full、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0100 交付结论

- 五批 general cosine E2E/kernel 中位数=`2.90603/2.81139 ms`，相对基线下降 `49.02%/49.93%`，五批全部满足门禁。
- max abs 保持 `3.57628e-7`，RMSE 从 `4.70274e-8` 变为 `4.72874e-8`；所有 accuracy/reference 用例通过。
- windows `23/23`、Task1/Task2 L1、all81 `81/81`、dtype 缺口 0、14 步缺口 0、manifest 全部通过。
- dlsmi：进程/全卡显存峰值=`80/373 MiB`，GPU P95/active median=`99%/98%`，memory util P95=`2%`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0100_pull_ovpecOzi/`；归档/console SHA256=`aa73e30e.../fe2ec212...`。

## V6-0101 门禁

- V6-0100 all81 gausspulse bundle E2E/kernel=`5.40349/5.35596 ms`，real-only=`2.64759/2.60354 ms`。
- 候选只复用同一样本的 `expf(-a*t*t)` 结果；保留独立 `cosf/sinf`、原乘法顺序、API、输出组合、shape/dtype 和 schema。
- 五批 gausspulse full 中 bundle E2E/kernel 至少下降 5%，real-only 不得退化超过 3%；随后执行 waveforms full、双任务 L1、all81、dtype、步骤、dlsmi 和 manifest。

## V6-0101 结果

- 五批 bundle E2E 中位数=`4.46783 ms`，相对 `5.40349 ms` 下降 `17.32%`；real-only E2E 下降 `1.05%`，全部数值用例通过。
- 报告 kernel 中位数=`5.35673 ms`，与基线持平且大于 E2E。审计确认 kernel 指标来自测试文件中独立复制的旧 kernel，并未执行候选产品实现，因此原 kernel 门禁无效。
- 后续 telemetry、waveforms full、任务 smoke 和 all81 按门禁跳过；manifest 无差异。候选不宣告保留或回退，转 V6-0102 修正测量链。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0101_pull_LFOuYEmw/`；归档/console SHA256=`3c1ae9f3.../c0bc1432...`。

## V6-0102 门禁

- 新增内部 `gausspulse_components`，产品和测试 kernel 共用完全相同的 envelope/trig 路径，消除复制实现漂移。
- 仍以 V6-0100 bundle E2E/kernel=`5.40349/5.35596 ms`、real-only=`2.64759/2.60354 ms` 为分母；bundle 双指标至少下降 5%，real-only 双指标退化不超过 3%。
- 通过后补齐 dlsmi、waveforms `5/5`、双任务 L1、all81 `81/81`、dtype、步骤和 manifest。

## V6-0102 结果

- 修正后的五批 bundle E2E/kernel 中位数=`4.33832/4.28933 ms`，相对 V6-0100 下降 `19.71%/19.91%`，确认 envelope 复用收益真实存在。
- real-only E2E/kernel=`2.80569/2.76140 ms`，退化 `5.97%/6.06%`，超过 3% 硬门禁；十个 perf case 数值全部通过，max abs=`1.78814e-7`。
- 后续完整阶梯按止损跳过，manifest 无差异；证据目录 `/home/usr_04/CETC_garbage/cetc_v6_0102_pull_XgEqSDPt/`，归档/console SHA256=`123430fd.../41016247...`。

## V6-0103 门禁

- `retquad/retenv` 改为两个 bool 模板参数，编译出 real、IQ、I+envelope、bundle 四个 kernel；`if constexpr` 删除各变体不需要的计算和分支。
- 产品和 benchmark 继续调用同一模板 helper；公共 API、CPU 路径、公式、输出 variant、shape/dtype 和 schema 不变。
- 仍以 V6-0100 为原始分母：五批 bundle E2E/kernel 均至少下降 5%，real-only 双指标退化不超过 3%；通过后运行 dlsmi、waveforms `5/5`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0103 交付结论

- 五批 real-only E2E/kernel 中位数=`2.58396/2.52858 ms`，相对 V6-0100 下降 `2.40%/2.88%`；bundle=`4.48914/4.44098 ms`，下降 `16.92%/17.08%`。
- waveforms `5/5`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过。
- dlsmi：进程/全卡显存峰值=`528/821 MiB`，GPU P95/active median=`99%/99%`，memory util P95=`5%`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0103_pull_FZrobtBr/`；归档/console SHA256=`cf8501a6.../544b77a0...`。

## V6-0104 门禁

- V6-0103 all81 Kaiser E2E/kernel=`10.0802/9.94272 ms`；beta 8.6 的 Bessel 级数旧路径执行 22 次迭代。
- 保留原级数和项顺序，仅在 `next_sum == sum` 时停止；宿主 float32 模拟 `x=[0,20]` 共 20001 点位级差异为 0，beta 8.6 降为 15 次迭代。
- 五批 Kaiser full 要求 E2E/kernel 均至少下降 8%、至少四批达标且 max abs 不高于 `1.66893e-6`；通过后运行 dlsmi、windows `23/23`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0104 交付结论

- 五批 Kaiser E2E/kernel 中位数=`6.65311/6.57719 ms`，相对 V6-0103 下降 `34.00%/33.85%`；max abs/RMSE=`1.66893e-6/1.76505e-7`。
- windows `23/23`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过。
- dlsmi：进程/全卡显存峰值=`80/373 MiB`，GPU P95/active median=`99%/99%`，memory util P95=`2%`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0104_pull_MqwlyZ07/`；归档/console SHA256=`9f1af9a8.../4efa2dbf...`。

## V6-0105 门禁

- V6-0104 all81 linear real E2E/kernel=`2.73803/2.69989 ms`，complex E2E=`4.13651 ms`；候选只把 `(f1-f0)/t1` 从逐样本 GPU 除法改为宿主一次预计算，不改公式和相位乘加顺序。
- 旧 complex benchmark 写两个独立 float 数组，产品写交错 `float2`；修正布局后的 complex kernel 只报告，不与旧 `4.37525 ms` 比较。
- 五批 chirp full 要求 real E2E/kernel 至少下降 3%、complex E2E 至少下降 2%、两类 E2E 合计至少下降 3%，各 E2E 至少四批达标且 max abs 不增；通过后运行 dlsmi、waveforms `5/5`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0105 交付结论

- 五批 real E2E/kernel 中位数=`2.61261/2.57477 ms`，下降 `4.58%/4.63%`；complex E2E=`3.71627 ms`，下降 `10.16%`，修正布局后的 kernel=`3.67744 ms`；两类 E2E 合计下降 `7.94%`。
- waveforms `5/5`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过。
- dlsmi：进程/全卡显存峰值=`464/757 MiB`，GPU P95/active median=`99%/99%`，memory util P95=`4%`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0105_pull_20260714_215407/`；归档/console SHA256=`9c3c66e7.../4c732124...`。

## V6-0106 门禁

- V6-0105 all81 morlet2 E2E/kernel=`30.5184/30.2880 ms`，summary max abs=`5.96046e-8`；perf case max abs=`1.666e-8`。
- 候选只把同一 phase 的独立 `cosf/sinf` 改为 `sincosf`，不改坐标、amplitude、Gaussian、phase、输出布局、API、dtype/shape 或 schema。
- 五批 morlet2 full 要求 E2E/kernel 均至少下降 5%、至少四批达标且 summary/perf max abs 均不增；通过后运行 dlsmi、wavelets `5/5`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0106 结果

- 五批数值及误差门禁均通过；E2E/kernel 中位数=`30.4297/30.3561 ms`，仅下降 `0.29%`/退化 `0.22%`，双项达标批次为 0。
- 后续完整阶梯按止损跳过，manifest 无差异；源码已恢复 SHA=`1af1ab0f...`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0106_pull_20260714_220504/`；归档/console SHA256=`cb88e323.../8d1dffd5...`。

## V6-0107 门禁

- V6-0105 all81 Ricker E2E/kernel=`29.5576/29.4336 ms`，perf case 为 16777216 点，summary/perf max abs 均为 `2.98023e-8`。
- `points <= 2^24` 时只计算前半区并将同值写入镜像位置；超出 float 精确整数索引范围时仍走原 kernel。公式、参数预计算、输出顺序、API、dtype/shape 和 schema 不变。
- 五批 Ricker full 要求 E2E/kernel 均至少下降 20%、至少四批双项达标且 summary/perf max abs 均不增；通过后运行 dlsmi、wavelets `5/5`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0107 交付结论

- 五批 E2E/kernel 中位数=`15.3383/15.2579 ms`，下降 `48.11%/48.16%`，五批双项全部达标；summary/perf max abs 均保持 `2.98023e-8`。
- wavelets `5/5`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过。
- dlsmi：进程/全卡显存峰值=`1106/1399 MiB`，GPU P95/active median=`99%/99%`，memory util P95=`8%`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0107_pull_20260715_123949/`；归档/console SHA256=`5f3ac454.../ca83dc8e...`。

## V6-0108 门禁

- V6-0107 all81 morlet2 E2E/kernel=`30.4007/30.1426 ms`，summary/perf max abs=`5.96046e-8/1.666e-8`。
- `points <= 2^24` 且参数有限时只计算前半区，并向镜像位置写共轭值；更大 points 或非有限参数仍走原 kernel。坐标、Gaussian、phase、乘法顺序、API、dtype/shape 和 schema 不变。
- 五批 morlet2 full 要求 E2E/kernel 均至少下降 20%、至少四批双项达标且 summary/perf max abs 均不增；通过后运行 dlsmi、wavelets `5/5`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0108 交付结论

- 五批 E2E/kernel 中位数=`16.7873/16.6851 ms`，相对 V6-0107 下降 `44.78%/44.65%`，五批双项全部达标；summary/perf max abs 保持 `5.96046e-8/1.666e-8`。
- wavelets `5/5`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过。
- dlsmi：进程/全卡显存峰值=`1170/1463 MiB`，GPU P95/active median=`99%/99%`，memory util P95=`8%`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0108_pull_tDf6ukO3/`；归档/console SHA256=`e1e25f27.../6ff5cbdd...`。

## V6-0109 门禁

- V6-0108 all81 Morlet E2E/kernel=`5.56884/5.48628 ms`，perf case 为 16777216 点，summary/perf max abs=`9.77589e-7`。
- 直接把左点共轭复制到右点会因 `start + step * index` 的 float32 坐标不严格对称产生最高 `1.86211e-6` 差异，已由宿主探针否决。
- 候选每线程精确计算左点，并用右点坐标残差的一阶导数修正镜像值；phase/envelope 修正量超过 `1e-4` 时恢复右点逐点精确计算。API、坐标定义、complete correction、dtype/shape 和 schema 不变。
- 五批 Morlet full 要求 E2E/kernel 均至少下降 `20%`、至少四批双项达标且 summary/perf max abs 不高于 `9.77589e-7`；通过后运行 dlsmi、wavelets `5/5`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0109 结果

- 五批算子均 PASS，E2E/kernel 中位数=`4.04347/3.97874 ms`，相对 V6-0108 下降 `27.39%/27.48%`，五批性能门禁全部通过。
- max abs=`9.92467e-7`，比基线高 `1.4878e-8`，严格精度门禁失败；后续 dlsmi、wavelets、双任务和 all81 按止损跳过，manifest 不变。
- 不恢复后重新开始同一方向；V6-0110 直接替换镜像近似公式。证据：`/home/usr_04/CETC_garbage/cetc_v6_0109_pull_nWkkNPM4/`；归档/console SHA256=`5a398b84.../8a393726...`。

## V6-0110 门禁

- 镜像点 Gaussian 恢复原 `expf(-0.5*x*x)`，只复用左点 `cosf/sinf`；用 `phase_delta=mirror_phase+phase` 的三阶 sin、二阶 cos 小角旋转恢复镜像 phase。
- 宿主 `2^24` 点模拟中，相对原实现 max delta 从 V6-0109 的 `1.88486e-7` 降至 `1.19209e-7`，CPU RMSE 从 `1.73162e-8` 降至 `1.31729e-8`。
- 相对 V6-0108 五批 E2E/kernel 均至少下降 `5%`、至少四批达标，summary/perf max abs 不高于 `9.77589e-7`；通过后补齐 dlsmi、wavelets `5/5`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0110 结果

- 五批 Morlet 算子均通过；E2E/kernel 中位数=`4.61647/4.56155 ms`，相对 V6-0108 下降 `17.10%/16.86%`。
- max abs=`1.01152e-6`，仍高于基线 `9.77589e-7`，严格精度门禁失败；后续完整阶梯按止损跳过，manifest 不变。
- 宿主和 `gpu_04` 已恢复 V6-0108 SHA=`301bfb4e...`。证据：`/home/usr_04/CETC_garbage/cetc_v6_0110_pull_XtYAwVfm/`；归档/console SHA256=`8bf352c3.../57270da4...`。

## V6-0111 门禁

- V6-0108 all81 general Gaussian E2E/kernel=`1.89522/1.83722 ms`；perf case 为 16777216 点周期窗，`effective_size=16777217`，summary/perf max abs 均为 `1.19209e-7`。
- 对专用 power mode 在 `effective_size-1 <= 2^24` 时只计算前半区并向镜像位置写同值；通用幂和更大尺寸保留原 kernel。公共 API、公式、`p/sig/sym`、shape/dtype 和 schema 不变。
- 宿主探针覆盖五种专用 power mode、奇偶尺寸、对称窗、周期窗和 perf 尺寸，所有镜像对位级一致。
- 五批 general Gaussian full 要求 E2E/kernel 均至少下降 `20%`、至少四批双项达标且 summary/perf max abs 不高于 `1.19209e-7`；通过后运行 dlsmi、windows `23/23`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0111 交付结论

- 五批 E2E/kernel 中位数=`1.15901/1.09192 ms`，相对基线下降 `38.85%/40.57%`，五批双项全部达标；summary/perf max abs 均保持 `1.19209e-7`。
- windows `23/23`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过，最终 `overall=0`。
- dlsmi：进程/全卡显存峰值=`80/373 MiB`，GPU P95/active median=`97%/96%`，memory util P95=`2%`。
- 正式保留源码 SHA=`ac8dc47b...`。证据：`/home/usr_04/CETC_garbage/cetc_v6_0111_pull_pWosplxM/`；归档/console SHA256=`6702fb90.../8ab469ff...`。

## V6-0112 门禁

- V6-0111 all81 Parzen E2E/kernel=`1.47060/1.41345 ms`，perf case 为 16777216 点周期窗，summary/perf max abs 均为 `5.96046e-8`。
- 宿主探针覆盖奇偶尺寸、sym/periodic 和 perf 尺寸，Parzen 所有镜像对位级一致；同一探针发现 Hamming perf 尺寸有 `3635054` 对不一致，故本轮不修改 Hamming。
- 仅在 `effective_size-1 <= 2^24` 时计算前半区并向镜像位置写同值，更大尺寸保留原 kernel。公共 API、Parzen 分段公式、sym、shape/dtype 和 schema 不变。
- 五批 Parzen full 要求 E2E/kernel 均至少下降 `5%`、至少四批双项达标且 summary/perf max abs 不高于 `5.96046e-8`；通过后运行 dlsmi、windows `23/23`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0112 交付结论

- 五批 E2E/kernel 中位数=`0.850685/0.766052 ms`，相对 V6-0111 下降 `42.15%/45.80%`，五批双项全部达标；summary/perf max abs 均保持 `5.96046e-8`。
- windows `23/23`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过，最终 `overall=0`。
- dlsmi：进程/全卡显存峰值=`80/373 MiB`，GPU P95/active median=`94%/83.5%`，memory util P95=`2%`。
- 正式保留源码 SHA=`01d900e0...`。证据：`/home/usr_04/CETC_garbage/cetc_v6_0112_pull_MWIaZZGx/`；归档/console SHA256=`e330e091.../d0545dc4...`。

## V6-0113 门禁

- V6-0112 all81 Hamming E2E/kernel=`2.39096/2.31683 ms`，perf case 为 16777216 点周期窗，summary/perf max abs 均为 `1.78814e-7`。
- 禁止直接复制全部镜像值。每对按原表达式计算左点；仅当右点角度与左点角度精确互为相反数时复用左值，否则按原表达式计算右点。
- 宿主 perf 探针中 `53.05%` 镜像对可安全复用，理论 `cosf` 调用减少 `26.53%`，候选相对原实现位级差异 0。公共 API、Hamming 系数、角度公式、sym、shape/dtype 和 schema 不变。
- 五批 Hamming full 要求 E2E/kernel 均至少下降 `5%`、至少四批双项达标且 summary/perf max abs 不高于 `1.78814e-7`；通过后运行 dlsmi、windows `23/23`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0113 交付结论

- 五批 E2E/kernel 中位数=`1.39457/1.33826 ms`，相对 V6-0112 下降 `41.67%/42.24%`，五批双项全部达标；summary/perf max abs 保持 `1.78814e-7`。
- windows `23/23`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 全部通过，最终 `overall=0`。
- dlsmi：进程/全卡显存峰值=`80/373 MiB`，GPU P95/active median=`98%/96.5%`，memory util P95=`2%`。
- 正式保留源码 SHA=`cdfe138a...`。证据：`/home/usr_04/CETC_garbage/cetc_v6_0113_pull_tCyR8BFC/`；归档/console SHA256=`256d495f.../7735d038...`。

## V6-0114 门禁

- V6-0113 all81 sawtooth scalar/vector E2E/kernel=`2.90524/2.85484 ms`、`2.90156/2.85211 ms`；square scalar/vector=`2.17526/2.13152 ms`、`2.17672/2.13163 ms`。
- `positive_periodic_mod` 仅在 `-2π < t < 2π` 时跳过 `fmodf` 并直接使用 `t`；精确边界、非有限值和其余输入仍走原函数。公共 API、分段公式、shape/dtype 和 schema 不变。
- 宿主探针覆盖 `±0`、`±2π` 邻域、无穷、NaN 和 1000 万随机 float，候选与原函数位级一致；预计 sawtooth/square perf 快路径比例=`12.5%/10%`。
- 四个 scalar/vector case 分别做五批 full，要求各自 E2E/kernel 中位数至少下降 `5%`、至少四批双项达标且原误差上限不增；随后运行 dlsmi、waveforms `5/5`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0114 结果

- 十批算子均通过，sawtooth max abs 保持 `2.38419e-7`，square 保持 0；源码、构建和 manifest 门禁通过。
- sawtooth scalar/vector E2E 中位数=`3.10697/3.09865 ms`，相对基线上升 `6.94%/6.79%`；kernel=`3.06170/3.06100 ms`，上升 `7.25%/7.32%`。
- square scalar/vector E2E 中位数=`2.40293/2.40301 ms`，上升 `10.47%/10.40%`；kernel=`2.36168/2.36155 ms`，上升 `10.80%/10.79%`。完整阶梯按止损跳过，宿主和容器已恢复 SHA=`57506c4c...`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0114_pull_N4oCjThV/`；归档/console SHA256=`d817275f.../db134a02...`。

## V6-0115 门禁

- V6-0113 all81 Triang E2E/kernel=`1.09041/1.02065 ms`，perf case 为 16777216 点周期窗，summary/perf max abs=`1.19209e-7`。
- 原单点公式只依赖整数 `n` 和 `effective_size`。宿主探针检查 `45,086,714` 个镜像对，覆盖连续尺寸 2 至 4096、奇偶、sym/periodic、`2^20` 邻域和 `2^24`，全部位级一致。
- `effective_size >= 512` 时每线程计算左点一次并向镜像位置写同值，小尺寸保留原 kernel；公共 API、公式、周期截断、shape/dtype 和 schema 不变。
- 五批 Triang full 要求 E2E/kernel 均至少下降 `5%`、至少四批双项达标且 max abs 不高于 `1.19209e-7`；通过后运行 dlsmi、windows `23/23`、双任务 L1、all81、dtype、步骤和 manifest。

## V6-0115 结果

- 五批均通过；E2E/kernel 中位数=`0.777635/0.723708 ms`，相对基线下降 `28.68%/29.09%`，summary/perf max abs 保持 `1.19209e-7`。
- dlsmi 进程/全卡显存峰值=`80/373 MiB`，GPU P95/active median=`95%/77%`，显存利用率 P95=`2%`；该算子受计算和访存吞吐约束，不以扩大显存占用作为收益条件。
- windows `23/23`、Task1/Task2 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 `0/0`、manifest 不变，最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0115_manual_pull_20260715_173746/`；归档/console SHA256=`d89d275c.../2f65d934...`；源码/脚本/探针 SHA256=`2b678b48.../f1b2b094.../8ac66e2a...`。

## V6-0116 门禁

- V6-0115 all81 QMF E2E/kernel=`1.66222/1.60264 ms`，perf case 为 16777216 点，summary/perf max abs 和 RMSE 均为 0；benchmark 直接调用产品 `zx_gpu_backend::wavelets::qmf()`。
- 偶数且不少于 512 点时，一个线程处理两个输出，以一个对齐 `float2` 连续载入反序输入对并交换分量，负号仍使用原 `* -1.0f`；奇数和小尺寸走原 kernel。公共 API、QMF 定义、shape/dtype 和 schema 不变。
- 宿主探针检查 `11,535,361` 对，覆盖连续尺寸 2 至 4096、`2^20` 邻域、`2^24`、特殊值和任意 float 位模式，候选映射位级一致。
- 五批 QMF full 要求 E2E/kernel 均至少下降 `5%`、至少四批双项达标且误差保持 0；通过后运行 dlsmi、wavelets `5/5`、双任务 L1、all81、dtype、14 步和 manifest。

## V6-0116 结果

- 五批 QMF 数值均通过，summary/perf max abs 和 RMSE 均保持 0；源码和构建门禁通过。
- E2E/kernel 中位数=`1.68053/1.62071 ms`，相对基线上升 `1.10%/1.13%`；五批均未达到双项 5% 收益，dlsmi 和完整回归按止损跳过，manifest 不变。
- 宿主和容器已恢复 V6-0115 wavelets SHA=`301bfb4e...`。证据：`/home/usr_04/CETC_garbage/cetc_v6_0116_pull_lvEcKNbU/`；归档/console SHA256=`297b07c4.../5139f953...`；回退读回：`/home/usr_04/CETC_garbage/cetc_v6_0116_rollback_readback_Zp09GVa6/`。

## V6-0117 门禁

- V6-0115 all81 Lomb-Scargle E2E/kernel=`12.5364/12.2951 ms`，perf 规模为 `8192 samples × 16384 frequencies`；summary/perf max abs=`7.62939e-6/4.76837e-6`。
- `sample_count>=1024 && freq_count>=1024` 时每 block 处理相邻两个频率，两组计算共用一次 `x/y` 载入；每个频率的 range reduction、sin/cos 多项式、FMA 累加和树形归约顺序不变，小规模保留原 kernel。公共 API、参数、shape/dtype 和 schema 不变。
- 宿主结构探针对 514 个频率、每频率 2051 点比较旧/新路径，输出全部位级一致。
- 五批 Lomb-Scargle full 要求 E2E/kernel 均至少下降 `5%`、至少四批双项达标且原误差上限不增；通过后运行 dlsmi、spectral `9/9`、双任务 L1、all81、dtype、14 步和 manifest。

## V6-0117 结果

- 五批精度完全不变；summary/perf max abs=`7.62939e-6/4.76837e-6`，perf RMSE=`1.29611e-7`。
- E2E/kernel 中位数=`12.1251/11.8777 ms`，相对原基线下降 `3.28%/3.39%`，绝对节省 `0.4113/0.4174 ms`；五批均未达到双项 5%，完整阶梯按止损跳过，manifest 不变。
- 该结果超过阶段绝对节省 `0.05 ms` 有效线，但不能作为完整关闭证据；代码作为 V6-0118 中间基线保留。证据：`/home/usr_04/CETC_garbage/cetc_v6_0117_pull_tgC3PAHj/`；归档/console SHA256=`9ce3b82f.../ec592e4a...`。

## V6-0118 门禁

- 在 V6-0117 双频输入复用基础上，仅优化 pair kernel 归约同步：stride 128/64 使用 block barrier，stride 32 至 1 使用 warp 同步；加法配对、顺序和最终公式不变，小规模原 kernel 不变。
- 宿主探针对 514 个频率、每频率 2051 点比较原树和拆分同步树，输出全部位级一致。
- 仍相对 V6-0115 原始 E2E/kernel=`12.5364/12.2951 ms` 要求五批中位数下降至少 `5%`、至少四批双项达标且原误差上限不增；通过后运行 dlsmi、spectral `9/9`、双任务 L1、all81、dtype、14 步和 manifest。

## V6-0118 结果

- 五批 E2E/kernel 中位数=`11.5651/11.3009 ms`，相对原始基线下降 `7.75%/8.09%`，五批全部达标；summary/perf max abs=`7.62939e-6/4.76837e-6`、perf RMSE=`1.29611e-7`，均与基线相同。
- dlsmi 进程/全卡显存峰值=`48/341 MiB`，GPU P95/active median=`99%/99%`，显存利用率 P95=`2%`。
- spectral `9/9`、Task1/Task2 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 `0/0`、manifest 不变，最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0118_pull_KpgvCsbF/`；归档/console SHA256=`64e3b1ce.../2d20b7dd...`；源码/探针/脚本 SHA256=`145cebbd.../267b8dd2.../5c656598...`。

## V6-0119 门禁

- V6-0118 all81 vectorstrength E2E/kernel=`9.19509/9.09648 ms`，perf 为 1048576 events、64 periods、每 period 1024 个 partial blocks；summary/perf max abs=`4.76837e-6`。
- partial kernel 的 stride 128/64 保留 block barrier，stride 32 至 1 改为首 warp 同步；角度、多项式、Kahan 累加、树形加法配对/顺序、partial 布局和 finalize kernel 不变。公共 API、shape/dtype 和 schema 不变。
- 宿主探针对 `100000 × 256` 组随机实/虚部分和比较原树与拆分同步树，全部位级一致。
- 五批 vectorstrength full 要求 E2E/kernel 均至少下降 `5%`、至少四批双项达标且原误差上限不增；通过后运行 dlsmi、spectral `9/9`、双任务 L1、all81、dtype、14 步和 manifest。

## V6-0119 结果

- 五批 E2E/kernel 中位数=`6.91468/6.85419 ms`，相对 V6-0118 下降 `24.80%/24.65%`，五批全部双项达标；summary/perf max abs=`4.76837e-6`、perf RMSE=`1.45348e-6`，与基线相同。
- dlsmi 进程/全卡显存峰值=`48/341 MiB`，GPU P95/active median=`99%/99%`，显存利用率 P95=`2%`。
- spectral `9/9`、Task1/Task2 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 `0/0`、manifest 不变，最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0119_pull_z8Fq9IMg/`；归档/console SHA256=`4cc82317.../bd2886f0...`；源码/探针/脚本 SHA256=`b564d301.../943ae4d5.../878b3389...`。

## V6-0120 门禁

- 只在 vector-period 且 `blocks_per_period >= 256` 时用双 period block；每线程按原 sample 顺序独立执行两组 angle/poly 与 Kahan 累加，四路 shared 归约共用同步。奇数尾 period、scalar 和小规模调用原 kernel。
- 各 period 的运算、Kahan、加法树、partial 布局和 finalize 不变。宿主探针覆盖 `255/256/257/1024` blocks、`3/7/64/65` periods 和奇数尾路径，共比较 `107,582` 个 partial，实/虚部位级差异 0。
- 以 V6-0119 E2E/kernel=`6.91468/6.85419 ms` 为分母。强门禁要求双指标至少下降 `5%`且至少四批达标；稳定有效门禁要求双指标至少下降 `2%`、绝对各省至少 `0.1 ms`且至少四批均改善。任一性能门禁通过后仍须完成 dlsmi、spectral `9/9`、双任务 L1、all81、dtype、14 步和 manifest。

## V6-0120 结果

- 五批 E2E/kernel 中位数=`6.30728/6.22170 ms`，相对 V6-0119 下降 `8.78%/9.23%`，五批均达到强门禁；summary/perf max abs=`4.76837e-6`、perf RMSE=`1.45348e-6`，与基线相同。
- dlsmi 进程/全卡显存峰值=`48/341 MiB`，GPU P95/active median=`99%/99%`，显存利用率 P95=`2%`。
- spectral `9/9`、Task1/Task2 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 `0/0`、manifest 不变，最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0120_pull_LLiLdYQj/`；归档/console SHA256=`e28e75dd.../ae2076ce...`；源码/探针/脚本 SHA256=`9c49e696.../9dc2eae3.../ba01a040...`。

## V6-0121 门禁

- V6-0120 all81 channelize_poly E2E/kernel=`26.5569/26.4035 ms`，perf 为 1048576 complex samples、97 taps、8 channels；max abs/RMSE=`1.26441e-6/3.3783e-7`。
- 8 通道且不少于 256 points 时，每线程负责一个 point：每个 phase 的 polyphase accum 仅计算一次，再按原 phase 顺序更新 8 个 channel；block 内 64 个 twiddle 仍用原 GPU 表达式生成后 shared 复用。其他 shape 使用原 kernel。
- 宿主探针覆盖 4/8 通道、`255/256/257` point 边界、5 档 tap 长度和尾部输入，共比较 `194,680` 个 complex 输出，位级差异 0。
- 强门禁要求五批 E2E/kernel 均至少下降 `20%`且至少四批达标；稳定有效门禁要求双指标至少下降 `5%`、绝对各省至少 `1 ms`且至少四批达标。任一通过后仍须完成 dlsmi、filtering `17/17`、双任务 L1、all81、dtype、14 步和 manifest。
- 产品测试钩子直接比较实际 generic/point kernel：126 例、`1,471,492` 个 complex 输出逐实部/虚部 bitwise 相等；覆盖阈值边界、5 档 taps、0 至 7 尾样本、非 8 通道回退和主规模。
- `256/257/512/1024/4096/16384/131072` 七档阈值 sweep 均须至少 4/5 批 E2E/kernel 同时改善 `0.5%`；主规模五批还锁定 RMSE/mixed/max relative=`3.3783e-7/5.85883e-5/0.00105172` 上限。Owner、Standards、Spec 审查无阻断。
- 目标设备结果：126 例逐位 A/B 全过，七档均为 5/5 批双项收益；主规模五批 E2E/kernel=`2.35314/2.19482 ms`，下降 `91.14%/91.69%`，四项误差与基线相同。dlsmi 进程/全卡峰值=`82/375 MiB`，filtering `17/17`、双任务 L1、all81 `81/81`、dtype/14 步缺口 0、manifest 不变，最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0121_pull_IMQ2qIKm/`；归档/console SHA256=`b20efba6.../aecb1b46...`。ZQ500 无可用 sanitizer，记录为非阻塞残余风险。

## V6-0122 门禁

- 基线：`filtering/firfilter2` E2E/kernel=`6.22077/6.11656 ms`，31 taps、1048576 点；max abs/RMSE/mixed/max relative 上限=`5.36442e-7/6.42205e-8/8.90312e-7/0.00116693`。
- 候选保留 padding 和 forward FIR，将 `reverse -> backward FIR -> reverse -> crop` 等价合并为 `sum b[t]*forward[min(edge+i+t,P-1)]`，直接写最终输出；自动路径仅覆盖 31 taps、单连续行且不少于 65536 点。
- 宿主 probe 覆盖四种 pad、6 档 taps、15 档尺寸和多种 edge，共 792 例、`246252` 个输出，位级差异 0。实际设备测试另覆盖多轴/跨步、负 axis、显式 `padlen=0`、`65535/65536/65537` 和主规模，并读取测试钩子确认真实选路。
- 阈值 sweep 对 `65536/65537/262144/1048576` 要求至少 4/5 批 E2E/kernel 同时改善 `0.5%`；正式五批使用正常 auto 路径，相对固定基线要求双指标至少下降 `5%`、绝对各省至少 `0.25 ms`且至少四批达标，中位数也须通过。
- 通过后运行 dlsmi、filtering `17/17`、Task1/Task2 L1、all81 `81/81`、dtype、14 步和 manifest；失败恢复 V6-0121 产品/测试 SHA=`dbf37a0c.../d909f08c...`。

## V6-0122 结果

- 宿主公式 probe 792 例、`246252` 个输出位级相等；设备 A/B 13 例、`1,319,181` 个输出位级相等，实际 crossover=`65536`，四档有效尺寸均为 5/5 批双项收益。
- 正常 auto 路径五批 E2E/kernel 中位数=`5.66339/5.56020 ms`，相对固定基线下降 `8.96%/9.10%`，绝对节省 `0.55738/0.55636 ms`；max abs/RMSE/mixed/max relative 与基线完全相同。
- dlsmi 进程/全卡峰值=`194/487 MiB`，GPU P95/active median=`99%/98%`；filtering `17/17`、双任务 L1、all81 `81/81`、dtype/14 步缺口 0、manifest 不变，最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0122_pull_bR9Cqdyh/`；归档/console SHA256=`22ecb495.../3cbda162...`；产品/测试/探针/脚本 SHA256=`6f814c87.../460dc6fb.../1649e901.../4dad447d...`。ZQ500 无可用 sanitizer，记录为非阻塞残余风险。

## V6-0123 门禁

- 基线：`filtering/resample` E2E/kernel=`6.93087/6.85412 ms`；perf 为 1048576 点时域输入重采样到 1572864 点并使用 Hann window。
- 候选仅融合 inverse FFT 前的 output 清零、低频复制和高频复制；偶数 Nyquist 下采样相加、上采样折半和镜像必须与原链路逐位一致。FFT、window、axis/domain、输出和公共接口不变。
- 自动路径仅覆盖单连续行、time/Hann、`1048576 -> 1572864`；其他配置保留旧调度。宿主映射 probe 覆盖上/下/等长、奇偶尺寸和 Nyquist 边界；设备 generic/fused A/B 覆盖极小尺寸、跨步/负 axis、time/freq、workspace 大小交替和双向主规模，并读取实际选路。
- 主自动尺寸强制 sweep 要求至少 4/5 批 E2E/kernel 同时下降 `0.5%`；正常 auto 五批要求 E2E/kernel 各自下降至少 `5%`或绝对节省至少 `0.05 ms`，至少四批达标且四项误差不增，随后进入完整阶梯。

## V6-0123 结果

- 设备 generic/fused/auto A/B 共 20 例、`2,626,285` 个 float 输出，全部位级相等；auto route 仅正式 perf 配置选中 fused，其他 case 均保持 generic。主规模强制 sweep 4/5 批达到 E2E/kernel 同时下降 `0.5%`。
- 正常 auto 五批 E2E/kernel 中位数=`6.82613/6.74654 ms`，相对固定基线下降 `1.51%/1.57%`，绝对节省 `0.10474/0.10758 ms`，五批均通过 `5%`或绝对 `0.05 ms`门禁；四项误差保持 `8.34465e-7/1.50331e-7/4.73612e-5/0.0900481`。
- dlsmi 进程/全卡峰值=`118/411 MiB`，GPU P95/active median=`99%/99%`；filtering `17/17`、Task1/Task2 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 `0/0`、manifest 不变，最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0123_pull_2hkLZTFg/`；归档/console SHA256=`eb070456.../675157c9...`；产品/测试/探针/脚本 SHA256=`701abfdb.../59041422.../bb496fcd.../a5b7be18...`。ZQ500 无可用 sanitizer，记录为非阻塞残余风险。

## V6-0124 门禁

- 固定分母为 V6-0123 正常 auto 五批中位数 `6.82613/6.74654 ms`，精度上限保持不变。
- 候选把已有 Hann `apply_window_fftshift` 与 fused pack 合并；每个被复制源 bin 仍先乘原 window 值，再执行原 Nyquist 折半或相加。FFT、窗生成/cache、输出和公共接口不变。
- 宿主 probe 必须覆盖 no/direct/fftshift 三种窗模式及奇偶上/下/等长；设备强制 pack/windowed-pack 必须逐位一致并读取实际路径。主规模至少 4/5 批 E2E/kernel 同时下降 `0.5%`，正常 auto 五批再按 `5%`或绝对 `0.05 ms`及完整阶梯决定保留或回退。

## V6-0124 结果

- 21/21 源指纹、3954 例宿主位级 probe 和 Release 增量构建通过。
- 设备 A/B 进程 SIGSEGV，四个 A/B 输出文件均为 0 字节；性能、sanitizer、dlsmi、filtering、双任务、all81、dtype 和 14 步均未运行，不登记任何收益。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0124_pull_SKAZgh5i/`；归档/console SHA256=`409b96d7.../3f7e5b21...`，最终 `overall=1`。

## V6-0125 诊断门禁

- 只修改专项测试诊断入口，产品算法、API、auto 条件和标准报告 schema 不变；trace 与 case selector 默认关闭。
- 完整 correctness trace 必须在 SIGSEGV 前落盘具体 case/path/API 阶段；随后在新进程隔离最后 case，并以官方 case 25 为参考。单 case 通过时再禁 device storage cache 运行全量对照。
- 本轮只形成崩溃归因，不形成性能收益；定位后再决定修复 V6-0124 或恢复 V6-0123。

## V6-0125 结果

- 完整 trace 中 case 1-26 的 104 条路径全部结束；官方 case 25 `1048576 -> 1572864` 的 generic/pack/windowed/auto observed=`0/1/2/2`，独立运行 `rc=0`。
- case 27 `1048576 -> 1572863` 在首个 generic `before_call` 后 `rc=139`；新进程隔离仍为 `139`，因此不是 windowed-pack、显式 device window 生命周期或跨 case 累计状态。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0125_pull_gY4xEmdG/`；归档/console SHA256=`4e5c2018.../fe913146...`。再次取回固定别名的 mtime、大小和 SHA 完全相同，没有新的 V6-0126 运行结果。

## V6-0126 门禁

- auto scope 使用一个生产 predicate；独立 host-only 表以字面 expected 覆盖 exact、`num±1`、`input±1`、freq、Hamming、multiline 和 stride，不创建 device array，也不调用 `resample`。
- 动态 A/B 保留官方 exact、平滑 auto-negative、奇偶升降采样、named/explicit window、空/错长 window、multiline/stride、negative-axis 和 freq；仅删除四个只验证路由边界且会触发大非平滑 FFT 的 case。
- 正式验证前，独立 dlFFT 子进程逐一观察四个 `N±1/M±1` 路由边界；`1048576/1572864` 必须完整通过，`1572863` 必须在 `cufftPlan1d` 内以 `139` 退出。正式脚本复核归档内 source/script SHA、原始 RC 和 marker；若不满足，停止并恢复 V6-0123。
- 归因通过后仍执行 3954 例宿主位级 probe、31 case 四路径设备 A/B、五批固定分母性能、filtering `17/17`、双任务 L1、all81 和 manifest，并硬断言 dtype missing=0、calculation steps=14、timing/accuracy gap=0；结果未回来前不登记收益。

## V6-0126 结果

- 前置 probe source SHA 通过；单条 `dlcc -x cuda source libraries...` 命令使 `.so` 仍处于 CUDA 语言模式，`libcurt.so` 被当源码解析，build=`1`。
- 六个 FFT case 均未启动，RC 全为 `99`；正式验证按前置门跳过，因此没有 correctness、性能、all81、dtype 或 14 步结果，不登记收益也不回退产品候选。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0126_pull_I9jw4SkC/`；FFT archive/console SHA256=`5f2c4437.../6c3b9304...`。

## V6-0127 门禁

- 只把 standalone probe 拆为 `.cu -> .o` 编译和无 `-x cuda` 的链接，分别记录 compile/link/build RC；其余产品、测试和门禁不变。
- 正式脚本绑定 V6-0127 probe source/script SHA，并要求 compile/link 均为 0 后再验六 case 原始 RC 与 marker；失败仍禁止进入正式性能链路。
- compile/link/build 均为 0；六个 FFT RC 为 `0/255/139/0/139/139`，smooth 两例完整通过，`1572863` 的 plan 崩溃归因通过。
- `1048575` 已完成 plan 并进入 exec，随后因 16 MiB local-memory 资源超限和 Driver 0701 返回 `255`；旧 coverage RC 白名单未包含该已分类结果，aggregate=`1`，正式验证按门禁未运行。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0127_pull_XrpFzRkV/`；archive/console SHA256=`70e36db1.../906e6dc1...`。本轮不形成 correctness、性能或回归结论。

## V6-0128 门禁

- 产品、测试、公式 probe、六个 FFT size、V6-0123 固定分母和完整回归均不变，只修边界“已观察”判据。
- 每个边界必须到达 `before_plan`；正常、plan 错误、exec 错误、清理错误、SIGSEGV 和 Driver 0701 分别绑定对应阶段 marker，未运行、timeout 或无分类的 `255` 均失败。
- 真实 V6-0127 归档回放结果为 legacy=`1`、candidate=`0`；删除 `before_plan`、删除 0701、伪造 timeout/未运行或无非零清理 marker 的 `40` 均为 `1`，`1572863` 严格归因仍为 `0`。
- Filtering Owner、Standards、Spec、Evidence Guard 均 PASS；六个冻结文件已同步 `gpu_04` 且回读 SHA 一致，证据为 `/home/usr_04/CETC_garbage/cetc_v6_0128_deploy_readback_U3YUo17T/`。当前状态为待验证，不登记性能收益。
- 容器前置与正式状态全部为 0。五批 resample E2E/kernel 中位数=`6.65073/6.57236 ms`，相对固定分母下降 `2.57%/2.58%`，绝对节省 `0.17540/0.17418 ms`，四项精度不变。
- 31 case 设备 A/B 检查 `13,636,398` 个 float 输出，auto route、4 个非法窗口、主尺寸收益均通过；dlsmi 进程/全卡峰值=`118/411 MiB`、GPU P95/active median=`99%/99%`。
- filtering `17/17`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 均通过。证据：`/home/usr_04/CETC_garbage/cetc_v6_0128_pull_qG4DQ8fB/`，FFT archive/console SHA=`91c64800.../f3399df0...`，formal archive/console SHA=`d840479c.../b8fcb2b0...`。

## V6-0129 门禁

- host probe、构建、17 case 设备位级 A/B 和五批数值门均通过。
- 五批 E2E=`19.8962/19.9574/19.9979/20.0207/19.9467 ms`，kernel=`19.8011/19.7984/19.8701/19.7848/19.8461 ms`。
- 中位数相对固定分母仅下降 `0.43%/0.30%`，双项有效批次为 `2/5`，性能门禁失败；dlsmi、双任务、spectral、all81、dtype 和 14 步按止损未运行。
- 已恢复 V6-0128 STFT 路径。证据：`/home/usr_04/CETC_garbage/cetc_v6_0129_pull_rXJ3db5p/`；归档/console SHA=`4bbe4175.../39e1dd85...`。

## V6-0130 结果

- packed-C2C 试图用一次复数 FFT 重建两路实数 FFT 后的交叉谱。
- host probe 在 nfft `128/256`、pattern/random 输入上最大差异=`9.87377646e-8`、RMSE=`6.73709391e-9`，超过当前 CSD perf max abs=`9.31323e-10` 两个数量级。
- 未修改产品或测试。证据：`/home/usr_04/CETC_garbage/cetc_v6_0130_csd_packed_probe.{cpp,log}`，SHA=`f0f041a4.../174e8929...`。

## V6-0131 门禁

- 目标为 CSD constant detrend 的调度固定开销，不改两路输入、去均值归约、窗乘、FFT 数学、交叉谱、缩放、输出布局、API、dtype 或 schema。
- paired kernel 以 `2*nseg` 个 block 把 x/y 分段顺序写入同一连续 workspace；单个 `batch=2*nseg` C2C exec 替代两次 `batch=nseg` exec。
- auto 只覆盖官方一维 `[1048576]`、`axis=-1` perf exact；其余 shape/axis、two-sided、spectrum/median、boxcar、host/device explicit window 和非 constant detrend 均保持 generic。12 case 设备 A/B 必须逐位一致。
- 固定基线 E2E/kernel=`18.8581/18.7915 ms`；五批中位数和至少四批均须满足双项下降 `5%`或绝对各省 `0.05 ms`，六项误差不得高于 V6-0128。
- host probe 已通过 6 组、`4,309,248` 个 complex 输出和 10 项 route；产品/测试/probe/script SHA=`6880da1c.../7fc39675.../60f5d305.../ff240705...`。容器通过后再登记收益。
- 四个部署文件已同步 `gpu_04` 并回读逐字节一致。证据：`/home/usr_04/CETC_garbage/cetc_v6_0131_final_readback_kmhIjc/`。

## V6-0131 结果

- source、host probe、构建、12 case 设备位级 A/B、sanitizer 和五批数值均通过。
- 五批 E2E/kernel 中位数=`18.8101/18.7213 ms`，相对固定分母仅下降 `0.2545%/0.3736%`，绝对节省 `0.0480/0.0702 ms`；双项达标批次仅 `1/5`。
- 性能门失败，dlsmi、双任务、spectral、all81、dtype 和 14 步按止损跳过；产品和测试已恢复 V6-0128 行为。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0131_pull_WEsgfs/`；归档/console SHA=`b09c0b3e.../f8743258...`。

## V6-0132 门禁

- V6-0128 all81 periodogram E2E/kernel=`0.623577/0.192984 ms`，kernel 外固定开销=`0.430593 ms`。
- 同配置重复调用复用命名窗口 device storage、scale 和频率轴；host/device explicit window 不缓存。FFT、detrend、窗乘、PSD、输出布局、API、dtype/shape 和 schema 不变。
- 设备 A/B 覆盖 9 case、`41,489` 个 float 输出；bypass、首次 miss、再次 hit 和 auto 输出必须逐位相等。
- 五批 paired 对照要求 E2E 中位数和至少 4/5 批下降 `5%`或绝对 `0.05 ms`，kernel 中位数和至少 4/5 批不得退化超过 `3%`或 `0.01 ms`；数值误差不得高于 V6-0128。
- 产品/测试/probe/script SHA=`266e2879.../b07d8c45.../7f2c8e19.../7f0eb637...`；宿主 probe 和性能门正反回放已通过，四个文件同步 `gpu_04` 后回读一致。部署证据：`/home/usr_04/CETC_garbage/cetc_v6_0132_final_readback_72R5IyIK/`。

## V6-0132 交付结论

- 五批 bypass/candidate E2E 中位数=`0.659052/0.387250 ms`，下降 `41.24%`、绝对节省 `0.271802 ms`；kernel=`0.192644/0.192576 ms`。
- 9 case 设备 A/B 检查 `41,489` 个 float 输出，7 miss、14 hit、15 bypass，全部逐位相等；五批数值误差完全不变。
- dlsmi 进程/全卡峰值=`32/325 MiB`、GPU P95/active median=`82%/78%`；spectral `9/9`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 均通过。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0132_pull_nnPZz14Q/`；归档/console SHA=`0726980a.../ee687f65...`，最终 `overall=0`。

## V6-0133 门禁

- V6-0132 all81 Welch E2E/kernel=`0.928063/0.609520 ms`，kernel 外固定开销=`0.318543 ms`。
- 同配置重复调用复用命名窗口 device storage、scale 和频率轴；host/device explicit window 不缓存。FFT、分段、detrend、average、PSD、API、dtype/shape 和 schema 不变。
- spectral cache key 的 float 字段改用 float32 位模式，消除 `std::to_string` 六位小数导致的近邻参数碰撞；相邻 `fs` 必须表现为 miss、随后同值 hit。
- 设备 A/B 覆盖 12 case、`2519` 个 float 输出；预期 11 miss、19 hit、18 bypass。五批 paired E2E 中位数和至少 4/5 批须下降 `5%`或绝对 `0.05 ms`，kernel 不得退化超过 `3%`或 `0.01 ms`。
- 产品/测试/probe/script SHA=`30a5164f.../85f00ef2.../43b5e596.../2650b5d9...`；宿主 probe、源码指纹和性能门正反回放已通过，四个文件同步 `gpu_04` 后回读一致。部署证据：`/home/usr_04/CETC_garbage/cetc_v6_0133_final_readback_jF1cnbC1/`。

## V6-0133 交付结论

- 五批 bypass/candidate E2E 中位数=`0.951467/0.792062 ms`，下降 `16.75%`、绝对节省 `0.159405 ms`；kernel=`0.629814/0.613350 ms`，下降 `2.61%`。
- 12 case 设备 A/B 检查 `2519` 个 float 输出，11 miss、19 hit、18 bypass，全部逐位相等；宿主精确 key probe 为 `14/31/5`，五批数值误差完全不变。
- dlsmi 进程/全卡峰值=`48/341 MiB`、GPU P95/active median=`90%/89%`；spectral `9/9`、双任务 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 均通过。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0133_pull_wFBuJquz/`；归档/console SHA=`e0302da3.../f8f3382c...`，最终 `overall=0`。

## V6-0134 门禁

- V6-0133 all81 ISTFT E2E/kernel=`0.663961/0.216292 ms`，kernel 外固定开销=`0.447669 ms`。
- 同配置重复调用复用命名/参数窗口 device storage、按旧 D2H 累加顺序得到的窗口和，以及 `(输出长度, fs)` 时间轴；host/device explicit window 和强制 bypass 完整走旧路径。
- FFT、单/双边谱准备、inverse plan、overlap-add、workspace 清零、API、dtype/shape 和 schema 不变；本轮不混入 `fft_full.zero` 消除或 kernel 修改。
- 设备 A/B 覆盖 12 case、`26432` 个 float 输出，预期 12 miss、18 hit、18 bypass；覆盖官方 accuracy/perf、单双边、boundary、padding、Kaiser、默认长度、多行、显式窗口、相邻 `fs` 和窗口切换。
- 五批 paired E2E 中位数和至少 4/5 批须下降 `5%`或绝对 `0.05 ms`，kernel 中位数和至少 4/5 批不得退化超过 `3%`或 `0.01 ms`；四项误差不得高于 V6-0133。
- 宿主 probe `PASS key_checks=11 route_checks=34 exact_float_checks=4`；21 项源码指纹、Bash 语法和性能门正反回放已通过。产品/测试/probe/script SHA=`aaca8a89.../52c61be6.../124d9952.../4317e312...`，回退副本为 `/home/usr_04/CETC_garbage/cetc_v6_0134_before_j89Ttw/`。

## V6-0134 首轮结果

- source、host probe、Release 构建和 12 case 设备 A/B 全部通过；检查 `26432` 个 float 输出，12 miss、18 hit、18 bypass，均逐位相等。平台无 sanitizer，按非阻塞规则记录。
- 五批 bypass/candidate E2E 中位数=`0.642347/0.506345 ms`，下降 `21.17%`、绝对节省 `0.136002 ms`，5/5 批达到收益门；四项误差完全不变。
- kernel 中位数=`0.216106/0.215390 ms`，下降 `0.33%`；第 1、4 批候选分别抖动至 `0.241040/0.256682 ms`，稳定批次为 `3/5`，低于预设 `4/5`，因此 `overall=1`。dlsmi、双任务、spectral、all81、dtype 和 14 步按门禁未运行。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0134_pull_In5PxwuL/`；归档/console SHA=`83dc8c1c.../45552459...`。不修改产品和门限，确认脚本改用 `warmup 10/repeat 100` 后重跑同一门禁，SHA=`e23a2710...`；容器同步回读证据为 `/home/usr_04/CETC_garbage/cetc_v6_0134_confirm_readback_KJpI5ha3/`。

## V6-0134 交付结论

- 增采样确认五批 bypass/candidate E2E 中位数=`0.682767/0.473596 ms`，下降 `30.64%`、绝对节省 `0.209171 ms`，五批全部达到原收益门。
- kernel 中位数=`0.214966/0.206278 ms`，下降 `4.04%`，稳定批次=`4/5`；未降低门限。max abs/RMSE=`1.49012e-6/2.31522e-7`，与 bypass 一致。
- 12 case 设备 A/B 检查 `26432` 个 float 输出，12 miss、18 hit、18 bypass，全部逐位相等；host key/route/float probe=`11/34/4`。
- dlsmi 进程/全卡显存峰值=`48/341 MiB`，GPU P95/active median=`78%/74%`；spectral `9/9`、Task1/Task2 L1、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 和源码指纹全部通过，最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0134_confirm_pull_eYnWMNuO/`；归档/console SHA256=`de092e941d9d956c5047f5b069b6a59a869bd4863c76f5a00d5260081babea49/acbd653a7d8be8d9c121a237b8b8f60fd6f362bcc7fab8ddad1195267313db`。

## V6-0135 V6.7 收束结论

- V6.7 共正式保留 21 个方向，覆盖 windows、waveforms、wavelets、spectral 和 filtering；性能失败、严格精度失败或平台无收益的候选均已回退或暂缓。
- 最终 all81 热点中，`ambgfun/cwt/stft/csd` 等属于任务已深化链路或 FFT/算法主体；`unit_impulse` 等小算子主要受单次 launch/setup 固定开销限制；其余项低于轻度优化有效线或需要改变缓存生命周期语义。
- 继续深挖上述方向将进入算法重写、跨调用生命周期或任务专项范围，不属于 V6.7 的低风险轻度优化。阶段不以降低精度、兼容性、API/schema 或有效性能线换取关闭。
- V6.7 已关闭，V6.8 进入条件已满足；下一步执行最终同源码全量回归、Task1/Task2 L1-L6 性能终测和报告收束。
