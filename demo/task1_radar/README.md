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
- `data/reports/demo/task1_radar/final/summary.md`
- `data/reports/demo/task1_radar/final/metrics.json`
- `data/reports/demo/task1_radar/final/stage_timings.csv`
- `data/reports/demo/task1_radar/final/step_metrics.csv`
- `data/reports/demo/task1_radar/final/step_metrics.json`

`latest_summary.md` and `latest_metrics.json` include `mixed_error` for each CPU/GPU comparison. The metric uses absolute error near zero-valued CPU references and relative error elsewhere, matching the unit benchmark reporting policy.

`scripts/demo.sh --build-dir build-zx --no-build --scale-sweep` 生成 L1-L6
结构化报告，不自动作图。

## Fixed Scenario

- single-target baseline, equivalent to scale `L3`
- `fs=1e6`
- `num_pulses=64`
- `samples_per_pulse=256`
- `template_length=64`
- `prf=2000`
- `delay_samples=48`
- `doppler_hz=125`
- `snr_db=20`
- random seed `20260414`

## Scale Levels

The demo accepts `--scale-level 1..6`. If omitted, it uses the fixed `L3`
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
| L6 | 192 | 1536 | 192 x 1536 | 384 | 288 | 2048 | 256 | 294912 |
