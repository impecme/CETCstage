# Task1 Radar Demo

## Build

```bash
./scripts/build.sh --build-dir build-zx --target task1_radar_demo
```

## Run

```bash
./build-zx/demo/task1_radar/task1_radar_demo
```

## Outputs

- `data/generated/demo/task1_radar/input/`
- `data/generated/demo/task1_radar/output_samples/`
- `data/reports/autotune/demo/task1_radar/summary.csv`
- `data/reports/autotune/demo/task1_radar/operators/L1.csv` ... `L6.csv`

GPU 正式路径在 Device 端生成 chirp、延迟、多普勒和噪声；CPU/GPU 使用相同 seed 和计数式 RNG。
`summary.csv` 同时记录 input/operator/e2e 三类误差，算子 CSV 记录各实际算子的 CPU/GPU 时间和误差。

`scripts/performance.sh --tasks --task task1 --build-dir build-zx --no-build --scale all` 生成 L1-L6
结构化报告，不自动作图。

## Fixed Scenario

- single-target high-parallelism scenario, equivalent to scale `L6`
- `fs=1e6`
- `num_pulses=128`
- `samples_per_pulse=4096`
- `template_length=1024`
- `prf=2000`
- `delay_samples=768`
- `doppler_hz=125`
- `snr_db=20`
- random seed `20260414`

## Scale Levels

The demo accepts `--scale-level 1..6`. If omitted, it uses the fixed `L6`
scenario. `scale_value` is
`num_pulses * samples_per_pulse`, and `rx_shape` is
`num_pulses x samples_per_pulse`.

| level | num_pulses | samples_per_pulse | rx_shape | template_length | delay_samples | pulse_compression_nfft | pulse_doppler_nfft | scale_value |
|---:|---:|---:|---|---:|---:|---:|---:|---:|
| L1 | 32 | 128 | 32 x 128 | 32 | 24 | 128 | 32 | 4096 |
| L2 | 48 | 256 | 48 x 256 | 64 | 48 | 256 | 64 | 12288 |
| L3 | 64 | 256 | 64 x 256 | 64 | 48 | 256 | 64 | 16384 |
| L4 | 96 | 512 | 96 x 512 | 128 | 96 | 512 | 128 | 49152 |
| L5 | 128 | 1024 | 128 x 1024 | 256 | 192 | 1024 | 128 | 131072 |
| L6 | 128 | 4096 | 128 x 4096 | 1024 | 768 | 4096 | 128 | 524288 |
