# V7 演示 Top30 算子

## 选择口径

- 数据源：V6-0141 最终 81 算子、L1-L6、warmup `5`、repeat `30`
  性能终测。
- 排序字段：L6 `gpu_e2e_speedup` 从高到低。
- 演示集合固定为前 30 项，定义在
  `scripts/test/operator_sets.json` 的 `demo_top30`。
- 现场使用 `large-gpu` L6：线性类为 `16777216` 点，FFT 类为
  `1048576` 点；二次复杂度类保持 `8192`，避免 OOM 和超时。

## 排名

| 排名 | 算子 | V6 L6 E2E 加速比 |
| ---: | --- | ---: |
| 1 | `wavelets/cwt` | `375.788x` |
| 2 | `windows/general_gaussian` | `226.150x` |
| 3 | `windows/kaiser` | `199.113x` |
| 4 | `filtering/wiener` | `196.179x` |
| 5 | `spectral/lombscargle` | `187.117x` |
| 6 | `windows/taylor` | `102.560x` |
| 7 | `windows/flattop` | `93.479x` |
| 8 | `windows/general_cosine` | `90.827x` |
| 9 | `waveforms/gausspulse` | `83.320x` |
| 10 | `windows/gaussian` | `81.505x` |
| 11 | `wavelets/morlet` | `75.676x` |
| 12 | `windows/blackmanharris` | `75.112x` |
| 13 | `windows/nuttall` | `73.254x` |
| 14 | `waveforms/chirp` | `65.604x` |
| 15 | `radartools/pulse_compression` | `65.456x` |
| 16 | `windows/cosine` | `60.641x` |
| 17 | `windows/exponential` | `59.731x` |
| 18 | `filtering/channelize_poly` | `55.752x` |
| 19 | `windows/blackman` | `52.134x` |
| 20 | `radartools/ambgfun` | `51.099x` |
| 21 | `wavelets/morlet2` | `50.138x` |
| 22 | `windows/hamming` | `50.138x` |
| 23 | `waveforms/square` | `49.233x` |
| 24 | `spectral/vectorstrength` | `45.289x` |
| 25 | `bsplines/gauss_spline` | `43.084x` |
| 26 | `windows/bohman` | `41.491x` |
| 27 | `filtering/lfilter_zi` | `41.483x` |
| 28 | `peak_finding/argrelmin` | `41.131x` |
| 29 | `peak_finding/argrelextrema` | `40.842x` |
| 30 | `peak_finding/argrelmax` | `38.179x` |

原始证据：
`/home/usr_04/CETC_garbage/cetc_v6_0141_pull_L11ItB5U/extracted/`
`cetc_v6_0141_v6_8_performance_20260716_131750/benchmark/`
`latest_all_ops_scale_benchmark.csv`。
