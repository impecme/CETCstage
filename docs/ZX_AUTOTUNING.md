# 中科芯 C500 全量离线自动调优

## 运行方式

自动调优是显式执行的离线流程，不在生产算子调用中 benchmark，也不做 JIT：

```bash
cmake --build build-zx --target zx_operator_autotune
```

该 target 依赖 `tests/unit` 中已配置的算子测试程序，并通过
`scripts/performance.sh` 使用冻结基线逐候选运行。注册表覆盖
`tests/contracts/operator_sets.json` 的 81 个算子、L1-L6 六个精确规模；当前
dry-run 共展开 248 个候选/算子组合。正式调优第一轮测量全部候选，第二轮只
复测每个算子的静态路径和第一轮胜者；只有第二轮仍然更快的候选才写入 cache。
结果目录按 `round1/` 和 `round2_winner_against_static/` 分开保存，最终查表 cache
和可发布报告保存在仓库 `data/` 目录。也可以直接运行脚本：

```bash
python3 scripts/zx_operator_autotune.py \
  --frozen-baseline data/baseline \
  --output-root data/reports/autotune/tuning_runs \
  --cache-output data/tuning/zx_tuning.json \
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
`zx-c500-all81-v2` 精确匹配。关闭缓存、cache miss、JSON 损坏、设备不匹配、候选
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
  工作集档位；M75/M90 的 `batch_tile` 会进入实际每线程处理 tile 数。
- 行归约：FM demod 和 peak-finding 的 contiguous-row tile，含 M50/M75/M90
  候选。
- FIR：real/complex `firfilter` 与 `lfilter` 共用有限的 1/2/4/8
  outputs-per-thread registry；只有实际进入 shared FIR 分支且语义满足的 workload
  才会应用该候选，其他 `lfilter` 通用递归路径保留静态回退。
- 其余没有已验证可安全改变 tile、batch、plan 或 workspace 的算子保留
  `static_operator`，仍执行全量正确性和输入刷新检查，不伪造候选。

候选均为源码中预编译的有限变体。运行时只接受完整
`operator + shape + semantic + dtype/layout + device fingerprint + registry`
的 exact key；cache miss、损坏、设备不匹配、资源不足或候选未实际生效时回退
当前静态路径。PlanMany 不在候选注册表中，15 GiB 设备缓存上限和单块 8 GiB
上限也不属于本次调优参数，保持原值不变。

`M50/M75/M90` 是候选真实工作集档位，不是显存预分配命令，也不是显存占用目标。
显存占用不参与候选排序、cache 入选或最终性能 PASS/FAIL。调优器不会通过 dummy
allocation 填充显存；workspace 只能来自实际计算。线程数、shared memory、workspace
上限、当前可用显存和 shape 合法性仍是资源安全检查，失败时必须回退静态路径。
