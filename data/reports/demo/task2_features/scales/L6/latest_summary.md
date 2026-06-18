# Task 2 Feature Localization Demo

## Scenario

- scale_level: `L6`
- scale_value: `294912`
- fs: `1e+06`
- num_frames: `96`
- samples_per_frame: `3072`
- template_length: `768`
- target_start_sample_0: `660`
- target_step_per_frame: `3`
- interferer_start_sample: `1920`
- snr_db: `12`

## Consistency

- cpu_gpu_track_match: `true`
- gpu_matches_truth_within_tolerance: `true`
- gpu_kalman_rmse: `0.5268` samples

## Error

| field | mixed_error | max_abs | max_rel | rmse |
| --- | ---: | ---: | ---: | ---: |
| filtered | 3.551405e-06 | 1.311641e-06 | 5.819851e-05 | 8.426954e-08 |
| correlate | 7.265051e-06 | 1.192093e-06 | 1.135148e-04 | 3.704746e-08 |
| spectrogram | 9.139476e-07 | 2.980232e-08 | 1.236735e+00 | 3.726499e-09 |
| cwt | 1.307153e-06 | 7.493670e-07 | 6.506193e+00 | 7.467467e-08 |
| feature_score | 7.020296e-05 | 1.853332e-06 | 3.637421e-02 | 1.313059e-07 |
| kalman_track | 8.532423e-04 | 1.101440e+00 | 8.532423e-04 | 5.267832e-01 |

## Timing

| stage | cpu_ms | gpu_ms |
| --- | ---: | ---: |
| filter | 33.150646 | 7.673055 |
| demod | 10.042747 | 0.213091 |
| correlate | 5951.513184 | 208.685165 |
| spectrogram | 53.135437 | 94.622375 |
| cwt | 3392.093506 | 76.724785 |
| feature_fusion | 1.630536 | 0.578682 |
| kalman | 0.133601 | 0.162541 |
| total | 9441.700195 | 388.659668 |

## Validation

- pass: `true`
- repeat_runs: `3`
- cuda_free_delta_mib: `-48.000`
- rss_current_delta_mib: `386.938`

## Artifacts

- inputs: `data/generated/demo/task2_features/input/`
- samples: `data/generated/demo/task2_features/output_samples/`
- metrics: `data/reports/demo/task2_features/latest_metrics.json`
- timings: `data/reports/demo/task2_features/latest_stage_timings.csv`
- figures: run `python3 demo/task2_features/visualize_task2.py`
