# 可量化优化亮点

下表只收录历史台账中同时存在明确 GPU 优化前后耗时、正确性结果、台账编号和当前源码
路径的条目。倍率统一为“优化前 GPU E2E / 优化后 GPU E2E”，不是 CPU/GPU 加速比；单位均为
历史报告中的 ms。完整上下文见 [`history/PROJECT_LEDGER.md`](history/PROJECT_LEDGER.md)。

| 算子/任务 | 原始瓶颈 | 优化方法 | 优化前 GPU E2E | 优化后 GPU E2E | GPU 前后倍率 | 正确性结果 | 当前代码位置 | 历史依据 |
| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |
| `filtering/filtfilt` | 高阶递推串行依赖与重复中间数组 | BA 转单节 SOS，前后向递推复用 prefix-scan 路径 | 909.940 | 0.679 | 1339.5x | PASS；历史报告通过 | `src/zhongkexin/filtering.cu` | V5-0054，`history/PROJECT_LEDGER.md` |
| `filtering/lfilter` | BA 形式递推代价高、状态更新串行 | SOS fast path，保留通用 fallback | 455.170 | 0.359 | 1267.9x | PASS；历史报告通过 | `src/zhongkexin/filtering.cu` | V5-0054，`history/PROJECT_LEDGER.md` |
| `spectral/periodogram` | 传统流程存在 R2C 计算、去趋势和 PSD 中间写回 | R2C FFT，constant detrend 与 PSD 输出融合 | 72.910 | 0.669 | 108.97x | PASS；历史报告通过 | `src/zhongkexin/spectral.cu` | V5-0056，`history/PROJECT_LEDGER.md` |
| `filtering/wiener` | 邻域窗口重复全局访存 | 16×16 shared-memory tiled stencil，块内复用 halo | 214.436 | 3.500 | 61.27x | PASS；历史报告通过 | `src/zhongkexin/filtering.cu` | V5-0003，`history/PROJECT_LEDGER.md` |
| `windows/general_gaussian` | 每个输出点重复 `powf` 与参数数学计算 | 常见整数/半整数幂展开，参数在 host 侧预计算 | 5.824 | 0.206 | 28.27x | PASS；`mixed_error=0` | `src/zhongkexin/windows.cu` | V5-0036，`history/PROJECT_LEDGER.md` |
| `windows/general_cosine` | 系数 H2D、通用系数循环与 extended workspace copy | 固定 1–5 系数 direct kernel，直接写最终输出 | 5.970 | 0.451 | 13.24x | PASS；`mixed_error=0` | `src/zhongkexin/windows.cu` | V5-0037，`history/PROJECT_LEDGER.md` |
| `windows/taylor` | 固定系数仍走通用分发和中间 workspace | 1–8 系数 direct kernel，系数作为 kernel 参数 | 5.938 | 0.565 | 10.51x | PASS；`mixed_error=0` | `src/zhongkexin/windows.cu` | V5-0038，`history/PROJECT_LEDGER.md` |
| `spectral/lombscargle` | 频点×样本三角函数计算占主导 | 角度归一化与多项式 sin/cos，保留归约结构 | 31.708 | 12.546 | 2.53x | PASS；`mixed_error=9.62346e-06` | `src/zhongkexin/spectral.cu` | V5-0039，`history/PROJECT_LEDGER.md` |
| `radartools/ambgfun` | 大二维输出、批量 FFT 与矩阵构造写零 | 自适应 tile、非零区域构造 kernel，减少无效写入 | 175.956 | 167.896 | 1.05x | PASS；`mixed_error=0` | `src/zhongkexin/radartools.cu` | V5-0040，`history/PROJECT_LEDGER.md` |
| `spectral/csd` | 每个 segment 重复扫描求均值 | C2C constant-detrend segment block 归约后直接填充 FFT 输入 | 3.019 | 0.865 | 3.49x | PASS；`mixed_error=8.11127e-08` | `src/zhongkexin/spectral.cu` | V5-0041，`history/PROJECT_LEDGER.md` |
| `bsplines/gauss_spline` | 点函数复用通用 detail 公式，设备端重复数学运算 | float helper，host 侧预计算归一化常量 | 3.366 | 0.178 | 18.91x | PASS；`mixed_error=0` | `src/zhongkexin/bsplines.cu` | V5-0042，`history/PROJECT_LEDGER.md` |
| `wavelets/ricker` | 每个点重复计算与宽度无关的常量 | host 预计算幅值和倒数平方，kernel 保留逐点运算 | 55.834 | 1.812 | 30.81x | PASS；`mixed_error=0` | `src/zhongkexin/wavelets.cu` | V5-0031，`history/PROJECT_LEDGER.md` |

本表不包含只有 CPU/GPU 对比、没有 GPU 版本前后成对数据的记录；新增当前报告后，
应把最新六规模数据与本表分开，不覆盖历史值。
