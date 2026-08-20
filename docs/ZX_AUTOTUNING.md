# 中科芯 C500 全量离线自动调优

## 运行方式

自动调优是显式执行的离线流程，不在生产算子调用中 benchmark，也不做 JIT：

```bash
cmake --build build-zx --target zx_operator_autotune
```

该 target 依赖 `tests/unit` 中已配置的算子测试程序，并通过
`scripts/performance.sh` 使用冻结基线逐候选运行。注册表覆盖
`tests/contracts/operator_sets.json` 的 `task_appendix` 53 个算子、L1-L6 六个精确
规模，并额外覆盖 Task1/Task2 的 12 个任务 workload。当前正式运行使用
`candidate-profile=two_day`，dry-run 展开 609 个算子候选组合和 9 个任务候选组合；
其中没有安全并行变体的算子会显示明确的 static-only 原因，不会
伪造参数。正式流程是筛选 `warmup=2/repeat=5`、每个 exact key 前 3 名加静态路径
的 `warmup=5/repeat=30`、再对正式第一名和静态路径进行同协议复核；只有复核仍更快
的候选才写入 cache。结果目录按 `operator_screening/`、`operator_formal_top3/`、
`operator_winner_against_static/`、对应的 `task_*` 目录分开保存，最终查表 cache
和 Auto/Static 报告位于外部运行目录。

可恢复执行器还维护 `manifest.json`、`status.json`、`heartbeat.json`、`lock/`、
`state/`、`results/`、`cache/` 和 `logs/`；每个候选的六个精确规模分别记录状态，
同一 `--state-root --resume` 会跳过已通过的候选。

也可以直接运行脚本：

```bash
python3 scripts/zx_operator_autotune.py \
  --scope all \
  --operator-set task_appendix \
  --candidate-profile two_day \
  --frozen-baseline data/baseline \
  --state-root /path/to/CETC_runs/zq500_autotune_appendix53_v5/state \
  --output-root /path/to/CETC_runs/zq500_autotune_appendix53_v5/reports \
  --cache-output data/tuning/zx_tuning.json \
  --resume \
  --warmup 5 --repeat 30 --skip-cpu-timing \
  --selection-validation winner-against-static

# 只跑一个精确算子的全部候选，适合先做 L1/L3/L6 代表性验证
python3 scripts/zx_operator_autotune.py \
  --operator waveforms/chirp \
  --frozen-baseline data/baseline \
  --output-root data/reports/autotune/tuning_runs_chirp \
  --cache-output data/tuning/zx_tuning.json
```

每个候选按 L1-L6 执行 `warmup=5/repeat=30`，报告必须同时满足：

- GPU E2E median 可用；
- accuracy case 通过；
- `InputRefreshRun` 通过；
- 对适用 workload 候选实际生效；shape/semantic/resource 不满足时允许记录为
  `candidate_applied=false`，但该结果不得进入 cache；
- workspace 记录可用。

第一轮只产生临时胜者；第二轮把临时胜者与静态策略按相同协议重新比较。每个精确
key 只有在第二轮候选比静态策略更快且全部检查通过时写入缓存。没有收益或复核
失败的 key 不写入，运行时自然回退静态策略。

## 运行时查表

默认不启用 Auto，因此现有静态策略不变。启用 Auto 后，仓库脚本会自动读取
`data/tuning/zx_tuning.json`；也可以显式指定同一个仓库内路径：

```bash
export CUSIGNAL_ZX_TUNING_MODE=auto
export CUSIGNAL_ZX_TUNING_CACHE="$PWD/data/tuning/zx_tuning.json"
```

运行时使用完整 shape、语义参数、dtype/layout、设备指纹和 registry version
`zx-c500-appendix53-task-v5` 精确匹配。关闭缓存、cache miss、JSON 损坏、设备不匹配、候选
配置不合法或 workspace 不满足时，均回退静态策略；不会在线测量或写回缓存。

调试/验证可使用：

```bash
export CUSIGNAL_ZX_TUNING_MODE=force
export CUSIGNAL_ZX_TUNING_FORCE='ca_cfar=ca_cfar_tiled_t256_e512'
```

`force` 只接受注册表中的候选 ID，不能注入任意整数。`CUSIGNAL_ZX_TILE_PATH=legacy` 及现有算子 legacy 开关优先级更高。

## 候选范围

- CA-CFAR：legacy、128/256/512 threads 的 tiled row scan；扫描 footprint 为 128、512、1024。
- Pulse Compression：legacy plan、split plan 的 128/256/512 threads。
- Pulse Doppler：legacy、fused pack 的 128/256/512 threads。
- correlate2d：generic、8×32、16×16、32×8、16×32、32×16 shared-halo。
- 线性逐元素：波形和 B-spline 的 tiled element grouping，含 M50/M75/M90
  工作集档位；two_day profile 保留 M50/M75/M90 手工锚点及 64/128/256/512
  线程代表，不展开完整 generated 矩阵。M75/M90 的 `batch_tile` 会进入实际每线程
  处理 tile 数。
- 行归约：FM demod 和 peak-finding 的 contiguous-row tile，含 M50/M75/M90
  候选。
- FIR：real/complex `firfilter` 与 `lfilter` 共用有限的 1/2/4/8
  outputs-per-thread registry；只有实际进入 shared FIR 分支且语义满足的 workload
  才会应用该候选，其他 `lfilter` 通用递归路径保留静态回退。
- 任务：Task1 的输入构造线程配置；Task2 的 direct 与 fixed radix-2 FFT 路由和线程
  配置。任务候选以完整任务 GPU E2E 排序，公共算子阶段仍查冻结后的算子 cache。
- Window、Spectral、Filtering、Wavelet、RadarAux、Correlate1d、Kalman 和
  FilterDesignGpu 已接入真实 GPU dispatch 的有限候选矩阵；候选会改变线程、route、
  batch、stage 或实际 workspace 使用，且每个候选都记录 dispatch trace。
- `filter_design/kaiser_beta`、`filter_design/kaiser_atten`、
  `filter_design/cmplx_sort` 和 `radartools/cfar_alpha` 明确保留
  `static_operator`：它们是 Host 标量/CPU sort 辅助逻辑，没有可独立调度的 C500
  GPU 路径，不伪造候选；仍执行全量正确性和输入刷新检查。

候选均为源码中预编译的有限变体。`full` profile 仍可用于后续更长的全量探索；当前
交付运行使用 `task_appendix + two_day`，正好覆盖 53 个算子和 318 个算子 workload。
运行时只接受完整
`operator + shape + semantic + dtype/layout + device fingerprint + registry`
的 exact key；cache miss、损坏、设备不匹配、资源不足或候选未实际生效时回退
当前静态路径。PlanMany 不在候选注册表中，15 GiB 设备缓存上限和单块 8 GiB
上限也不属于本次调优参数，保持原值不变。

`M50/M75/M90` 是候选真实工作集档位，不是显存预分配命令，也不是显存占用目标。
显存占用不参与候选排序、cache 入选或最终性能 PASS/FAIL。调优器不会通过 dummy
allocation 填充显存；workspace 只能来自实际计算。线程数、shared memory、workspace
上限、当前可用显存和 shape 合法性仍是资源安全检查，失败时必须回退静态路径。
