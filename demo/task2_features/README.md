# Task 2 Features Demo

## Build

```bash
./scripts/build.sh --build-dir build-zx --target task2_features_demo
```

## Run

```bash
./build-zx/demo/task2_features/task2_features_demo
```

## Outputs

- `data/generated/demo/task2_features/input/`
- `data/generated/demo/task2_features/output_samples/`
- `data/reports/demo/task2_features/final/summary.md`
- `data/reports/demo/task2_features/final/metrics.json`
- `data/reports/demo/task2_features/final/stage_timings.csv`
- `data/reports/demo/task2_features/final/step_metrics.csv`
- `data/reports/demo/task2_features/final/step_metrics.json`

`latest_summary.md` and `latest_metrics.json` include `mixed_error` for each CPU/GPU comparison. The metric uses absolute error near zero-valued CPU references and relative error elsewhere, matching the unit benchmark reporting policy.

`scripts/demo.sh --build-dir build-zx --no-build --scale-sweep` 生成 L1-L6
结构化报告，不自动作图。

## Fixed Scenario

Equivalent to scale `L3`.

- `fs = 1e6`
- `num_frames = 48`
- `samples_per_frame = 1024`
- `template_length = 256`
- `target_start_sample_0 = 220`
- `target_step_per_frame = 3`
- `interferer_start_sample = 640`
- `target_amplitude = 1.0`
- `interferer_amplitude = 0.45`
- `snr_db = 12`
- `seed = 20260414`

## Scale Levels

The demo accepts `--scale-level 1..6`. If omitted, it uses the fixed `L3`
scenario. `scale_value` is
`num_frames * samples_per_frame`, and `rx_shape` is
`num_frames x samples_per_frame`.

| level | num_frames | samples_per_frame | rx_shape | template_length | target_start_sample_0 | interferer_start_sample | interferer_length | representative_frame_index | filter_numtaps | spectrogram nperseg/noverlap/nfft | scale_value |
|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---|---:|
| L1 | 16 | 512 | 16 x 512 | 128 | 110 | 320 | 128 | 8 | 65 | 64 / 48 / 128 | 8192 |
| L2 | 32 | 768 | 32 x 768 | 192 | 165 | 480 | 192 | 16 | 97 | 96 / 72 / 128 | 24576 |
| L3 | 48 | 1024 | 48 x 1024 | 256 | 220 | 640 | 256 | 24 | 129 | 128 / 96 / 256 | 49152 |
| L4 | 64 | 1536 | 64 x 1536 | 384 | 330 | 960 | 384 | 32 | 161 | 192 / 144 / 256 | 98304 |
| L5 | 80 | 2048 | 80 x 2048 | 512 | 440 | 1280 | 512 | 40 | 193 | 256 / 192 / 512 | 163840 |
| L6 | 96 | 3072 | 96 x 3072 | 768 | 660 | 1920 | 768 | 48 | 257 | 384 / 288 / 512 | 294912 |
